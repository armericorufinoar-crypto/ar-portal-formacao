-- =====================================================================
-- 026_crm_proximo_passo.sql  ·  CRM: próximo passo, data do próximo contacto e motivo de perda
-- ESTADO: RASCUNHO PARA REVISÃO. Não executar sem autorização expressa.
-- Só acrescenta colunas (todas opcionais) a public.av_crm_deals, a tabela que o portal usa.
-- Não altera dados, não mexe em restrições nem em políticas (RLS), não toca no Treino.
-- Re-executável (add column if not exists).
--
-- A obrigação de preencher («negócio aberto precisa de próximo passo e data»; «Perdido precisa
-- de motivo») fica no ecrã. Não a ponho aqui como restrição porque os registos que já existem
-- ficariam inválidos e qualquer edição deles falharia.
-- =====================================================================
begin;

do $$
begin
  if to_regclass('public.av_crm_deals') is null then
    raise exception 'Falta public.av_crm_deals, a tabela que o portal usa para o CRM. A 019_crm_interessados.sql cria av_crm_leads e av_crm_opps, que são outras tabelas. Confirme o esquema do CRM antes de executar esta migração.';
  end if;
end $$;

alter table public.av_crm_deals
  add column if not exists next_step    text,
  add column if not exists next_contact date,
  add column if not exists lost_reason  text;

-- ajuda o alerta «atrasado» e a vista «Hoje» (só negócios com data marcada)
create index if not exists av_crm_deals_next_contact_ix
  on public.av_crm_deals (next_contact) where next_contact is not null;

commit;
