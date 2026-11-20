-- =====================================================================
-- 025_treino_sessao_link.sql  ·  Perguntas do Treino ligadas a sessões
-- Base: 015, 017 e 018 (já executadas). Não depende da 016. O número 025 foi escolhido por ser o
-- seguinte ao último que o portal referencia (024); se já existir uma 025, mude só o número do ficheiro.
-- ESTADO: RASCUNHO PARA REVISÃO. Não executar sem autorização expressa.
-- Não altera: av_test_*, pauta, diagnóstico, sessões, materiais, nem os dados das perguntas.
-- Re-executável: coluna e índice com «if not exists»; função com «create or replace».
--
-- O QUE FAZ
--  1. av_train_questions ganha session_id (opcional), com o MESMO tipo de av_sessions.id.
--     Ao apagar uma sessão, as perguntas não se apagam: ficam sem sessão (set null) e voltam
--     a ser servidas só pelo tema, como hoje.
--  2. av_train_pick (a função que escolhe as perguntas do dia) passa a nunca servir uma pergunta
--     ligada a uma sessão cuja data ainda não chegou («nunca matéria por dar»).
--     Perguntas SEM sessão continuam exactamente como antes.
--
-- O QUE NÃO FAZ (de propósito)
--  · Não filtra por área: av_sessions.area e av_staff.areas podem estar gravadas com nomes
--    antigos e o portal normaliza-os no cliente; comparar aqui poderia esconder perguntas.
--  · Não liga perguntas existentes. Ver o passo opcional no fim (preview e actualização manual).
--  · Não muda a ordem nem o tamanho da sessão do dia (isso é a fase seguinte: treino livre).
-- =====================================================================
begin;

-- 0. Salvaguardas
do $$
declare v_def text;
begin
  if to_regclass('public.av_train_questions') is null then
    raise exception 'Falta public.av_train_questions: execute primeiro a 015_treino_niveis.sql';
  end if;
  if to_regclass('public.av_sessions') is null then
    raise exception 'Falta public.av_sessions.';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='av_sessions' and column_name='session_date') then
    raise exception 'public.av_sessions não tem a coluna session_date.';
  end if;
  if to_regprocedure('public.av_train_pick(uuid,date,text,text[],text[],integer,text,boolean)') is null then
    raise exception 'Falta av_train_pick: execute primeiro a 017_treino_sessao.sql';
  end if;
  -- Esta migração substitui a função inteira. Se outra migração a alterou depois da 017,
  -- substituí-la apagaria essa alteração: nesse caso pára aqui.
  select pg_get_functiondef(to_regprocedure('public.av_train_pick(uuid,date,text,text[],text[],integer,text,boolean)')) into v_def;
  if v_def not like '%lower(btrim(x)) from unnest(p_themes)%' or v_def not like '%p.next_due is null%' then
    raise exception 'av_train_pick foi alterada depois da 017 (versão diferente da esperada). Envie a versão actual antes de executar.';
  end if;
end $$;

-- 1. Coluna session_id com o mesmo tipo do id das sessões
do $$
declare v_type text;
begin
  if exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='av_train_questions' and column_name='session_id') then
    return;
  end if;
  select format_type(a.atttypid, a.atttypmod) into v_type
    from pg_attribute a
   where a.attrelid = 'public.av_sessions'::regclass and a.attname = 'id' and not a.attisdropped;
  if v_type is null then raise exception 'Não consegui ler o tipo de av_sessions.id'; end if;
  execute format('alter table public.av_train_questions add column session_id %s references public.av_sessions(id) on delete set null', v_type);
end $$;

create index if not exists av_train_questions_session_ix
  on public.av_train_questions (session_id) where session_id is not null;

-- 2. Escolha das perguntas do dia: nunca matéria de uma sessão que ainda não aconteceu.
--    Igual à da 017, com UMA condição nova (a que menciona «ses»).
create or replace function public.av_train_pick(
  p_staff uuid, p_day date, p_level text, p_themes text[], p_kinds text[],
  p_limit int, p_source text, p_prefer_seen boolean default false) returns int
language plpgsql security definer set search_path = public as $$
declare v_n int; v_base int; v_th text[];
begin
  if p_limit is null or p_limit <= 0 then return 0; end if;
  if p_themes is not null and cardinality(p_themes) > 0 then
    v_th := array(select lower(btrim(x)) from unnest(p_themes) x);
  end if;
  select coalesce(max(position),0) into v_base
    from public.av_train_items where staff_id = p_staff and day = p_day;
  insert into public.av_train_items (staff_id, day, position, question_id, source)
  select p_staff, p_day, v_base + row_number() over (order by s.o1, s.o2, s.o3, s.o4), s.id, p_source
    from (
      select q.id,
             case when p_prefer_seen then (p.question_id is null)::int else (p.question_id is not null)::int end as o1,
             case when p_kinds is not null and q.kind = any(p_kinds) then 0 else 1 end as o2,
             p.last_at as o3,
             random() as o4
        from public.av_train_questions q
        left join public.av_train_progress p on p.staff_id = p_staff and p.question_id = q.id
       where q.active and p_level = any(q.levels)
         and (v_th is null or lower(btrim(coalesce(q.theme,''))) = any(v_th))
         and (p.question_id is null or p.next_due is null)
         and (q.session_id is null or exists (select 1 from public.av_sessions ses
                                               where ses.id = q.session_id and ses.session_date::date <= p_day))
         and not exists (select 1 from public.av_train_items i
                          where i.staff_id = p_staff and i.day = p_day and i.question_id = q.id)
       order by o1, o2, o3, o4
       limit p_limit
    ) s;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

revoke all on function public.av_train_pick(uuid, date, text, text[], text[], int, text, boolean)
  from public, anon, authenticated;

-- 3. PASSO OPCIONAL (não corre sozinho): ligar perguntas que já existem a sessões.
--    Primeiro veja o que ficaria ligado (só leitura). Exige que o TEMA da pergunta seja igual
--    ao TÍTULO da sessão (ignorando maiúsculas e espaços). Se houver títulos repetidos, ficam de fora.
--
--    select q.theme, s.title, s.session_date, count(*) as perguntas
--      from public.av_train_questions q
--      join public.av_sessions s on lower(btrim(s.title)) = lower(btrim(q.theme))
--     where q.session_id is null
--       and (select count(*) from public.av_sessions s2 where lower(btrim(s2.title)) = lower(btrim(q.theme))) = 1
--     group by q.theme, s.title, s.session_date order by s.session_date;
--
--    Depois de rever o resultado, para ligar:
--
--    update public.av_train_questions q set session_id = s.id
--      from public.av_sessions s
--     where q.session_id is null and lower(btrim(s.title)) = lower(btrim(q.theme))
--       and (select count(*) from public.av_sessions s2 where lower(btrim(s2.title)) = lower(btrim(q.theme))) = 1;

commit;
