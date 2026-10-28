-- 004_testes_escolha_multipla.sql
-- Testes com perguntas Verdadeiro/Falso e Escolha múltipla (uma só opção correcta).
-- Repetível sem erro. Corre numa só transacção: se algo falhar, nada fica alterado.
-- Não correr nenhum outro ficheiro "v12" de testes depois deste: substituiria as funções.
begin;

-- 0) Verificação prévia dos tipos esperados --------------------------------
do $$
declare r record; t text;
begin
  for r in select * from (values
      ('av_session_materials','id','uuid'),
      ('av_staff','id','uuid'),
      ('av_profiles','user_id','uuid'),
      ('av_profiles','staff_id','uuid')) v(tb, col, ty)
  loop
    select format_type(a.atttypid, a.atttypmod) into t
      from pg_attribute a
     where a.attrelid = ('public.' || r.tb)::regclass
       and a.attname = r.col and not a.attisdropped;
    if t is distinct from r.ty then
      raise exception 'Migração 004 interrompida: %.% é % (esperado %)', r.tb, r.col, t, r.ty;
    end if;
  end loop;

  select data_type into t from information_schema.columns
   where table_schema = 'public' and table_name = 'av_session_materials' and column_name = 'kind';
  if t is null or t not in ('text', 'character varying') then
    raise exception 'Migração 004 interrompida: av_session_materials.kind é % (esperado text)', t;
  end if;
end $$;

-- 1) Materiais: janela de abertura/fecho e tipo "teste" ---------------------
alter table public.av_session_materials
  add column if not exists opens_at  timestamptz,
  add column if not exists closes_at timestamptz;

do $$
declare c record;
begin
  for c in select conname from pg_constraint
            where conrelid = 'public.av_session_materials'::regclass
              and contype = 'c'
              and pg_get_constraintdef(oid) ilike '%kind%'
  loop
    execute format('alter table public.av_session_materials drop constraint %I', c.conname);
  end loop;
  alter table public.av_session_materials
    add constraint av_session_materials_kind_check
    check (kind in ('ficheiro', 'ligacao', 'teste'));
end $$;

-- 2) Perguntas ---------------------------------------------------------------
create table if not exists public.av_test_questions (
  id            uuid primary key default gen_random_uuid(),
  material_id   uuid not null references public.av_session_materials(id) on delete cascade,
  position      int  not null,
  kind          text not null default 'vf' check (kind in ('vf', 'mc')),
  statement     text not null check (char_length(btrim(statement)) between 1 and 500),
  answer        boolean,        -- só Verdadeiro/Falso
  options       jsonb,          -- só escolha múltipla: lista de textos (2 a 6)
  correct_index int,            -- só escolha múltipla: posição da opção certa (0 = A)
  created_at    timestamptz not null default now(),
  constraint av_test_questions_shape check (
    (kind = 'vf' and answer is not null and options is null and correct_index is null)
    or
    (kind = 'mc' and answer is null
       and jsonb_typeof(options) = 'array'
       and jsonb_array_length(options) between 2 and 6
       and correct_index is not null and correct_index >= 0
       and correct_index < jsonb_array_length(options))
  )
);
create index if not exists av_test_questions_material_idx
  on public.av_test_questions (material_id, position);

-- 3) Tentativas (uma por colaborador e teste) ---------------------------------
create table if not exists public.av_test_attempts (
  id           uuid primary key default gen_random_uuid(),
  material_id  uuid not null references public.av_session_materials(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  staff_id     uuid not null references public.av_staff(id) on delete cascade,
  answers      jsonb not null,
  correct      int not null,
  total        int not null,
  score        numeric(5,2) not null,
  submitted_at timestamptz not null default now(),
  unique (material_id, staff_id)
);

-- 4) Segurança ---------------------------------------------------------------
create or replace function public.av_test_is_team()
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.av_profiles
                  where user_id = auth.uid() and role in ('admin', 'trainer'));
$$;
revoke all on function public.av_test_is_team() from public, anon;
grant execute on function public.av_test_is_team() to authenticated;

alter table public.av_test_questions enable row level security;
alter table public.av_test_attempts  enable row level security;

revoke all on public.av_test_questions, public.av_test_attempts from anon, authenticated;
grant select, insert, delete on public.av_test_questions to authenticated;
grant select, delete         on public.av_test_attempts  to authenticated;

-- Perguntas: só equipa formativa lê (o colaborador nunca vê as respostas certas pela tabela).
-- Não se alteram perguntas de um teste que já tem tentativas.
drop policy if exists av_test_questions_select on public.av_test_questions;
create policy av_test_questions_select on public.av_test_questions
  for select to authenticated using (public.av_test_is_team());

drop policy if exists av_test_questions_insert on public.av_test_questions;
create policy av_test_questions_insert on public.av_test_questions
  for insert to authenticated
  with check (public.av_test_is_team()
    and not exists (select 1 from public.av_test_attempts t
                     where t.material_id = av_test_questions.material_id));

drop policy if exists av_test_questions_delete on public.av_test_questions;
create policy av_test_questions_delete on public.av_test_questions
  for delete to authenticated
  using (public.av_test_is_team()
    and not exists (select 1 from public.av_test_attempts t
                     where t.material_id = av_test_questions.material_id));

-- Tentativas: o colaborador vê só as suas; a equipa vê todas e pode anular.
-- Ninguém escreve directamente: a submissão passa por av_submit_test.
drop policy if exists av_test_attempts_select on public.av_test_attempts;
create policy av_test_attempts_select on public.av_test_attempts
  for select to authenticated
  using (user_id = auth.uid() or public.av_test_is_team());

drop policy if exists av_test_attempts_delete on public.av_test_attempts;
create policy av_test_attempts_delete on public.av_test_attempts
  for delete to authenticated using (public.av_test_is_team());

-- 5) Funções -----------------------------------------------------------------
-- Ficha do colaborador autenticado; recusa quem não é colaborador activo.
create or replace function public.av_test_caller_staff()
returns uuid language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_role text; v_staff uuid;
begin
  if auth.uid() is null then raise exception 'Sessão inválida.'; end if;
  select role, staff_id into v_role, v_staff from public.av_profiles where user_id = auth.uid();
  if v_role is distinct from 'collaborator' or v_staff is null
     or not exists (select 1 from public.av_staff s
                     where s.id = v_staff and s.status is distinct from 'Inactivo') then
    raise exception 'Sem acesso a este teste.';
  end if;
  return v_staff;
end $$;
revoke all on function public.av_test_caller_staff() from public, anon, authenticated;

-- Devolve as perguntas (sem respostas certas) ou, se já submeteu, a nota.
-- A correcção detalhada só aparece depois da data de fecho.
create or replace function public.av_get_test(p_material uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_staff  uuid := public.av_test_caller_staff();
  m        public.av_session_materials%rowtype;
  a        public.av_test_attempts%rowtype;
  v_closed boolean;
begin
  select * into m from public.av_session_materials where id = p_material and kind = 'teste';
  if not found then raise exception 'Teste não encontrado.'; end if;
  v_closed := m.closes_at is not null and now() >= m.closes_at;

  select * into a from public.av_test_attempts
   where material_id = p_material and staff_id = v_staff;
  if found then
    return jsonb_build_object(
      'done', true, 'score', a.score, 'correct', a.correct, 'total', a.total,
      'review', case when v_closed then (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'statement', q.statement,
                 'kind', q.kind,
                 'options', q.options,
                 'answer', case when q.kind = 'mc' then to_jsonb(q.correct_index) else to_jsonb(q.answer) end,
                 'mine', a.answers -> (q.id::text)
               ) order by q.position), '[]'::jsonb)
          from public.av_test_questions q where q.material_id = p_material) end);
  end if;

  if m.opens_at is not null and now() < m.opens_at then
    raise exception 'Este teste ainda não está aberto.';
  end if;
  if v_closed then raise exception 'Este teste já está fechado.'; end if;

  return jsonb_build_object('done', false, 'questions', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', q.id, 'kind', q.kind, 'statement', q.statement, 'options', q.options
           ) order by q.position), '[]'::jsonb)
      from public.av_test_questions q where q.material_id = p_material));
end $$;

-- Corrige no servidor: nota = certas ÷ total × 20. Uma só tentativa por colaborador.
create or replace function public.av_submit_test(p_material uuid, p_answers jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_staff   uuid := public.av_test_caller_staff();
  m         public.av_session_materials%rowtype;
  q         record;
  v_a       jsonb;
  v_clean   jsonb := '{}'::jsonb;
  v_total   int := 0;
  v_correct int := 0;
  v_idx     int;
  v_score   numeric(5,2);
begin
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    raise exception 'Respostas inválidas.';
  end if;
  select * into m from public.av_session_materials where id = p_material and kind = 'teste';
  if not found then raise exception 'Teste não encontrado.'; end if;
  if m.opens_at is not null and now() < m.opens_at then
    raise exception 'Este teste ainda não está aberto.';
  end if;
  if m.closes_at is not null and now() >= m.closes_at then
    raise exception 'Este teste já está fechado.';
  end if;
  if exists (select 1 from public.av_test_attempts
              where material_id = p_material and staff_id = v_staff) then
    raise exception 'Já submeteu este teste.';
  end if;

  for q in select * from public.av_test_questions
            where material_id = p_material order by position
  loop
    v_total := v_total + 1;
    v_a := p_answers -> (q.id::text);
    if q.kind = 'mc' then
      if v_a is null or jsonb_typeof(v_a) <> 'number' or (v_a #>> '{}') !~ '^[0-9]{1,2}$' then
        raise exception 'Responda a todas as perguntas.';
      end if;
      v_idx := (v_a #>> '{}')::int;
      if v_idx >= jsonb_array_length(q.options) then raise exception 'Resposta inválida.'; end if;
      if v_idx = q.correct_index then v_correct := v_correct + 1; end if;
    else
      if v_a is null or jsonb_typeof(v_a) <> 'boolean' then
        raise exception 'Responda a todas as perguntas.';
      end if;
      if (v_a #>> '{}')::boolean = q.answer then v_correct := v_correct + 1; end if;
    end if;
    v_clean := v_clean || jsonb_build_object(q.id::text, v_a);
  end loop;

  if v_total = 0 then raise exception 'Este teste ainda não tem perguntas.'; end if;
  v_score := round(v_correct::numeric / v_total * 20, 2);

  begin
    insert into public.av_test_attempts (material_id, user_id, staff_id, answers, correct, total, score)
    values (p_material, auth.uid(), v_staff, v_clean, v_correct, v_total, v_score);
  exception when unique_violation then
    raise exception 'Já submeteu este teste.';
  end;

  return jsonb_build_object('score', v_score, 'correct', v_correct, 'total', v_total);
end $$;

revoke all on function public.av_get_test(uuid)           from public, anon;
revoke all on function public.av_submit_test(uuid, jsonb) from public, anon;
grant execute on function public.av_get_test(uuid)           to authenticated;
grant execute on function public.av_submit_test(uuid, jsonb) to authenticated;

commit;
