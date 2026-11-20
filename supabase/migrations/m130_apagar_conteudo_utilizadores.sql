-- =====================================================================
-- Portal de Formação AR · migração 005
-- Funções (RPC) usadas pelos botões «Eliminar» do index.html v13:
--   av_delete_post(text)        · apagar publicação (admin ou o próprio autor)
--   av_delete_comment(text)     · apagar comentário (admin ou o próprio autor)
--   av_delete_feedback(text)    · apagar feedback   (só admin)
--   av_admin_delete_user(uuid)  · eliminar conta    (só admin)
-- Executar uma vez no SQL Editor do Supabase. É seguro repetir.
-- Os ids são comparados como texto para funcionar seja qual for o tipo
-- (uuid / bigint) das colunas.
-- =====================================================================

create or replace function public.av_is_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.av_profiles
    where user_id = auth.uid() and role = 'admin'
  );
$$;

-- ---------- publicação (apaga também comentários e reacções) ----------
create or replace function public.av_delete_post(p_id text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare v_author uuid;
begin
  select author_user_id into v_author from public.av_forum_posts where id::text = p_id;
  if not found then raise exception 'Publicação não encontrada.'; end if;
  if not (public.av_is_admin() or v_author = auth.uid()) then
    raise exception 'Sem permissão para eliminar esta publicação.';
  end if;
  delete from public.av_forum_reactions where post_id::text = p_id;
  delete from public.av_forum_replies   where post_id::text = p_id;
  delete from public.av_forum_posts     where id::text = p_id;
end;
$$;

-- ---------- comentário ----------
create or replace function public.av_delete_comment(p_id text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare v_author uuid;
begin
  select author_user_id into v_author from public.av_forum_replies where id::text = p_id;
  if not found then raise exception 'Comentário não encontrado.'; end if;
  if not (public.av_is_admin() or v_author = auth.uid()) then
    raise exception 'Sem permissão para eliminar este comentário.';
  end if;
  delete from public.av_forum_replies where id::text = p_id;
end;
$$;

-- ---------- feedback de sessão (só administração) ----------
create or replace function public.av_delete_feedback(p_id text)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.av_is_admin() then
    raise exception 'Apenas a administração pode eliminar feedback.';
  end if;
  delete from public.av_session_feedback where id::text = p_id;
  if not found then raise exception 'Feedback não encontrado.'; end if;
end;
$$;

-- ---------- eliminar conta ----------
-- Apaga: login, perfil, publicações/comentários/reacções e mensagens privadas
-- desta conta. Mantém: ficha do colaborador, presenças e avaliações.
create or replace function public.av_admin_delete_user(p_user uuid)
returns void
language plpgsql security definer
set search_path = public, auth
as $$
begin
  if not public.av_is_admin() then
    raise exception 'Apenas a administração pode eliminar contas.';
  end if;
  if p_user = auth.uid() then
    raise exception 'Não pode eliminar a sua própria conta.';
  end if;
  if exists (select 1 from public.av_profiles where user_id = p_user and role = 'admin') then
    raise exception 'Não é possível eliminar uma conta de administrador.';
  end if;
  if not exists (select 1 from auth.users where id = p_user) then
    raise exception 'Conta não encontrada.';
  end if;

  -- conteúdo do chat público
  delete from public.av_forum_reactions where user_id = p_user
     or post_id in (select id from public.av_forum_posts where author_user_id = p_user);
  delete from public.av_forum_replies where author_user_id = p_user
     or post_id in (select id from public.av_forum_posts where author_user_id = p_user);
  delete from public.av_forum_posts where author_user_id = p_user;

  -- mensagens privadas
  delete from public.av_private_replies where author_user_id = p_user
     or message_id in (select id from public.av_private_messages where sender_user_id = p_user);
  delete from public.av_private_messages where sender_user_id = p_user;

  delete from public.av_user_seen where user_id = p_user;

  -- referências «quem fez» em registos que se mantêm: passam a nulo
  begin update public.av_attendance        set marked_by   = null where marked_by   = p_user; exception when others then null; end;
  begin update public.av_assessments       set assessed_by = null where assessed_by = p_user; exception when others then null; end;
  begin update public.av_session_materials set created_by  = null where created_by  = p_user; exception when others then null; end;

  -- testes submetidos: a nota fica ligada à ficha; só se perde a ligação à conta
  begin
    update public.av_test_attempts set user_id = null where user_id = p_user;
  exception when others then
    raise exception 'Esta conta tem testes submetidos e não é possível desligá-los. Anule as tentativas em «Materiais → Resultados» e tente de novo.';
  end;

  delete from public.av_profiles where user_id = p_user;
  delete from auth.users where id = p_user;
end;
$$;

-- só utilizadores autenticados podem chamar; a verificação de admin é feita dentro
revoke all on function public.av_delete_post(text)       from public, anon;
revoke all on function public.av_delete_comment(text)    from public, anon;
revoke all on function public.av_delete_feedback(text)   from public, anon;
revoke all on function public.av_admin_delete_user(uuid) from public, anon;
grant execute on function public.av_delete_post(text)       to authenticated;
grant execute on function public.av_delete_comment(text)    to authenticated;
grant execute on function public.av_delete_feedback(text)   to authenticated;
grant execute on function public.av_admin_delete_user(uuid) to authenticated;
