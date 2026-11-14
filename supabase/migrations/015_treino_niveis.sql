-- =====================================================================
-- 015_treino_niveis.sql  ·  Modo Treino, níveis, turmas, missões
-- Base: Especificação AR Formação (Modo Treino) APROVADA 13/11/2026
-- ESTADO: RASCUNHO PARA REVISÃO. Não executar sem autorização expressa.
-- Não altera: av_test_*, pauta, diagnóstico de competências, pagamentos.
-- =====================================================================
begin;

-- 0. Salvaguarda de tipos: o script assume staff_id/ids em uuid.
do $$
declare t1 text; t2 text;
begin
  select data_type into t1 from information_schema.columns
   where table_schema='public' and table_name='av_staff' and column_name='id';
  select data_type into t2 from information_schema.columns
   where table_schema='public' and table_name='av_profiles' and column_name='staff_id';
  if t1 is distinct from 'uuid' or t2 is distinct from 'uuid' then
    raise exception 'av_staff.id (%) e av_profiles.staff_id (%) não são uuid: ajustar os tipos de staff_id nesta migração antes de a executar.', t1, t2;
  end if;
end $$;

-- 1. Auxiliares de papel (nomes próprios para não colidir com os existentes)
create or replace function public.av_train_role() returns text
language sql stable security definer set search_path = public as
$$ select role from public.av_profiles where user_id = auth.uid() $$;

create or replace function public.av_train_staff_id() returns uuid
language sql stable security definer set search_path = public as
$$ select staff_id from public.av_profiles where user_id = auth.uid() $$;

create or replace function public.av_train_is_staff() returns boolean
language sql stable security definer set search_path = public as
$$ select coalesce(public.av_train_role() in ('admin','trainer'), false) $$;

-- 2. Parâmetros editáveis (linha única). Só a administração altera.
create table public.av_train_settings (
  id             int primary key default 1 check (id = 1),
  ladder         jsonb   not null default '[1,3,7]',
  exit_streak    int     not null default 2 check (exit_streak in (2,3)),
  active_min_days int    not null default 3,
  session_sizes  jsonb   not null default '{
    "estudante":         {"min":3,"questions":5,"old_errors":3},
    "empreendedor":      {"min":3,"questions":5,"old_errors":3},
    "empreendedor_plus": {"min":4,"questions":6,"old_errors":3},
    "empresario":        {"min":5,"questions":7,"old_errors":3}}',
  rest_rule      jsonb   not null default '{"missed_days_per_7":1}',
  cohort_min_size int    not null default 5,
  current_cycle  int     not null default 1,
  updated_at     timestamptz not null default now()
);
insert into public.av_train_settings (id) values (1);

-- 3. Turmas
create table public.av_cohorts (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  levels          text[] not null default '{}',
  trainer_user_id uuid references auth.users(id) on delete set null,
  current_theme   text,
  active          boolean not null default true,
  created_at      timestamptz not null default now()
);

alter table public.av_staff
  add column if not exists cohort_id uuid references public.av_cohorts(id) on delete set null;

create table public.av_cohort_aulas (
  id         uuid primary key default gen_random_uuid(),
  cohort_id  uuid not null references public.av_cohorts(id) on delete cascade,
  lesson_no  int  not null check (lesson_no between 1 and 4),
  lesson_date date,
  theme      text,
  unique (cohort_id, lesson_no)
);

-- 4. Perfil de entrada e histórico de níveis
create table public.av_student_profile (
  staff_id      uuid primary key references public.av_staff(id) on delete cascade,
  answers       jsonb not null,
  level_auto    text  not null check (level_auto  in ('estudante','empreendedor','empreendedor_plus','empresario')),
  level_final   text  not null check (level_final in ('estudante','empreendedor','empreendedor_plus','empresario')),
  lead_flag     boolean not null default false,
  reassess_open boolean not null default false,
  updated_at    timestamptz not null default now()
);

create table public.av_level_history (
  id         uuid primary key default gen_random_uuid(),
  staff_id   uuid not null references public.av_staff(id) on delete cascade,
  level      text not null check (level in ('estudante','empreendedor','empreendedor_plus','empresario')),
  source     text not null check (source in ('auto','formador')),
  reason     text,
  cycle      int  not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);
create index on public.av_level_history (staff_id, created_at desc);

-- 5. Banco de treino (cinco tipos de item; campos próprios por tipo)
create table public.av_train_questions (
  id                 uuid primary key default gen_random_uuid(),
  area               text,
  theme              text,
  levels             text[] not null default '{}',
  kind               text not null check (kind in ('vf','mc','num','order','case')),
  statement          text not null,
  case_context       text,                 -- case
  options            jsonb,                -- mc, order (passos), case
  correct_index      int,                  -- mc, case
  answer_bool        boolean,              -- vf
  expected_value     numeric,              -- num
  tolerance          numeric default 0,    -- num (± absoluto)
  correct_order      int[],                -- order (índices de options pela ordem certa)
  scoring_key        jsonb,                -- case com pontuação parcial (opcional)
  explanation        text,
  competency_id      uuid,                 -- sem FK: tipo de av_competencies a confirmar
  source_question_id uuid,                 -- cópia de av_test_questions; sem FK
  active             boolean not null default true,
  created_at         timestamptz not null default now(),
  check (kind <> 'vf'    or answer_bool is not null),
  check (kind <> 'mc'    or (options is not null and correct_index is not null)),
  check (kind <> 'num'   or expected_value is not null),
  check (kind <> 'order' or (options is not null and correct_order is not null)),
  check (kind <> 'case'  or (options is not null and (correct_index is not null or scoring_key is not null)))
);

-- 6. Progresso, dias, contactos, lembretes, missões
create table public.av_train_progress (
  staff_id    uuid not null references public.av_staff(id) on delete cascade,
  question_id uuid not null references public.av_train_questions(id) on delete cascade,
  streak      int  not null default 0,
  next_due    date,
  last_result boolean,
  last_at     timestamptz,
  primary key (staff_id, question_id)
);

create table public.av_train_days (
  staff_id  uuid not null references public.av_staff(id) on delete cascade,
  day       date not null,
  answered  int  not null default 0,
  correct   int  not null default 0,
  completed boolean not null default false,
  primary key (staff_id, day)
);

create table public.av_contact_prefs (
  staff_id           uuid primary key references public.av_staff(id) on delete cascade,
  whatsapp_e164      text check (whatsapp_e164 ~ '^\+244[0-9]{9}$'),
  whatsapp_optin_at  timestamptz,
  email_optin_at     timestamptz,
  reminder_hour      time,
  paused_until       date
);

create table public.av_reminder_log (
  id         uuid primary key default gen_random_uuid(),
  staff_id   uuid not null references public.av_staff(id) on delete cascade,
  day        date not null,
  channel    text not null check (channel in ('whatsapp','email')),
  status     text not null,
  error      text,
  created_at timestamptz not null default now()
);

create table public.av_train_missions (
  id           uuid primary key default gen_random_uuid(),
  staff_id     uuid not null references public.av_staff(id) on delete cascade,
  level        text not null check (level in ('estudante','empreendedor','empreendedor_plus','empresario')),
  lesson_no    int  not null check (lesson_no between 1 and 4),
  mission_id   text not null,
  status       text not null default 'pendente' check (status in ('pendente','feita','verificada')),
  done_at      timestamptz,
  checked_at   timestamptz,
  checked_by   uuid references auth.users(id) on delete set null,
  trainer_note text,
  unique (staff_id, level, lesson_no)
);

-- 7. RLS. O formando só lê os seus dados; escritas sensíveis só por função.
alter table public.av_train_settings  enable row level security;
alter table public.av_cohorts         enable row level security;
alter table public.av_cohort_aulas    enable row level security;
alter table public.av_student_profile enable row level security;
alter table public.av_level_history   enable row level security;
alter table public.av_train_questions enable row level security;
alter table public.av_train_progress  enable row level security;
alter table public.av_train_days      enable row level security;
alter table public.av_contact_prefs   enable row level security;
alter table public.av_reminder_log    enable row level security;
alter table public.av_train_missions  enable row level security;

create policy ts_sel on public.av_train_settings for select using (public.av_train_is_staff());
create policy ts_upd on public.av_train_settings for update using (public.av_train_role() = 'admin') with check (public.av_train_role() = 'admin');

create policy co_sel on public.av_cohorts for select using (
  public.av_train_is_staff() or exists (select 1 from public.av_staff s where s.id = public.av_train_staff_id() and s.cohort_id = av_cohorts.id));
create policy co_all on public.av_cohorts for all using (public.av_train_is_staff()) with check (public.av_train_is_staff());

create policy ca_sel on public.av_cohort_aulas for select using (
  public.av_train_is_staff() or exists (select 1 from public.av_staff s where s.id = public.av_train_staff_id() and s.cohort_id = av_cohort_aulas.cohort_id));
create policy ca_all on public.av_cohort_aulas for all using (public.av_train_is_staff()) with check (public.av_train_is_staff());

create policy sp_sel on public.av_student_profile for select using (public.av_train_is_staff() or staff_id = public.av_train_staff_id());
create policy lh_sel on public.av_level_history   for select using (public.av_train_is_staff() or staff_id = public.av_train_staff_id());

-- Banco de treino: o formando NUNCA lê a tabela (recebe perguntas por função, sem a resposta).
create policy tq_all on public.av_train_questions for all using (public.av_train_is_staff()) with check (public.av_train_is_staff());

create policy tp_sel on public.av_train_progress for select using (public.av_train_is_staff() or staff_id = public.av_train_staff_id());
create policy td_sel on public.av_train_days     for select using (public.av_train_is_staff() or staff_id = public.av_train_staff_id());
create policy cp_sel on public.av_contact_prefs  for select using (public.av_train_is_staff() or staff_id = public.av_train_staff_id());
create policy rl_sel on public.av_reminder_log   for select using (public.av_train_is_staff());
create policy tm_sel on public.av_train_missions for select using (public.av_train_is_staff() or staff_id = public.av_train_staff_id());
create policy tm_stf on public.av_train_missions for all    using (public.av_train_is_staff()) with check (public.av_train_is_staff());
-- (marcar «feita» pelo formando entra numa função na fase 3; sem política de escrita directa.)

-- 8. Regra de nível (critérios revistos 13/11: a dimensão da equipa NÃO bloqueia)
create or replace function public.av_level_from_answers(a jsonb) returns text
language sql immutable as $$
  select case
    when a->>'q1' in ('nao','preparacao') then 'estudante'
    when a->>'q3' = 'sempre'
     and a->>'q4' = 'leads_vendas_despesas'
     and a->>'q6' = 'delego' then 'empresario'
    when a->>'q3' = 'sempre'
     and a->>'q4' in ('vendas_despesas','leads_vendas_despesas') then 'empreendedor_plus'
    else 'empreendedor'
  end
$$;

-- 9. Funções da fase 1
-- Códigos das respostas:
--  q1 nao|preparacao|sim · q2 lt1|1a3|gt3 (só se q1=sim) · q3 nunca|as_vezes|sempre
--  q4 nenhum|so_vendas|vendas_despesas|leads_vendas_despesas
--  q5 nenhuma|1a3|4mais (contexto) · q6 so_eu|com_ajuda|delego
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
  if (p_answers->>'q1') is null or (p_answers->>'q1') not in ('nao','preparacao','sim')
     or (p_answers->>'q3') not in ('nunca','as_vezes','sempre')
     or (p_answers->>'q4') not in ('nenhum','so_vendas','vendas_despesas','leads_vendas_despesas')
     or (p_answers->>'q5') not in ('nenhuma','1a3','4mais')
     or (p_answers->>'q6') not in ('so_eu','com_ajuda','delego') then
    raise exception 'respostas_invalidas';
  end if;
  if p_answers->>'q1' = 'sim' and (p_answers->>'q2') not in ('lt1','1a3','gt3') then
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

create or replace function public.av_set_level(p_staff uuid, p_level text, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare v_cycle int;
begin
  if not public.av_train_is_staff() then raise exception 'sem_permissao'; end if;
  if p_level not in ('estudante','empreendedor','empreendedor_plus','empresario') then raise exception 'nivel_invalido'; end if;
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'nota_obrigatoria'; end if;
  perform 1 from public.av_student_profile where staff_id = p_staff;
  if not found then raise exception 'sem_perfil'; end if;
  select current_cycle into v_cycle from public.av_train_settings where id = 1;
  update public.av_student_profile set level_final = p_level, updated_at = now() where staff_id = p_staff;
  insert into public.av_level_history (staff_id, level, source, reason, cycle, created_by)
  values (p_staff, p_level, 'formador', trim(p_reason), v_cycle, auth.uid());
end $$;

-- Abre a reavaliação (fim de ciclo) para uma turma, ou para todos se p_cohort for nulo.
create or replace function public.av_open_reassessment(p_cohort uuid default null) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.av_train_is_staff() then raise exception 'sem_permissao'; end if;
  update public.av_student_profile p set reassess_open = true
   where p.staff_id in (select s.id from public.av_staff s where p_cohort is null or s.cohort_id = p_cohort);
  get diagnostics n = row_count;
  return n;
end $$;

-- Atribui (ou retira, com p_cohort nulo) a turma de um formando. O formador só consulta
-- av_staff, por isso a escrita de cohort_id passa por esta função e não por UPDATE directo.
create or replace function public.av_assign_cohort(p_staff uuid, p_cohort uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.av_train_is_staff() then raise exception 'sem_permissao'; end if;
  if p_cohort is not null and not exists (select 1 from public.av_cohorts where id = p_cohort and active) then
    raise exception 'turma_invalida';
  end if;
  update public.av_staff set cohort_id = p_cohort where id = p_staff;
  if not found then raise exception 'formando_inexistente'; end if;
end $$;

revoke all on function public.av_save_profile(jsonb), public.av_set_level(uuid,text,text),
  public.av_open_reassessment(uuid), public.av_assign_cohort(uuid,uuid) from public, anon;
grant execute on function public.av_save_profile(jsonb), public.av_set_level(uuid,text,text),
  public.av_open_reassessment(uuid), public.av_assign_cohort(uuid,uuid) to authenticated;

-- As funções av_train_session/answer/state/av_cohort_week entram na migração da fase 2.
commit;
