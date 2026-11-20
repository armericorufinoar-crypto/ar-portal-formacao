-- ============================================================================
-- AV Formação · Migração 025 · CRM real: próximo passo, motivo de perda, turma
-- Completa o ficheiro crm_followup_fields.sql (já executado ou não: é seguro
-- repetir). Só ACRESCENTA colunas a av_crm_deals; não apaga nada.
-- Colunas usadas pelo portal: next_step, next_contact_date, last_contact,
-- lost_reason, cohort.
-- ============================================================================
alter table public.av_crm_deals
  add column if not exists next_step         text,
  add column if not exists next_contact_date date,
  add column if not exists last_contact      date,
  add column if not exists lost_reason       text,
  add column if not exists cohort            text;

create index if not exists idx_av_crm_deals_next_contact_date
  on public.av_crm_deals (next_contact_date) where next_contact_date is not null;

-- 5 etapas: as antigas passam para a equivalente
update public.av_crm_deals set stage='CONTACTADO' where stage='QUALIFICADO';
update public.av_crm_deals set stage='PROPOSTA'    where stage='NEGOCIACAO';
