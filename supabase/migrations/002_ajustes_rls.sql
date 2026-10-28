-- AR Portal de Formação — migração 002: ajustes de RLS
-- Executar no SQL Editor depois da 001. Pode ser executada mais do que uma vez.

-- 1. Colaborador inactivo perde o acesso aos seus registos.
create or replace function public.av_is_staff_member(target_staff_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.av_profiles p
    join public.av_staff s on s.id = p.staff_id
    where p.user_id = auth.uid() and p.staff_id = target_staff_id
      and s.status = 'Activo'::public.av_staff_status)
$$;

-- Participante activo = equipa formativa ou colaborador activo com ficha ligada.
create or replace function public.av_is_active_participant()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.av_can_manage_training() or exists (
    select 1 from public.av_profiles p
    join public.av_staff s on s.id = p.staff_id
    where p.user_id = auth.uid() and s.status = 'Activo'::public.av_staff_status)
$$;

-- 2. Nome do autor visível no fórum (preenchido no servidor, não pelo cliente).
alter table public.av_forum_posts add column if not exists author_name text;
alter table public.av_forum_replies add column if not exists author_name text;

create or replace function public.av_set_author_name()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.author_name := coalesce(
    (select s.full_name from public.av_profiles p join public.av_staff s on s.id = p.staff_id where p.user_id = new.author_user_id),
    (select p.display_name from public.av_profiles p where p.user_id = new.author_user_id),
    'Equipa AR');
  return new;
end $$;

drop trigger if exists av_forum_posts_author on public.av_forum_posts;
create trigger av_forum_posts_author before insert or update on public.av_forum_posts
for each row execute procedure public.av_set_author_name();
drop trigger if exists av_forum_replies_author on public.av_forum_replies;
create trigger av_forum_replies_author before insert or update on public.av_forum_replies
for each row execute procedure public.av_set_author_name();

-- 3. Colaboradores activos podem publicar e responder uns aos outros no fórum.
drop policy if exists av_forum_insert_self on public.av_forum_posts;
create policy av_forum_insert_self on public.av_forum_posts for insert to authenticated
with check (author_user_id = auth.uid() and public.av_is_active_participant());

drop policy if exists av_forum_replies_insert_authorized on public.av_forum_replies;
drop policy if exists av_forum_replies_insert_participant on public.av_forum_replies;
create policy av_forum_replies_insert_participant on public.av_forum_replies for insert to authenticated
with check (author_user_id = auth.uid() and public.av_is_active_participant());

-- 4. A equipa formativa também pode iniciar uma mensagem privada a um colaborador.
drop policy if exists av_private_messages_insert_own on public.av_private_messages;
drop policy if exists av_private_messages_insert on public.av_private_messages;
create policy av_private_messages_insert on public.av_private_messages for insert to authenticated
with check (sender_user_id = auth.uid() and (public.av_can_manage_training() or public.av_is_staff_member(staff_id)));

-- 5. Funções de autorização deixam de ser chamáveis sem sessão.
revoke execute on function public.av_current_role(), public.av_is_staff_member(uuid),
  public.av_can_manage_training(), public.av_is_active_participant() from public, anon;
grant execute on function public.av_current_role(), public.av_is_staff_member(uuid),
  public.av_can_manage_training(), public.av_is_active_participant() to authenticated;
