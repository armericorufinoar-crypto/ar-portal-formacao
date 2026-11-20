-- AR Formação · Reacções (Gosto, Adoro, Coragem) nas publicações
-- Executar no Supabase: SQL Editor > New query > Run
-- Executar também o migracao_chat_anexos.sql, se ainda não o fez (anexos nas publicações e comentários).

create table if not exists public.av_forum_reactions (
  post_id    uuid not null references public.av_forum_posts(id) on delete cascade,
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind       text not null check (kind in ('gosto','adoro','coragem')),
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)   -- uma reacção por pessoa e publicação
);

create index if not exists av_forum_reactions_post_idx on public.av_forum_reactions (post_id);

alter table public.av_forum_reactions enable row level security;

-- Todos os utilizadores com sessão iniciada vêem as reacções (o feed é público para a formação)
drop policy if exists av_react_select on public.av_forum_reactions;
create policy av_react_select on public.av_forum_reactions
  for select to authenticated using (true);

-- Cada pessoa só cria, altera e retira a sua própria reacção
drop policy if exists av_react_insert on public.av_forum_reactions;
create policy av_react_insert on public.av_forum_reactions
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists av_react_update on public.av_forum_reactions;
create policy av_react_update on public.av_forum_reactions
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists av_react_delete on public.av_forum_reactions;
create policy av_react_delete on public.av_forum_reactions
  for delete to authenticated using (user_id = auth.uid());
