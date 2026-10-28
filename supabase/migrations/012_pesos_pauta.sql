-- Ponderação configurável da pauta: testes automáticos e avaliações práticas.
-- Migração idempotente: mantém a linha existente e alinha os privilégios/políticas
-- com a configuração verificada no projecto Supabase.

begin;

create table if not exists public.av_assessment_settings (
  id integer primary key check (id = 1),
  tests_weight integer not null default 60 check (tests_weight between 0 and 100),
  practical_weight integer not null default 40 check (practical_weight between 0 and 100),
  constraint av_assessment_settings_weights_sum check (tests_weight + practical_weight = 100),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.av_assessment_settings enable row level security;

-- Deixar explicitamente apenas os privilégios necessários para authenticated.
revoke all on table public.av_assessment_settings from public, anon, authenticated;
grant select, insert, update on table public.av_assessment_settings to authenticated;

-- Usar os nomes já encontrados na base de dados para evitar políticas duplicadas.
drop policy if exists av_assessment_settings_read on public.av_assessment_settings;
create policy av_assessment_settings_read
  on public.av_assessment_settings for select to authenticated
  using (true);

drop policy if exists av_assessment_settings_insert_admin on public.av_assessment_settings;
create policy av_assessment_settings_insert_admin
  on public.av_assessment_settings for insert to authenticated
  with check (public.av_current_role() = 'admin'::public.av_role);

drop policy if exists av_assessment_settings_update_admin on public.av_assessment_settings;
create policy av_assessment_settings_update_admin
  on public.av_assessment_settings for update to authenticated
  using (public.av_current_role() = 'admin'::public.av_role)
  with check (public.av_current_role() = 'admin'::public.av_role);

insert into public.av_assessment_settings (id, tests_weight, practical_weight)
values (1, 60, 40)
on conflict (id) do nothing;

commit;
