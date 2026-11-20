-- =====================================================================
-- 023_sessao_nivel.sql · Nível da sessão
-- Acrescenta a av_sessions a coluna "level" (nível a que a sessão se destina).
-- Vazio = todos os níveis (as sessões que já existem ficam assim).
-- O portal mostra ao formando as sessões do seu nível e dos níveis vizinhos.
-- Re-executável.
-- =====================================================================
begin;

alter table public.av_sessions add column if not exists level text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'av_sessions_level_chk') then
    alter table public.av_sessions
      add constraint av_sessions_level_chk
      check (level is null or level in ('estudante','empreendedor','empreendedor_plus','empresario'));
  end if;
end $$;

commit;
