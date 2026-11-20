-- =====================================================================
-- 025_forum_anexos.sql
-- Colunas de anexos e edição no fórum (publicações e respostas).
--
-- PROBLEMA: o portal grava attachment_path e attachment_name (e, quando
-- existem, attachments e edited_at) em av_forum_posts e av_forum_replies.
-- Se a coluna não existe, o servidor recusa e o ecrã mostra
-- «Could not find the 'attachment_name' column ... in the schema cache».
--
-- Aditiva e repetível: só acrescenta colunas que faltam; não mexe em
-- políticas RLS nem em dados existentes.
--
-- ANTES DE EXECUTAR (opcional) — ver o que já existe:
--   select table_name, column_name, data_type
--   from information_schema.columns
--   where table_name in ('av_forum_posts','av_forum_replies')
--     and column_name in ('attachment_path','attachment_name','attachments','edited_at')
--   order by 1,2;
-- =====================================================================

alter table public.av_forum_posts
  add column if not exists attachment_path text,
  add column if not exists attachment_name text,
  add column if not exists attachments     jsonb not null default '[]'::jsonb,
  add column if not exists edited_at       timestamptz;

alter table public.av_forum_replies
  add column if not exists attachment_path text,
  add column if not exists attachment_name text,
  add column if not exists attachments     jsonb not null default '[]'::jsonb,
  add column if not exists edited_at       timestamptz;

-- Faz o PostgREST (API do Supabase) ver as colunas novas de imediato.
notify pgrst, 'reload schema';

-- Para reverter (só se nada usar estas colunas):
--   alter table public.av_forum_posts   drop column if exists attachment_path, drop column if exists attachment_name, drop column if exists attachments, drop column if exists edited_at;
--   alter table public.av_forum_replies drop column if exists attachment_path, drop column if exists attachment_name, drop column if exists attachments, drop column if exists edited_at;
