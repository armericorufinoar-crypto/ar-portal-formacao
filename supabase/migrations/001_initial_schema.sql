-- AR Portal de Formação — esquema inicial Supabase
-- Executar num projecto Supabase NOVO dedicado ao portal. Rever antes de aplicar a um projecto existente.
-- Não colocar a chave service_role no navegador.

create extension if not exists pgcrypto;

create type public.av_role as enum ('admin', 'trainer', 'collaborator');
create type public.av_staff_status as enum ('Activo', 'Inactivo');
create type public.av_attendance_status as enum ('Presente', 'Falta', 'Justificada');

create table public.av_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role public.av_role not null default 'collaborator',
  staff_id uuid unique,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.av_staff (
  id uuid primary key default gen_random_uuid(),
  staff_number text not null unique,
  full_name text not null,
  department text not null,
  job_title text not null,
  email text,
  phone text,
  -- Evitar guardar BI nesta tabela até existir finalidade e política de retenção aprovadas.
  status public.av_staff_status not null default 'Activo',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.av_profiles
  add constraint av_profiles_staff_fk foreign key (staff_id) references public.av_staff(id) on delete set null;

create table public.av_sessions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  area text not null check (area in ('Finanças e Investimentos','Marketing e Vendas','Negócios','Oratória','Liderança')),
  session_date date not null,
  start_time time,
  trainer_name text not null,
  location text,
  description text,
  material_title text,
  material_url text,
  exercise_description text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.av_attendance (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.av_sessions(id) on delete cascade,
  staff_id uuid not null references public.av_staff(id) on delete cascade,
  status public.av_attendance_status not null,
  marked_by uuid references auth.users(id) on delete set null,
  marked_at timestamptz not null default now(),
  unique (session_id, staff_id)
);

create table public.av_assessments (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.av_sessions(id) on delete cascade,
  staff_id uuid not null references public.av_staff(id) on delete cascade,
  exercise_title text not null,
  assessed_on date not null default current_date,
  score numeric(5,2) not null check (score >= 0 and score <= 100),
  criteria text,
  trainer_feedback text,
  assessed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.av_forum_posts (
  id uuid primary key default gen_random_uuid(),
  author_user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid references public.av_sessions(id) on delete set null,
  area text check (area is null or area in ('Finanças e Investimentos','Marketing e Vendas','Negócios','Oratória','Liderança')),
  post_type text not null default 'Dúvida' check (post_type in ('Dúvida','Pergunta','Opinião','Partilha')),
  body text not null check (length(trim(body)) between 1 and 5000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.av_forum_replies (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.av_forum_posts(id) on delete cascade,
  author_user_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (length(trim(body)) between 1 and 3000),
  created_at timestamptz not null default now()
);

create table public.av_session_feedback (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.av_staff(id) on delete cascade,
  session_id uuid not null references public.av_sessions(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  comment text check (comment is null or length(comment) <= 3000),
  created_at timestamptz not null default now(),
  unique (staff_id, session_id)
);

create table public.av_private_messages (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.av_staff(id) on delete cascade,
  sender_user_id uuid not null references auth.users(id) on delete cascade,
  subject text,
  body text not null check (length(trim(body)) between 1 and 5000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.av_private_replies (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.av_private_messages(id) on delete cascade,
  author_user_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (length(trim(body)) between 1 and 5000),
  created_at timestamptz not null default now()
);

create index av_sessions_date_idx on public.av_sessions(session_date);
create index av_sessions_area_date_idx on public.av_sessions(area, session_date);
create index av_attendance_staff_idx on public.av_attendance(staff_id);
create index av_assessments_staff_idx on public.av_assessments(staff_id);
create index av_forum_posts_created_idx on public.av_forum_posts(created_at desc);
create index av_private_messages_staff_idx on public.av_private_messages(staff_id, created_at desc);

-- Funções de autorização SECURITY DEFINER evitam políticas RLS recursivas.
create or replace function public.av_current_role()
returns public.av_role
language sql stable security definer
set search_path = ''
as $$
  select p.role from public.av_profiles p where p.user_id = auth.uid()
$$;

create or replace function public.av_is_staff_member(target_staff_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.av_profiles p
    where p.user_id = auth.uid() and p.staff_id = target_staff_id
  )
$$;

create or replace function public.av_can_manage_training()
returns boolean
language sql stable security definer
set search_path = ''
as $$ select coalesce(public.av_current_role() in ('admin'::public.av_role, 'trainer'::public.av_role), false) $$;

-- A inscrição pública não pode escolher o próprio papel. O perfil nasce sempre como colaborador.
create or replace function public.av_handle_new_user()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.av_profiles (user_id, role, display_name)
  values (new.id, 'collaborator'::public.av_role, nullif(new.raw_user_meta_data ->> 'display_name', ''))
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger av_auth_user_created
after insert on auth.users
for each row execute procedure public.av_handle_new_user();

create or replace function public.av_touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end; $$;

create trigger av_staff_touch before update on public.av_staff for each row execute procedure public.av_touch_updated_at();
create trigger av_sessions_touch before update on public.av_sessions for each row execute procedure public.av_touch_updated_at();
create trigger av_assessments_touch before update on public.av_assessments for each row execute procedure public.av_touch_updated_at();
create trigger av_forum_posts_touch before update on public.av_forum_posts for each row execute procedure public.av_touch_updated_at();
create trigger av_private_messages_touch before update on public.av_private_messages for each row execute procedure public.av_touch_updated_at();

-- Activar RLS em todas as tabelas acessíveis pela API.
alter table public.av_profiles enable row level security;
alter table public.av_staff enable row level security;
alter table public.av_sessions enable row level security;
alter table public.av_attendance enable row level security;
alter table public.av_assessments enable row level security;
alter table public.av_forum_posts enable row level security;
alter table public.av_forum_replies enable row level security;
alter table public.av_session_feedback enable row level security;
alter table public.av_private_messages enable row level security;
alter table public.av_private_replies enable row level security;

-- Perfis: cada utilizador vê o próprio; administradores gerem todos. Papel não pode ser alterado pelo próprio cliente.
create policy av_profiles_read_self_or_admin on public.av_profiles for select to authenticated
using (user_id = auth.uid() or public.av_current_role() = 'admin'::public.av_role);
create policy av_profiles_admin_insert on public.av_profiles for insert to authenticated
with check (public.av_current_role() = 'admin'::public.av_role);
create policy av_profiles_admin_update on public.av_profiles for update to authenticated
using (public.av_current_role() = 'admin'::public.av_role)
with check (public.av_current_role() = 'admin'::public.av_role);

-- Colaboradores: administração/formadores podem consultar; só administração pode alterar o cadastro.
create policy av_staff_read_authenticated on public.av_staff for select to authenticated
using (public.av_can_manage_training() or public.av_is_staff_member(id));
create policy av_staff_admin_insert on public.av_staff for insert to authenticated
with check (public.av_current_role() = 'admin'::public.av_role);
create policy av_staff_admin_update on public.av_staff for update to authenticated
using (public.av_current_role() = 'admin'::public.av_role)
with check (public.av_current_role() = 'admin'::public.av_role);
create policy av_staff_admin_delete on public.av_staff for delete to authenticated
using (public.av_current_role() = 'admin'::public.av_role);

-- Sessões e materiais: utilizadores autenticados consultam; administração/formadores gerem.
create policy av_sessions_read_authenticated on public.av_sessions for select to authenticated using (true);
create policy av_sessions_manage_training on public.av_sessions for all to authenticated
using (public.av_can_manage_training()) with check (public.av_can_manage_training());

-- Presenças: administração/formadores gerem; colaborador consulta apenas as suas.
create policy av_attendance_read_own_or_training on public.av_attendance for select to authenticated
using (public.av_can_manage_training() or public.av_is_staff_member(staff_id));
create policy av_attendance_manage_training on public.av_attendance for all to authenticated
using (public.av_can_manage_training()) with check (public.av_can_manage_training());

-- Avaliações: colaborador consulta as suas; administração/formadores gerem.
create policy av_assessments_read_own_or_training on public.av_assessments for select to authenticated
using (public.av_can_manage_training() or public.av_is_staff_member(staff_id));
create policy av_assessments_manage_training on public.av_assessments for all to authenticated
using (public.av_can_manage_training()) with check (public.av_can_manage_training());

-- Fórum: participantes autenticados consultam; cada um cria publicações próprias; equipa formativa modera.
create policy av_forum_read_authenticated on public.av_forum_posts for select to authenticated using (true);
create policy av_forum_insert_self on public.av_forum_posts for insert to authenticated
with check (author_user_id = auth.uid());
create policy av_forum_update_self_or_training on public.av_forum_posts for update to authenticated
using (author_user_id = auth.uid() or public.av_can_manage_training())
with check (author_user_id = auth.uid() or public.av_can_manage_training());
create policy av_forum_delete_self_or_training on public.av_forum_posts for delete to authenticated
using (author_user_id = auth.uid() or public.av_can_manage_training());
create policy av_forum_replies_read_authenticated on public.av_forum_replies for select to authenticated using (true);
create policy av_forum_replies_insert_authorized on public.av_forum_replies for insert to authenticated
with check (author_user_id = auth.uid() and (public.av_can_manage_training() or exists (select 1 from public.av_forum_posts fp where fp.id = post_id and fp.author_user_id = auth.uid())));
create policy av_forum_replies_delete_self_or_training on public.av_forum_replies for delete to authenticated
using (author_user_id = auth.uid() or public.av_can_manage_training());

-- Feedback: o colaborador só cria/consulta o seu; equipa formativa consulta tudo.
create policy av_feedback_read_own_or_training on public.av_session_feedback for select to authenticated
using (public.av_can_manage_training() or public.av_is_staff_member(staff_id));
create policy av_feedback_insert_own on public.av_session_feedback for insert to authenticated
with check (public.av_is_staff_member(staff_id));
create policy av_feedback_update_own_or_training on public.av_session_feedback for update to authenticated
using (public.av_can_manage_training() or public.av_is_staff_member(staff_id))
with check (public.av_can_manage_training() or public.av_is_staff_member(staff_id));

-- Mensagens privadas: apenas o próprio colaborador e a equipa formativa acedem.
create policy av_private_messages_read_own_or_training on public.av_private_messages for select to authenticated
using (public.av_can_manage_training() or public.av_is_staff_member(staff_id));
create policy av_private_messages_insert_own on public.av_private_messages for insert to authenticated
with check (sender_user_id = auth.uid() and public.av_is_staff_member(staff_id));
create policy av_private_messages_update_training on public.av_private_messages for update to authenticated
using (public.av_can_manage_training()) with check (public.av_can_manage_training());
create policy av_private_messages_delete_training on public.av_private_messages for delete to authenticated
using (public.av_can_manage_training());
create policy av_private_replies_read_authorized on public.av_private_replies for select to authenticated
using (public.av_can_manage_training() or exists (select 1 from public.av_private_messages pm where pm.id = message_id and public.av_is_staff_member(pm.staff_id)));
create policy av_private_replies_insert_authorized on public.av_private_replies for insert to authenticated
with check (author_user_id = auth.uid() and (public.av_can_manage_training() or exists (select 1 from public.av_private_messages pm where pm.id = message_id and public.av_is_staff_member(pm.staff_id))));

-- O papel inicial de cada utilizador é sempre collaborator. Promover o primeiro administrador
-- manualmente pelo SQL Editor, depois de criar a sua conta:
-- update public.av_profiles set role = 'admin' where user_id = '<UUID_DO_UTILIZADOR>';
