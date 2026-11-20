-- =====================================================================
-- 019_crm_interessados.sql  ·  Pipeline CRM da AR Formação (um só funil de interessados)
-- ESTADO: RASCUNHO PARA REVISÃO. Não executar sem autorização expressa.
-- Acesso: administração e formador (usa av_train_is_staff() da 015). O formando não vê nada.
-- Independente do Treino e do diagnóstico. Re-executável (if not exists / drop ... if exists).
-- Um registo por interessado, do primeiro contacto ao formando:
--   NOVO → CONTACTADO → QUALIFICADO → PROPOSTA → NEGOCIACAO → GANHO / PERDIDO
-- Códigos CRM-0001, CRM-0002… atribuídos pelo servidor, por ordem de criação.
-- O id é texto para aceitar os ids que o portal gera e a importação do que ficou no navegador.
-- =====================================================================
begin;

do $$
begin
  if to_regprocedure('public.av_train_is_staff()') is null then
    raise exception 'Falta av_train_is_staff(): execute primeiro a 015_treino_niveis.sql';
  end if;
end $$;

create table if not exists public.av_crm_deals (
  id             text primary key,
  code           text not null unique,
  name           text not null,
  phone          text,
  email          text,
  origin         text,
  interest       text,
  owner          text,
  stage          text not null default 'NOVO'
                 check (stage in ('NOVO','CONTACTADO','QUALIFICADO','PROPOSTA','NEGOCIACAO','GANHO','PERDIDO')),
  est_value      numeric not null default 0 check (est_value >= 0),
  probability    int not null default 10 check (probability between 0 and 100),
  expected_close date,
  entered_on     date,
  notes          text,
  stage_dates    jsonb not null default '{}',
  formando_id    text,   -- id do formando registado quando o negócio é ganho (sem FK, de propósito)
  created_by     uuid default auth.uid() references auth.users(id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- Numeração simples, automática e cronológica (apagar um registo deixa um intervalo).
create sequence if not exists public.av_crm_deal_seq;

create or replace function public.av_crm_set_code() returns trigger
language plpgsql as $$
begin
  if nullif(btrim(coalesce(new.code, '')), '') is null then
    new.code := 'CRM-' || lpad(nextval('public.av_crm_deal_seq')::text, 4, '0');
  end if;
  return new;
end $$;
drop trigger if exists av_crm_deals_code on public.av_crm_deals;
create trigger av_crm_deals_code before insert on public.av_crm_deals
  for each row execute function public.av_crm_set_code();

create or replace function public.av_crm_touch() returns trigger
language plpgsql as $$ begin new.updated_at := now(); return new; end $$;
drop trigger if exists av_crm_deals_touch on public.av_crm_deals;
create trigger av_crm_deals_touch before update on public.av_crm_deals
  for each row execute function public.av_crm_touch();

alter table public.av_crm_deals enable row level security;
drop policy if exists crm_deals_all on public.av_crm_deals;
create policy crm_deals_all on public.av_crm_deals for all
  using (public.av_train_is_staff()) with check (public.av_train_is_staff());

revoke all on public.av_crm_deals from anon;

commit;
