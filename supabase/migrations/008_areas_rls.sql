-- 008_areas_rls.sql
-- Aplica no servidor as áreas de acesso definidas na ficha do colaborador (av_staff.areas):
-- o colaborador activo só lê sessões, materiais e ficheiros das áreas marcadas.
-- Equipa formativa (admin/formador) mantém o acesso total, pelas políticas de gestão que já existem.
-- Requer a migração 007. Repetível sem erro. Corre numa só transacção.
--
-- Nota: até agora av_mat_select tinha using (true), isto é, qualquer utilizador autenticado
-- (incluindo colaboradores inactivos) conseguia listar todos os materiais e ligações.
-- Esta migração fecha isso.
begin;

-- Verdadeiro se o colaborador autenticado tem acesso à área da sessão indicada.
create or replace function public.av_has_session_access(p_session uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.av_sessions s
                  where s.id = p_session and public.av_has_area(s.area));
$$;
revoke all on function public.av_has_session_access(uuid) from public, anon;
grant execute on function public.av_has_session_access(uuid) to authenticated;

-- 1) Sessões: colaborador activo só vê as sessões das suas áreas.
drop policy if exists av_sessions_read_active on public.av_sessions;
create policy av_sessions_read_active on public.av_sessions
  for select to authenticated
  using ((select av_is_active_participant()) and public.av_has_area(area));

-- 2) Materiais (incluindo testes e ligações): equipa de gestão vê tudo; colaborador só os das suas áreas.
drop policy if exists av_mat_select on public.av_session_materials;
create policy av_mat_select on public.av_session_materials
  for select to authenticated
  using (public.av_can_manage_materials() or public.av_has_session_access(session_id));

-- 3) Ficheiros no armazenamento: mantém a janela de abertura/fecho que já existia e junta a área.
drop policy if exists av_mat_files_read on storage.objects;
create policy av_mat_files_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'av-materiais'
    and (
      public.av_can_manage_materials()
      or exists (
        select 1 from public.av_session_materials m
         where m.file_path = objects.name
           and public.av_has_session_access(m.session_id)
           and (
             m.kind <> all (array['actividade'::text, 'teste'::text])
             or ((m.opens_at is null or m.opens_at <= now())
                 and (m.closes_at is null or m.closes_at >= now()))
           )
      )
    )
  );

commit;

-- ---------------------------------------------------------------------------
-- COMO REVERTER (se for preciso voltar ao comportamento anterior, correr à parte):
--
-- begin;
-- drop policy if exists av_sessions_read_active on public.av_sessions;
-- create policy av_sessions_read_active on public.av_sessions
--   for select to authenticated using ((select av_is_active_participant()));
-- drop policy if exists av_mat_select on public.av_session_materials;
-- create policy av_mat_select on public.av_session_materials
--   for select to authenticated using (true);
-- drop policy if exists av_mat_files_read on storage.objects;
-- create policy av_mat_files_read on storage.objects
--   for select to authenticated
--   using (bucket_id = 'av-materiais' and (public.av_can_manage_materials() or exists (
--     select 1 from public.av_session_materials m
--      where m.file_path = objects.name
--        and (m.kind <> all (array['actividade'::text, 'teste'::text])
--             or ((m.opens_at is null or m.opens_at <= now())
--                 and (m.closes_at is null or m.closes_at >= now()))))));
-- commit;
