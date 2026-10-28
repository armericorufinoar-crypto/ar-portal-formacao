-- AR Portal de Formação — migração 003: leitura apenas para participantes activos
-- Executar no SQL Editor depois da 001 e da 002. Pode ser executada mais do que uma vez.
-- Participante activo = equipa formativa (admin/trainer) ou colaborador Activo com ficha ligada
-- (função public.av_is_active_participant(), criada na 002).

-- 1. Sessões e materiais: deixam de ser legíveis por qualquer utilizador autenticado.
drop policy if exists av_sessions_read_authenticated on public.av_sessions;
drop policy if exists av_sessions_read_active on public.av_sessions;
create policy av_sessions_read_active on public.av_sessions for select to authenticated
using ((select public.av_is_active_participant()));

-- 2. Fórum: leitura só para participantes activos.
drop policy if exists av_forum_read_authenticated on public.av_forum_posts;
drop policy if exists av_forum_read_active on public.av_forum_posts;
create policy av_forum_read_active on public.av_forum_posts for select to authenticated
using ((select public.av_is_active_participant()));

drop policy if exists av_forum_replies_read_authenticated on public.av_forum_replies;
drop policy if exists av_forum_replies_read_active on public.av_forum_replies;
create policy av_forum_replies_read_active on public.av_forum_replies for select to authenticated
using ((select public.av_is_active_participant()));

-- 3. Um colaborador inactivo também deixa de editar ou apagar as suas publicações.
--    A equipa formativa continua a moderar.
drop policy if exists av_forum_update_self_or_training on public.av_forum_posts;
create policy av_forum_update_self_or_training on public.av_forum_posts for update to authenticated
using (public.av_can_manage_training() or (author_user_id = (select auth.uid()) and (select public.av_is_active_participant())))
with check (public.av_can_manage_training() or (author_user_id = (select auth.uid()) and (select public.av_is_active_participant())));

drop policy if exists av_forum_delete_self_or_training on public.av_forum_posts;
create policy av_forum_delete_self_or_training on public.av_forum_posts for delete to authenticated
using (public.av_can_manage_training() or (author_user_id = (select auth.uid()) and (select public.av_is_active_participant())));

drop policy if exists av_forum_replies_delete_self_or_training on public.av_forum_replies;
create policy av_forum_replies_delete_self_or_training on public.av_forum_replies for delete to authenticated
using (public.av_can_manage_training() or (author_user_id = (select auth.uid()) and (select public.av_is_active_participant())));

-- Verificação (opcional): deve listar as políticas *_read_active e nenhuma *_read_authenticated
-- select tablename, policyname, cmd from pg_policies
-- where schemaname = 'public' and tablename in ('av_sessions','av_forum_posts','av_forum_replies')
-- order by tablename, cmd, policyname;
