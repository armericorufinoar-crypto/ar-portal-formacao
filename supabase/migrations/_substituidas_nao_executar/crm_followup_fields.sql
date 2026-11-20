-- Etapa 1 do CRM: campos de acompanhamento comercial.
-- Executar uma única vez no SQL Editor do Supabase, no projecto da plataforma.

ALTER TABLE public.av_crm_deals
  ADD COLUMN IF NOT EXISTS next_step text,
  ADD COLUMN IF NOT EXISTS next_contact_date date,
  ADD COLUMN IF NOT EXISTS lost_reason text;

-- Índice para futuras consultas de contactos previstos/atrasados.
CREATE INDEX IF NOT EXISTS idx_av_crm_deals_next_contact_date
  ON public.av_crm_deals (next_contact_date)
  WHERE next_contact_date IS NOT NULL;

COMMENT ON COLUMN public.av_crm_deals.next_step IS 'Próxima acção comercial a executar';
COMMENT ON COLUMN public.av_crm_deals.next_contact_date IS 'Data prevista para o próximo contacto comercial';
COMMENT ON COLUMN public.av_crm_deals.lost_reason IS 'Motivo registado quando a oportunidade é perdida';
