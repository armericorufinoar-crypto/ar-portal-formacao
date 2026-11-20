-- =====================================================================
-- AR Formação · migração v11
-- Executar UMA vez no Supabase: SQL Editor > New query > colar > Run
-- (é seguro repetir: usa "if not exists" / "drop policy if exists")
-- =====================================================================

-- 0) Função auxiliar: quem pode gerir materiais (admin e formador)
create or replace function public.av_can_manage_materials()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.av_profiles p
    where p.user_id = auth.uid() and p.role in ('admin','trainer')
  );
$$;
grant execute on function public.av_can_manage_materials() to authenticated;

-- 1) Estado de leitura (mensagens privadas e notificações) por utilizador
create table if not exists public.av_user_seen (
  user_id       uuid primary key references auth.users(id) on delete cascade,
  thread_seen   jsonb not null default '{}'::jsonb,
  notif_seen_at timestamptz,
  updated_at    timestamptz not null default now()
);
alter table public.av_user_seen enable row level security;
drop policy if exists av_user_seen_own on public.av_user_seen;
create policy av_user_seen_own on public.av_user_seen
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- 2) Materiais por sessão (ficheiros carregados, ligações, actividades, testes)
create table if not exists public.av_session_materials (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid not null references public.av_sessions(id) on delete cascade,
  kind        text not null default 'ficheiro'
              check (kind in ('ficheiro','ligacao','actividade','teste')),
  title       text not null check (char_length(title) between 1 and 160),
  file_path   text,
  file_name   text,
  url         text,
  opens_at    timestamptz,
  closes_at   timestamptz,
  created_by  uuid references auth.users(id) default auth.uid(),
  created_at  timestamptz not null default now()
);
create index if not exists av_session_materials_session_idx
  on public.av_session_materials(session_id);
alter table public.av_session_materials enable row level security;

drop policy if exists av_mat_select on public.av_session_materials;
create policy av_mat_select on public.av_session_materials
  for select to authenticated using (true);

drop policy if exists av_mat_insert on public.av_session_materials;
create policy av_mat_insert on public.av_session_materials
  for insert to authenticated with check (public.av_can_manage_materials());

drop policy if exists av_mat_update on public.av_session_materials;
create policy av_mat_update on public.av_session_materials
  for update to authenticated
  using (public.av_can_manage_materials())
  with check (public.av_can_manage_materials());

drop policy if exists av_mat_delete on public.av_session_materials;
create policy av_mat_delete on public.av_session_materials
  for delete to authenticated using (public.av_can_manage_materials());

-- 3) Armazenamento privado para os ficheiros (25 MB por ficheiro)
insert into storage.buckets (id, name, public, file_size_limit)
values ('av-materiais', 'av-materiais', false, 26214400)
on conflict (id) do update set public = false, file_size_limit = 26214400;

drop policy if exists av_mat_files_read on storage.objects;
create policy av_mat_files_read on storage.objects
  for select to authenticated using (bucket_id = 'av-materiais');

drop policy if exists av_mat_files_insert on storage.objects;
create policy av_mat_files_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'av-materiais' and public.av_can_manage_materials());

drop policy if exists av_mat_files_delete on storage.objects;
create policy av_mat_files_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'av-materiais' and public.av_can_manage_materials());

-- 4) OPCIONAL (executar só uma vez, e só se as notas antigas estiverem em 0-100):
--    converte as avaliações já registadas para a escala 0-20.
-- update public.av_assessments set score = round(score / 5.0, 2);
