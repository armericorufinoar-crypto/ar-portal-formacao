-- =====================================================================
-- 017_treino_sessao.sql  ·  Fase 2: sessão diária, banco de erros, sequência, meta de turma
-- Base: Especificação AR Formação (Modo Treino) APROVADA 13/11/2026 + decisões de 13/11 (recomendadas).
-- ESTADO: RASCUNHO PARA REVISÃO. Não executar sem autorização expressa.
-- Depende de: 015_treino_niveis.sql (já executada). Não depende da 016.
-- Não altera: av_test_*, pauta, diagnóstico de competências, pagamentos.
-- Re-executável: índices/tabela com «if not exists», funções com «create or replace».
--
-- DECISÕES APLICADAS
--  1. Sábado é neutro: sem sessão, não falha a sequência e não gasta a folga.
--  2. Semana da meta: domingo a sábado.
--  3. Tema da semana: a aula mais recente com data <= hoje (av_cohort_aulas); sem datas,
--     usa av_cohorts.current_theme. Quinta e sexta usam os temas de aulas anteriores.
--  4. Rotação por dia da semana, pelo «kind», com recurso a qualquer tipo se faltar:
--     dom vf/mc · seg case/mc · ter num/mc · qua case/mc · qui integra tema anterior · sex revisão.
--  5. Formando sem turma treina só com o nível (sem tema e sem meta de turma).
--  6. Inclui a correcção da validação de av_save_profile (valores em falta).
--  7. Meta de turma fixa em 80% (constante nesta migração; não há coluna em av_train_settings).
--  8. Tipo «case» exige correct_index nesta versão; scoring_key fica por usar.
--
-- CONTRATO COM O BROWSER (o que o formando recebe)
--  av_train_session() -> { day, rest, empty, level, minutes, theme, total, answered, correct,
--      completed, items:[ { id, kind, statement, context, options, source, answered, correct } ] }
--      · options: vf = null · mc/case = ["texto",...] · order = [ {"i":índice_original,"t":"texto"},... ]
--        (já baralhadas no servidor; o formando devolve a ordem como lista de «i»).
--      · NUNCA inclui resposta certa, explicação, tolerância, correct_order, scoring_key.
--  av_train_answer(question, answer) -> { repeat, correct, solution, explanation, total, answered,
--      correct_total, completed, streak }   (a solução só chega aqui, depois de responder)
--      · answer: vf = true|false · mc/case = índice · num = número · order = [índices originais]
--  Códigos de erro: apenas_formando, formando_inactivo, sem_perfil_treino, pergunta_nao_servida,
--      resposta_invalida, tipo_nao_suportado, turma_invalida, sem_permissao, respostas_invalidas.
-- =====================================================================
begin;

-- 0. Salvaguarda: a 015 tem de estar instalada.
do $$
declare t text;
begin
  foreach t in array array['av_train_settings','av_cohorts','av_cohort_aulas','av_student_profile',
                           'av_train_questions','av_train_progress','av_train_days','av_staff'] loop
    if to_regclass('public.'||t) is null then
      raise exception 'Falta a tabela public.% : execute primeiro a 015_treino_niveis.sql', t;
    end if;
  end loop;
  if to_regprocedure('public.av_train_staff_id()') is null
     or to_regprocedure('public.av_train_role()') is null
     or to_regprocedure('public.av_train_is_staff()') is null then
    raise exception 'Faltam as funções auxiliares da 015 (av_train_role, av_train_staff_id, av_train_is_staff).';
  end if;
end $$;

-- 1. Índices do banco de treino
create unique index if not exists av_train_questions_source_uq
  on public.av_train_questions (source_question_id) where source_question_id is not null;
create index if not exists av_train_questions_active_theme_ix
  on public.av_train_questions (active, theme);

-- 2. Perguntas servidas em cada dia (fixa a sessão, impede responder o que não foi servido
--    e responder duas vezes). Só as funções escrevem; o formando só lê as suas linhas.
create table if not exists public.av_train_items (
  staff_id    uuid not null references public.av_staff(id) on delete cascade,
  day         date not null,
  position    int  not null,
  question_id uuid not null references public.av_train_questions(id) on delete cascade,
  source      text not null check (source in ('erro','tema','revisao')),
  answered_at timestamptz,
  correct     boolean,
  given       jsonb,
  primary key (staff_id, day, question_id),
  unique (staff_id, day, position)
);
create index if not exists av_train_items_day_ix on public.av_train_items (day);
alter table public.av_train_items enable row level security;
drop policy if exists ti_sel on public.av_train_items;
create policy ti_sel on public.av_train_items for select
  using (public.av_train_is_staff() or staff_id = public.av_train_staff_id());

-- 3. Auxiliares internos (não expostos ao browser)

-- Dia de hoje em Luanda (UTC+1, sem hora de Verão).
create or replace function public.av_train_today() returns date
language sql stable as $$ select (now() at time zone 'Africa/Luanda')::date $$;

-- Tema da semana (cur) e temas de aulas anteriores (prev) para uma turma.
create or replace function public.av_train_themes(p_cohort uuid, p_day date, out cur text, out prev text[])
language plpgsql stable security definer set search_path = public as $$
declare v_no int;
begin
  prev := '{}';
  if p_cohort is null then return; end if;
  select a.lesson_no, btrim(a.theme) into v_no, cur
    from public.av_cohort_aulas a
   where a.cohort_id = p_cohort and a.lesson_date is not null and a.lesson_date <= p_day
     and nullif(btrim(a.theme),'') is not null
   order by a.lesson_date desc limit 1;
  if cur is null then
    select nullif(btrim(c.current_theme),'') into cur from public.av_cohorts c where c.id = p_cohort;
    if cur is not null then
      select a.lesson_no into v_no from public.av_cohort_aulas a
       where a.cohort_id = p_cohort and lower(btrim(a.theme)) = lower(cur) limit 1;
    end if;
  end if;
  if v_no is not null then
    select coalesce(array_agg(btrim(a.theme) order by a.lesson_no), '{}') into prev
      from public.av_cohort_aulas a
     where a.cohort_id = p_cohort and a.lesson_no < v_no and nullif(btrim(a.theme),'') is not null;
  end if;
end $$;

-- Escolhe até p_limit perguntas para o dia e regista-as em av_train_items.
-- Exclui as que já estão no dia e as que estão no banco de erros (essas entram pela fase dos erros).
-- Ordem: 1) novas primeiro (ou já vistas primeiro, se p_prefer_seen) 2) tipo preferido 3) mais antigas 4) acaso.
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
         and not exists (select 1 from public.av_train_items i
                          where i.staff_id = p_staff and i.day = p_day and i.question_id = q.id)
       order by o1, o2, o3, o4
       limit p_limit
    ) s;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- Sequência: dias seguidos com sessão concluída. Sábado é neutro. Um dia falhado é tolerado
-- se não houver outro falhado nos 7 dias anteriores; o segundo falhado na janela volta a zero.
-- O dia de hoje conta se concluído, mas não é falha enquanto não terminar.
create or replace function public.av_train_streak(p_staff uuid, p_today date) returns int
language plpgsql stable security definer set search_path = public as $$
declare v_first date; v_done date[]; v_n int := 0; v_last date; d date; i int;
begin
  select min(day) into v_first from public.av_train_items where staff_id = p_staff and day <= p_today;
  if v_first is null then return 0; end if;
  select coalesce(array_agg(day), '{}') into v_done
    from public.av_train_days where staff_id = p_staff and completed and day <= p_today;
  for i in 0 .. (p_today - v_first - 1) loop
    d := v_first + i;
    if extract(dow from d) = 6 then continue; end if;
    if d = any(v_done) then
      v_n := v_n + 1;
    else
      if v_last is not null and (d - v_last) < 7 then v_n := 0; end if;
      v_last := d;
    end if;
  end loop;
  if p_today = any(v_done) then v_n := v_n + 1; end if;
  return v_n;
end $$;

-- Meta de turma: formandos activos na semana (domingo a sábado) com >= active_min_days sessões concluídas.
create or replace function public.av_train_cohort_week_calc(p_cohort uuid, p_day date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_ws date; v_min int; v_total int; v_act int;
begin
  v_ws := p_day - extract(dow from p_day)::int;
  select active_min_days into v_min from public.av_train_settings where id = 1;
  select count(*) into v_total from public.av_staff where cohort_id = p_cohort and status = 'Activo';
  select count(*) into v_act from (
    select d.staff_id
      from public.av_train_days d join public.av_staff s on s.id = d.staff_id
     where s.cohort_id = p_cohort and s.status = 'Activo' and d.completed
       and d.day between v_ws and v_ws + 6
     group by d.staff_id having count(*) >= coalesce(v_min, 3)) x;
  return jsonb_build_object(
    'cohort_id', p_cohort, 'week_start', v_ws, 'active', v_act, 'total', v_total, 'goal_pct', 80,
    'pct', case when v_total > 0 then round(100.0 * v_act / v_total)::int else 0 end,
    'goal_met', v_total > 0 and v_act * 100 >= 80 * v_total);
end $$;

-- 4. Funções expostas ao formando

-- 4.1 Sessão do dia (cria-a na primeira chamada do dia; nas seguintes devolve a mesma).
create or replace function public.av_train_session() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_staff uuid := public.av_train_staff_id();
  v_today date := public.av_train_today();
  v_dow   int  := extract(dow from public.av_train_today())::int;
  v_lvl text; v_cohort uuid; v_status text;
  v_cfg public.av_train_settings%rowtype;
  v_size jsonb; v_n int; v_olde int; v_have int; v_miss int; v_got int;
  v_cur text; v_prev text[]; v_cur_arr text[]; v_all text[];
  v_list jsonb; v_tot int; v_ans int; v_ok int;
begin
  if v_staff is null or public.av_train_role() <> 'collaborator' then raise exception 'apenas_formando'; end if;
  select s.status, s.cohort_id into v_status, v_cohort from public.av_staff s where s.id = v_staff;
  if v_status is distinct from 'Activo' then raise exception 'formando_inactivo'; end if;
  select sp.level_final into v_lvl from public.av_student_profile sp where sp.staff_id = v_staff;
  if v_lvl is null then raise exception 'sem_perfil_treino'; end if;

  if v_dow = 6 then   -- sábado: aula presencial, sem sessão
    return jsonb_build_object('day', v_today, 'rest', true, 'empty', false, 'level', v_lvl,
      'items', '[]'::jsonb, 'total', 0, 'answered', 0, 'correct', 0, 'completed', false);
  end if;

  select * into v_cfg from public.av_train_settings where id = 1;
  v_size := v_cfg.session_sizes -> v_lvl;
  v_n    := coalesce((v_size->>'questions')::int, 5);
  v_olde := coalesce((v_size->>'old_errors')::int, 3);

  perform pg_advisory_xact_lock(hashtext('av_train:' || v_staff::text || ':' || v_today::text));

  select t.cur, t.prev into v_cur, v_prev from public.av_train_themes(v_cohort, v_today) t;
  v_cur_arr := case when v_cur is null then null else array[v_cur] end;
  v_all     := case when v_cur is null then null else array[v_cur] || coalesce(v_prev, '{}') end;

  select count(*) into v_have from public.av_train_items where staff_id = v_staff and day = v_today;
  if v_have = 0 then
    -- (a) erros vencidos, do mais antigo para o mais recente
    with c as (
      select p.question_id
        from public.av_train_progress p join public.av_train_questions q on q.id = p.question_id
       where p.staff_id = v_staff and p.next_due is not null and p.next_due <= v_today and q.active
       order by p.next_due, random()
       limit v_olde)
    insert into public.av_train_items (staff_id, day, position, question_id, source)
    select v_staff, v_today, row_number() over (), c.question_id, 'erro' from c;

    select count(*) into v_have from public.av_train_items where staff_id = v_staff and day = v_today;
    v_miss := v_n - v_have;

    -- (b) o resto, conforme o dia da semana
    if v_dow = 5 then
      v_got := public.av_train_pick(v_staff, v_today, v_lvl, v_all, null, v_miss, 'revisao', true);
    elsif v_dow = 4 and coalesce(cardinality(v_prev), 0) > 0 then
      v_got := public.av_train_pick(v_staff, v_today, v_lvl, v_prev, array['case','mc'], (v_miss + 1) / 2, 'tema', false);
      v_got := public.av_train_pick(v_staff, v_today, v_lvl, v_cur_arr, array['case','mc'], v_miss - v_got, 'tema', false);
    else
      v_got := public.av_train_pick(v_staff, v_today, v_lvl, v_cur_arr,
        case v_dow when 0 then array['vf','mc'] when 1 then array['case','mc']
                   when 2 then array['num','mc'] when 3 then array['case','mc'] else null end,
        v_miss, 'tema', false);
    end if;

    -- (c) recurso: temas vistos, depois qualquer tema do nível
    select count(*) into v_have from public.av_train_items where staff_id = v_staff and day = v_today;
    v_miss := v_n - v_have;
    if v_miss > 0 and v_all is not null then
      v_got := public.av_train_pick(v_staff, v_today, v_lvl, v_all, null, v_miss, 'tema', false);
      select count(*) into v_have from public.av_train_items where staff_id = v_staff and day = v_today;
      v_miss := v_n - v_have;
    end if;
    if v_miss > 0 then
      v_got := public.av_train_pick(v_staff, v_today, v_lvl, null, null, v_miss, 'tema', false);
    end if;
  end if;

  -- Payload SEM resposta certa, SEM explicação. As opções de «order» são baralhadas aqui.
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', q.id, 'kind', q.kind, 'statement', q.statement, 'context', q.case_context,
           'options', case when q.kind = 'order' then
                        (select jsonb_agg(jsonb_build_object('i', o.ord - 1, 't', o.t)
                                 order by md5(v_staff::text || v_today::text || q.id::text || o.ord::text))
                           from jsonb_array_elements_text(q.options) with ordinality as o(t, ord))
                      else q.options end,
           'source', i.source, 'answered', i.answered_at is not null, 'correct', i.correct
         ) order by i.position), '[]'::jsonb)
    into v_list
    from public.av_train_items i join public.av_train_questions q on q.id = i.question_id
   where i.staff_id = v_staff and i.day = v_today;

  select count(*), count(*) filter (where answered_at is not null), count(*) filter (where correct)
    into v_tot, v_ans, v_ok
    from public.av_train_items where staff_id = v_staff and day = v_today;

  return jsonb_build_object('day', v_today, 'rest', false, 'empty', v_tot = 0, 'level', v_lvl,
    'minutes', coalesce((v_size->>'min')::int, 3), 'theme', v_cur, 'items', v_list,
    'total', v_tot, 'answered', v_ans, 'correct', v_ok, 'completed', v_tot > 0 and v_ans = v_tot);
end $$;

-- 4.2 Responder (corrige no servidor; a solução só sai depois de responder).
create or replace function public.av_train_answer(p_question uuid, p_answer jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_staff uuid := public.av_train_staff_id();
  v_today date := public.av_train_today();
  v_item public.av_train_items%rowtype;
  v_q    public.av_train_questions%rowtype;
  v_cfg  public.av_train_settings%rowtype;
  v_p    public.av_train_progress%rowtype;
  v_ok boolean; v_idx int; v_arr int[]; v_n int; v_streak int; v_due date; v_sol jsonb;
  v_tot int; v_ans int; v_cor int; v_done boolean; v_found boolean; v_repeat boolean := false;
begin
  if v_staff is null or public.av_train_role() <> 'collaborator' then raise exception 'apenas_formando'; end if;
  if p_answer is null or jsonb_typeof(p_answer) = 'null' then raise exception 'resposta_invalida'; end if;

  perform pg_advisory_xact_lock(hashtext('av_train:' || v_staff::text || ':' || v_today::text));
  select * into v_item from public.av_train_items
   where staff_id = v_staff and day = v_today and question_id = p_question for update;
  if not found then raise exception 'pergunta_nao_servida'; end if;
  select * into v_q from public.av_train_questions where id = p_question;

  v_sol := case v_q.kind
    when 'vf' then jsonb_build_object('answer', v_q.answer_bool)
    when 'mc' then jsonb_build_object('index', v_q.correct_index, 'text', v_q.options ->> v_q.correct_index)
    when 'case' then jsonb_build_object('index', v_q.correct_index, 'text', v_q.options ->> v_q.correct_index)
    when 'num' then jsonb_build_object('value', v_q.expected_value, 'tolerance', coalesce(v_q.tolerance, 0))
    when 'order' then jsonb_build_object('order', to_jsonb(v_q.correct_order),
        'texts', (select jsonb_agg(v_q.options ->> t.x order by t.ord)
                    from unnest(v_q.correct_order) with ordinality as t(x, ord)))
    else null end;

  if v_item.answered_at is not null then
    v_repeat := true;
    v_ok := v_item.correct;
  else
    begin
      if v_q.kind = 'vf' then
        if jsonb_typeof(p_answer) <> 'boolean' then raise exception 'resposta_invalida'; end if;
        v_ok := (p_answer #>> '{}')::boolean = v_q.answer_bool;
      elsif v_q.kind in ('mc','case') then
        if v_q.correct_index is null then raise exception 'tipo_nao_suportado'; end if;
        if jsonb_typeof(p_answer) <> 'number' or (p_answer #>> '{}') !~ '^[0-9]+$' then
          raise exception 'resposta_invalida'; end if;
        v_idx := (p_answer #>> '{}')::int;
        if v_idx >= jsonb_array_length(v_q.options) then raise exception 'resposta_invalida'; end if;
        v_ok := v_idx = v_q.correct_index;
      elsif v_q.kind = 'num' then
        if jsonb_typeof(p_answer) <> 'number' then raise exception 'resposta_invalida'; end if;
        v_ok := abs((p_answer #>> '{}')::numeric - v_q.expected_value) <= coalesce(v_q.tolerance, 0);
      elsif v_q.kind = 'order' then
        if jsonb_typeof(p_answer) <> 'array' then raise exception 'resposta_invalida'; end if;
        v_n := jsonb_array_length(v_q.options);
        if jsonb_array_length(p_answer) <> v_n
           or exists (select 1 from jsonb_array_elements_text(p_answer) as e(x) where e.x !~ '^[0-9]+$') then
          raise exception 'resposta_invalida'; end if;
        select array_agg(e.x::int order by e.ord) into v_arr
          from jsonb_array_elements_text(p_answer) with ordinality as e(x, ord);
        if (select count(distinct u) from unnest(v_arr) u where u < v_n) <> v_n then
          raise exception 'resposta_invalida'; end if;
        v_ok := v_arr = v_q.correct_order;
      else
        raise exception 'tipo_nao_suportado';
      end if;
    exception when data_exception then
      raise exception 'resposta_invalida';
    end;
    v_ok := coalesce(v_ok, false);

    -- Banco de erros: degraus em av_train_settings.ladder; sai após exit_streak acertos seguidos.
    select * into v_cfg from public.av_train_settings where id = 1;
    select * into v_p from public.av_train_progress where staff_id = v_staff and question_id = p_question for update;
    v_found := found;
    if v_ok then
      if v_found and v_p.next_due is not null then
        v_streak := v_p.streak + 1;
        if v_streak >= v_cfg.exit_streak then
          v_due := null;
        else
          v_due := v_today + coalesce((v_cfg.ladder ->> v_streak)::int,
                                      (v_cfg.ladder ->> (jsonb_array_length(v_cfg.ladder) - 1))::int, 1);
        end if;
      else
        v_streak := 0; v_due := null;
      end if;
    else
      v_streak := 0;
      v_due := v_today + coalesce((v_cfg.ladder ->> 0)::int, 1);
    end if;
    insert into public.av_train_progress (staff_id, question_id, streak, next_due, last_result, last_at)
    values (v_staff, p_question, v_streak, v_due, v_ok, now())
    on conflict (staff_id, question_id) do update
      set streak = excluded.streak, next_due = excluded.next_due,
          last_result = excluded.last_result, last_at = excluded.last_at;

    update public.av_train_items
       set answered_at = now(), correct = v_ok, given = p_answer
     where staff_id = v_staff and day = v_today and question_id = p_question;

    insert into public.av_train_days (staff_id, day, answered, correct, completed)
    select v_staff, v_today,
           count(*) filter (where answered_at is not null),
           count(*) filter (where correct),
           bool_and(answered_at is not null)
      from public.av_train_items where staff_id = v_staff and day = v_today
    on conflict (staff_id, day) do update
      set answered = excluded.answered, correct = excluded.correct, completed = excluded.completed;
  end if;

  select count(*), count(*) filter (where answered_at is not null), count(*) filter (where correct)
    into v_tot, v_ans, v_cor
    from public.av_train_items where staff_id = v_staff and day = v_today;
  v_done := v_tot > 0 and v_ans = v_tot;

  return jsonb_build_object('repeat', v_repeat, 'correct', v_ok, 'solution', v_sol,
    'explanation', v_q.explanation, 'total', v_tot, 'answered', v_ans, 'correct_total', v_cor,
    'completed', v_done,
    'streak', case when v_done then public.av_train_streak(v_staff, v_today) else null end);
end $$;

-- 4.3 Estado para o cartão do dia (não cria a sessão).
create or replace function public.av_train_state() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_staff uuid := public.av_train_staff_id();
  v_today date := public.av_train_today();
  v_dow int; v_lvl text; v_reass boolean; v_cohort uuid; v_cname text;
  v_cfg public.av_train_settings%rowtype; v_size jsonb; v_cur text;
  v_tot int; v_ans int; v_cor int; v_ws date; v_wd int; v_due int; v_bank int;
begin
  if v_staff is null or public.av_train_role() <> 'collaborator' then raise exception 'apenas_formando'; end if;
  v_dow := extract(dow from v_today)::int;
  select sp.level_final, sp.reassess_open into v_lvl, v_reass
    from public.av_student_profile sp where sp.staff_id = v_staff;
  if v_lvl is null then return jsonb_build_object('needs_profile', true, 'day', v_today); end if;

  select s.cohort_id, c.name into v_cohort, v_cname
    from public.av_staff s left join public.av_cohorts c on c.id = s.cohort_id where s.id = v_staff;
  select * into v_cfg from public.av_train_settings where id = 1;
  v_size := v_cfg.session_sizes -> v_lvl;
  select t.cur into v_cur from public.av_train_themes(v_cohort, v_today) t;

  select count(*), count(*) filter (where answered_at is not null), count(*) filter (where correct)
    into v_tot, v_ans, v_cor
    from public.av_train_items where staff_id = v_staff and day = v_today;

  v_ws := v_today - v_dow;
  select count(*) into v_wd from public.av_train_days
   where staff_id = v_staff and completed and day between v_ws and v_ws + 6;

  select count(*) filter (where p.next_due <= v_today), count(*) into v_due, v_bank
    from public.av_train_progress p join public.av_train_questions q on q.id = p.question_id
   where p.staff_id = v_staff and p.next_due is not null and q.active;

  return jsonb_build_object(
    'day', v_today, 'rest', v_dow = 6, 'level', v_lvl, 'reassess_open', coalesce(v_reass, false),
    'cohort', case when v_cohort is null then null else jsonb_build_object('id', v_cohort, 'name', v_cname) end,
    'theme', v_cur,
    'session', jsonb_build_object(
        'minutes', coalesce((v_size->>'min')::int, 3), 'questions', coalesce((v_size->>'questions')::int, 5),
        'total', case when v_tot > 0 then v_tot else coalesce((v_size->>'questions')::int, 5) end,
        'started', v_tot > 0, 'answered', v_ans, 'correct', v_cor, 'completed', v_tot > 0 and v_ans = v_tot),
    'errors', jsonb_build_object('due', v_due, 'total', v_bank),
    'streak', public.av_train_streak(v_staff, v_today),
    'week', jsonb_build_object('start', v_ws, 'days_done', v_wd, 'needed', v_cfg.active_min_days),
    'cohort_week', case when v_cohort is null then null
                        else public.av_train_cohort_week_calc(v_cohort, v_today) end);
end $$;

-- 4.4 Meta de turma, sem nomes. Formando: só a sua turma. Administração/formador: qualquer turma.
create or replace function public.av_cohort_week(p_cohort uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_role text := public.av_train_role(); v_my uuid; v_c uuid := p_cohort;
begin
  if v_role in ('admin','trainer') then
    if v_c is null then raise exception 'turma_invalida'; end if;
  elsif v_role = 'collaborator' then
    select s.cohort_id into v_my from public.av_staff s where s.id = public.av_train_staff_id();
    if v_my is null then return null; end if;
    if v_c is not null and v_c <> v_my then raise exception 'sem_permissao'; end if;
    v_c := v_my;
  else
    raise exception 'sem_permissao';
  end if;
  if not exists (select 1 from public.av_cohorts where id = v_c) then raise exception 'turma_invalida'; end if;
  return public.av_train_cohort_week_calc(v_c, public.av_train_today());
end $$;

-- 5. Correcção de av_save_profile (015): «null not in (...)» não rejeitava valores em falta.
--    Corpo igual ao da 015, com a validação à prova de nulos.
create or replace function public.av_save_profile(p_answers jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_staff uuid := public.av_train_staff_id();
  v_cycle int;
  v_lvl   text;
  v_lead  boolean;
  v_old   public.av_student_profile%rowtype;
  v_ans   jsonb;
  v_existed boolean;
begin
  if v_staff is null or public.av_train_role() <> 'collaborator' then
    raise exception 'apenas_formando';
  end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    raise exception 'respostas_invalidas';
  end if;
  if coalesce(p_answers->>'q1','') not in ('nao','preparacao','sim')
     or coalesce(p_answers->>'q3','') not in ('nunca','as_vezes','sempre')
     or coalesce(p_answers->>'q4','') not in ('nenhum','so_vendas','vendas_despesas','leads_vendas_despesas')
     or coalesce(p_answers->>'q5','') not in ('nenhuma','1a3','4mais')
     or coalesce(p_answers->>'q6','') not in ('so_eu','com_ajuda','delego') then
    raise exception 'respostas_invalidas';
  end if;
  if p_answers->>'q1' = 'sim' and coalesce(p_answers->>'q2','') not in ('lt1','1a3','gt3') then
    raise exception 'respostas_invalidas';
  end if;

  v_ans := jsonb_strip_nulls(jsonb_build_object(
    'q1', p_answers->>'q1',
    'q2', case when p_answers->>'q1' = 'sim' then p_answers->>'q2' end,
    'q3', p_answers->>'q3', 'q4', p_answers->>'q4',
    'q5', p_answers->>'q5', 'q6', p_answers->>'q6'));

  v_lvl  := public.av_level_from_answers(v_ans);
  v_lead := (v_ans->>'q1' = 'sim' and v_ans->>'q4' <> 'leads_vendas_despesas');
  select current_cycle into v_cycle from public.av_train_settings where id = 1;

  select * into v_old from public.av_student_profile where staff_id = v_staff;
  v_existed := found;
  if v_existed and not v_old.reassess_open then
    raise exception 'perfil_ja_preenchido';
  end if;

  insert into public.av_student_profile (staff_id, answers, level_auto, level_final, lead_flag, reassess_open, updated_at)
  values (v_staff, v_ans, v_lvl, v_lvl, v_lead, false, now())
  on conflict (staff_id) do update
    set answers = excluded.answers, level_auto = excluded.level_auto,
        level_final = excluded.level_final, lead_flag = excluded.lead_flag,
        reassess_open = false, updated_at = now();

  insert into public.av_level_history (staff_id, level, source, reason, cycle, created_by)
  values (v_staff, v_lvl, 'auto', case when v_existed then 'reavaliação' else 'perfil de entrada' end, v_cycle, auth.uid());

  return jsonb_build_object('level', v_lvl, 'lead_flag', v_lead);
end $$;

-- 6. Permissões. Auxiliares: ninguém de fora. Funções do formando: só utilizadores autenticados.
revoke all on function public.av_train_today(), public.av_train_themes(uuid, date),
  public.av_train_pick(uuid, date, text, text[], text[], int, text, boolean),
  public.av_train_streak(uuid, date), public.av_train_cohort_week_calc(uuid, date)
  from public, anon, authenticated;

revoke all on function public.av_train_session(), public.av_train_answer(uuid, jsonb),
  public.av_train_state(), public.av_cohort_week(uuid), public.av_save_profile(jsonb)
  from public, anon;
grant execute on function public.av_train_session(), public.av_train_answer(uuid, jsonb),
  public.av_train_state(), public.av_cohort_week(uuid), public.av_save_profile(jsonb)
  to authenticated;

commit;
