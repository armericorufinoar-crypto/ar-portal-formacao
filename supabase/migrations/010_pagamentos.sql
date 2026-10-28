-- 010_pagamentos.sql
-- Módulo de Pagamentos (referência manual): planos de parcelas, pró-formas, pedidos de pagamento,
-- comprovativos, facturas internas numeradas e auditoria.
--
-- Fluxo (dados de pagamento FIXOS, sem esperar por referência):
--   1. Admin gera as pró-formas (parcelas) de cada formando a partir de um plano.
--   2. Formando selecciona pró-formas "Por pagar" e escolhe o método:
--        Multicaixa Express  -> paga para o número de telemóvel fixo (av_pay_settings.express_phone)
--        Transferência       -> paga para o IBAN fixo (av_pay_settings.iban)
--        Numerário           -> paga no balcão
--      O pedido fica logo "Aguarda pagamento", com o total calculado no servidor.
--   3. Formando paga fora do portal e anexa o comprovativo ("Comprovativo enviado").
--   4. Admin confirma -> pró-formas "Paga" e é emitida a factura interna numerada (ou rejeita com motivo).
--
-- Segurança: todas as escritas passam por funções (security definer) que verificam o papel; as tabelas
-- só têm políticas de LEITURA (admin vê tudo; formando vê apenas o que é seu). Os valores não são
-- aceites do cliente: o total é calculado no servidor a partir das pró-formas.
-- Requer: 001 (av_profiles, av_staff, av_touch_updated_at). É seguro correr mais de uma vez.
-- NOTA: a factura é um documento INTERNO do portal; não tem valor fiscal.

-- ---------------------------------------------------------------------------------------------
-- Auxiliares
-- ---------------------------------------------------------------------------------------------
-- Mesma definição da migração 005; repetida aqui para a 010 não depender dela.
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

create or replace function public.av_my_staff_id()
returns uuid language sql stable security definer set search_path = ''
as $$ select p.staff_id from public.av_profiles p where p.user_id = auth.uid() $$;

create table if not exists public.av_pay_counters (
  kind text not null,
  year int not null,
  last int not null default 0,
  primary key (kind, year)
);

create or replace function public.av_next_number(p_kind text)
returns text language plpgsql security definer set search_path = ''
as $$
declare y int := extract(year from now())::int; n int;
begin
  insert into public.av_pay_counters (kind, year, last) values (p_kind, y, 1)
  on conflict (kind, year) do update set last = public.av_pay_counters.last + 1
  returning last into n;
  return n::text || '/' || y::text;
end $$;

-- ---------------------------------------------------------------------------------------------
-- Tabelas
-- ---------------------------------------------------------------------------------------------
create table if not exists public.av_pay_settings (
  id int primary key default 1 check (id = 1),
  issuer_name text not null default '',
  issuer_nif text not null default '',
  issuer_address text not null default '',
  express_phone text not null default '',
  mc_entity text not null default '',
  bank_name text not null default '',
  iban text not null default '',
  instructions text not null default '',
  invoice_footer text not null default 'Documento interno de controlo de pagamentos, sem valor fiscal.',
  updated_at timestamptz not null default now()
);
alter table public.av_pay_settings add column if not exists express_phone text not null default '';
insert into public.av_pay_settings (id) values (1) on conflict (id) do nothing;

create table if not exists public.av_fee_plans (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 200),
  area text check (area is null or area in ('Finanças e Investimentos','Marketing e Vendas','Negócios','Oratória','Liderança')),
  installments int not null check (installments between 1 and 60),
  installment_amount numeric(14,2) not null check (installment_amount > 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.av_proformas (
  id uuid primary key default gen_random_uuid(),
  doc_number text not null unique,
  staff_id uuid not null references public.av_staff(id) on delete restrict,
  plan_id uuid references public.av_fee_plans(id) on delete set null,
  kind text not null default 'Formações',
  description text not null,
  installment_no int,
  amount numeric(14,2) not null check (amount > 0),
  due_date date not null,
  status text not null default 'Por pagar'
    check (status in ('Por pagar','Pagamento pendente','Paga','Anulada')),
  void_reason text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists av_proformas_staff_idx on public.av_proformas(staff_id, status);
create index if not exists av_proformas_due_idx on public.av_proformas(due_date) where status in ('Por pagar','Pagamento pendente');

create table if not exists public.av_payment_requests (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.av_staff(id) on delete restrict,
  requested_by uuid references auth.users(id) on delete set null,
  method text not null check (method in ('Multicaixa Express','Transferência bancária','Numerário')),
  notes text check (notes is null or length(notes) <= 1000),
  total numeric(14,2) not null check (total > 0),
  reference_entity text,
  reference_number text,
  expires_at date,
  proof_path text,
  status text not null default 'Aguarda pagamento'
    check (status in ('Aguarda referência','Aguarda pagamento','Comprovativo enviado','Confirmado','Rejeitado','Cancelado')),
  review_note text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists av_payreq_staff_idx on public.av_payment_requests(staff_id, status);
create index if not exists av_payreq_status_idx on public.av_payment_requests(status, created_at);

create table if not exists public.av_payment_request_items (
  request_id uuid not null references public.av_payment_requests(id) on delete cascade,
  proforma_id uuid not null references public.av_proformas(id) on delete restrict,
  amount numeric(14,2) not null,
  primary key (request_id, proforma_id)
);
create index if not exists av_payitems_proforma_idx on public.av_payment_request_items(proforma_id);

create table if not exists public.av_invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_number text not null unique,
  staff_id uuid not null references public.av_staff(id) on delete restrict,
  request_id uuid not null references public.av_payment_requests(id) on delete restrict,
  total numeric(14,2) not null,
  status text not null default 'Emitida' check (status in ('Emitida','Anulada')),
  void_reason text,
  issued_by uuid references auth.users(id) on delete set null,
  issued_at timestamptz not null default now()
);
create index if not exists av_invoices_staff_idx on public.av_invoices(staff_id, issued_at desc);

create table if not exists public.av_payment_audit (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor uuid,
  action text not null,
  entity text not null,
  entity_id text,
  detail jsonb
);

drop trigger if exists av_proformas_touch on public.av_proformas;
create trigger av_proformas_touch before update on public.av_proformas
  for each row execute procedure public.av_touch_updated_at();
drop trigger if exists av_payreq_touch on public.av_payment_requests;
create trigger av_payreq_touch before update on public.av_payment_requests
  for each row execute procedure public.av_touch_updated_at();

-- Actualização de bases criadas com a versão anterior (referência MultiCaixa): converte e troca a restrição.
alter table public.av_payment_requests drop constraint if exists av_payment_requests_method_check;
update public.av_payment_requests set method = 'Multicaixa Express' where method = 'Referência MultiCaixa';
update public.av_payment_requests set status = 'Aguarda pagamento' where status = 'Aguarda referência';
alter table public.av_payment_requests add constraint av_payment_requests_method_check
  check (method in ('Multicaixa Express','Transferência bancária','Numerário'));

-- ---------------------------------------------------------------------------------------------
-- RLS: só leitura para clientes; escritas via funções
-- ---------------------------------------------------------------------------------------------
alter table public.av_pay_counters enable row level security;
alter table public.av_pay_settings enable row level security;
alter table public.av_fee_plans enable row level security;
alter table public.av_proformas enable row level security;
alter table public.av_payment_requests enable row level security;
alter table public.av_payment_request_items enable row level security;
alter table public.av_invoices enable row level security;
alter table public.av_payment_audit enable row level security;

revoke all on public.av_pay_counters, public.av_pay_settings, public.av_fee_plans, public.av_proformas,
  public.av_payment_requests, public.av_payment_request_items, public.av_invoices, public.av_payment_audit
  from anon, authenticated;
grant select on public.av_pay_settings, public.av_fee_plans, public.av_proformas, public.av_payment_requests,
  public.av_payment_request_items, public.av_invoices, public.av_payment_audit to authenticated;
-- definições e planos: o admin altera directamente
grant insert, update, delete on public.av_fee_plans to authenticated;
grant update on public.av_pay_settings to authenticated;

drop policy if exists av_pay_settings_read on public.av_pay_settings;
create policy av_pay_settings_read on public.av_pay_settings for select to authenticated using (true);
drop policy if exists av_pay_settings_admin on public.av_pay_settings;
create policy av_pay_settings_admin on public.av_pay_settings for update to authenticated
  using ((select public.av_is_admin())) with check ((select public.av_is_admin()));

drop policy if exists av_fee_plans_admin on public.av_fee_plans;
create policy av_fee_plans_admin on public.av_fee_plans for all to authenticated
  using ((select public.av_is_admin())) with check ((select public.av_is_admin()));

drop policy if exists av_proformas_read on public.av_proformas;
create policy av_proformas_read on public.av_proformas for select to authenticated
  using ((select public.av_is_admin()) or staff_id = (select public.av_my_staff_id()));

drop policy if exists av_payreq_read on public.av_payment_requests;
create policy av_payreq_read on public.av_payment_requests for select to authenticated
  using ((select public.av_is_admin()) or staff_id = (select public.av_my_staff_id()));

drop policy if exists av_payitems_read on public.av_payment_request_items;
create policy av_payitems_read on public.av_payment_request_items for select to authenticated
  using (exists (select 1 from public.av_payment_requests r where r.id = request_id
    and ((select public.av_is_admin()) or r.staff_id = (select public.av_my_staff_id()))));

drop policy if exists av_invoices_read on public.av_invoices;
create policy av_invoices_read on public.av_invoices for select to authenticated
  using ((select public.av_is_admin()) or staff_id = (select public.av_my_staff_id()));

drop policy if exists av_payaudit_read on public.av_payment_audit;
create policy av_payaudit_read on public.av_payment_audit for select to authenticated
  using ((select public.av_is_admin()));

-- ---------------------------------------------------------------------------------------------
-- Funções (todas security definer; verificam o papel dentro)
-- ---------------------------------------------------------------------------------------------
create or replace function public.av_pay_audit(p_action text, p_entity text, p_id text, p_detail jsonb default null)
returns void language sql security definer set search_path = ''
as $$ insert into public.av_payment_audit (actor, action, entity, entity_id, detail)
      values (auth.uid(), p_action, p_entity, p_id, p_detail) $$;
revoke all on function public.av_pay_audit(text,text,text,jsonb) from public, anon, authenticated;

-- Admin: gera as parcelas (pró-formas) de um plano para vários formandos. Ignora quem já as tem.
create or replace function public.av_generate_proformas(p_staff uuid[], p_plan uuid, p_first_due date default current_date)
returns int language plpgsql security definer set search_path = ''
as $$
declare pl public.av_fee_plans%rowtype; s uuid; n int; made int := 0;
begin
  if not coalesce(public.av_is_admin(), false) then raise exception 'Apenas a administração pode gerar pró-formas.'; end if;
  select * into pl from public.av_fee_plans where id = p_plan and active;
  if not found then raise exception 'Plano inexistente ou inactivo.'; end if;
  if p_staff is null or array_length(p_staff, 1) is null then raise exception 'Escolha pelo menos um formando.'; end if;
  foreach s in array p_staff loop
    if not exists (select 1 from public.av_staff where id = s) then continue; end if;
    if exists (select 1 from public.av_proformas where staff_id = s and plan_id = p_plan and status <> 'Anulada') then continue; end if;
    for n in 1..pl.installments loop
      insert into public.av_proformas (doc_number, staff_id, plan_id, description, installment_no, amount, due_date, created_by)
      values (public.av_next_number('proforma'), s, p_plan,
              'Parcela nº ' || n || ' - ' || pl.name, n, pl.installment_amount,
              (p_first_due + make_interval(months => n - 1))::date, auth.uid());
      made := made + 1;
    end loop;
  end loop;
  perform public.av_pay_audit('gerar_proformas', 'plan', p_plan::text, jsonb_build_object('formandos', array_length(p_staff,1), 'parcelas', made));
  return made;
end $$;

-- Admin: anula uma pró-forma que ainda não foi paga nem está em pedido.
create or replace function public.av_void_proforma(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not coalesce(public.av_is_admin(), false) then raise exception 'Apenas a administração pode anular pró-formas.'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'Indique o motivo.'; end if;
  update public.av_proformas set status = 'Anulada', void_reason = trim(p_reason)
   where id = p_id and status = 'Por pagar';
  if not found then raise exception 'Só é possível anular pró-formas "Por pagar".'; end if;
  perform public.av_pay_audit('anular_proforma', 'proforma', p_id::text, jsonb_build_object('motivo', p_reason));
end $$;

-- Formando: cria pedido de pagamento com as pró-formas escolhidas.
create or replace function public.av_create_payment_request(p_proformas uuid[], p_method text, p_notes text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare me uuid := public.av_my_staff_id(); n int; tot numeric(14,2); rid uuid; st text;
begin
  if me is null then raise exception 'A sua conta não está ligada a uma ficha de formando.'; end if;
  if p_proformas is null or array_length(p_proformas, 1) is null then raise exception 'Seleccione pelo menos uma pró-forma.'; end if;
  if array_position(p_proformas, null) is not null then raise exception 'Seleccione apenas pró-formas válidas.'; end if;
  if p_method not in ('Multicaixa Express','Transferência bancária','Numerário') then raise exception 'Método inválido.'; end if;
  perform 1 from public.av_proformas where id = any (p_proformas) for update;
  select count(*), coalesce(sum(amount), 0) into n, tot
    from public.av_proformas where id = any (p_proformas) and staff_id = me and status = 'Por pagar';
  if n = 0 or n <> (select count(distinct x) from unnest(p_proformas) x) then
    raise exception 'Uma ou mais pró-formas não estão disponíveis para pagamento.';
  end if;
  st := 'Aguarda pagamento';
  insert into public.av_payment_requests (staff_id, requested_by, method, notes, total, status)
  values (me, auth.uid(), p_method, nullif(trim(coalesce(p_notes, '')), ''), tot, st) returning id into rid;
  insert into public.av_payment_request_items (request_id, proforma_id, amount)
    select rid, id, amount from public.av_proformas where id = any (p_proformas);
  update public.av_proformas set status = 'Pagamento pendente' where id = any (p_proformas);
  perform public.av_pay_audit('criar_pedido', 'request', rid::text, jsonb_build_object('total', tot, 'metodo', p_method));
  return rid;
end $$;

-- Admin (opcional): regista uma referência/validade num pedido (ex.: n.º da transferência).
create or replace function public.av_issue_reference(p_request uuid, p_entity text, p_reference text, p_expires date default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare r public.av_payment_requests%rowtype;
begin
  if not coalesce(public.av_is_admin(), false) then raise exception 'Apenas a administração pode emitir referências.'; end if;
  select * into r from public.av_payment_requests where id = p_request for update;
  if not found or r.status not in ('Aguarda referência','Aguarda pagamento') then
    raise exception 'O pedido não está a aguardar referência.';
  end if;
  update public.av_payment_requests
     set reference_entity = nullif(trim(coalesce(p_entity,'')), ''), reference_number = nullif(trim(coalesce(p_reference,'')), ''),
         expires_at = p_expires, status = 'Aguarda pagamento'
   where id = p_request;
  perform public.av_pay_audit('emitir_referencia', 'request', p_request::text, jsonb_build_object('entidade', p_entity, 'referencia', p_reference));
end $$;

-- Formando: anexa o comprovativo (já carregado para o bucket av-comprovativos).
create or replace function public.av_attach_proof(p_request uuid, p_path text)
returns void language plpgsql security definer set search_path = ''
as $$
declare me uuid := public.av_my_staff_id(); r public.av_payment_requests%rowtype;
begin
  select * into r from public.av_payment_requests where id = p_request for update;
  if not found or me is null or r.staff_id <> me then raise exception 'Pedido não encontrado.'; end if;
  if r.status not in ('Aguarda pagamento','Comprovativo enviado') then
    raise exception 'O pedido ainda não aceita comprovativo ou já foi tratado.';
  end if;
  if p_path is null or left(p_path, length(me::text) + 1) <> me::text || '/' then
    raise exception 'Caminho de ficheiro inválido.';
  end if;
  update public.av_payment_requests set proof_path = p_path, status = 'Comprovativo enviado' where id = p_request;
  perform public.av_pay_audit('enviar_comprovativo', 'request', p_request::text, jsonb_build_object('ficheiro', p_path));
end $$;

-- Interna: confirma um pedido e emite a factura. Usada por av_confirm_payment e av_admin_register_payment.
create or replace function public.av_do_confirm(p_request uuid, p_note text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare r public.av_payment_requests%rowtype; inv uuid;
begin
  select * into r from public.av_payment_requests where id = p_request for update;
  if not found or r.status not in ('Aguarda pagamento','Comprovativo enviado') then
    raise exception 'O pedido não está pronto para confirmação.';
  end if;
  update public.av_payment_requests
     set status = 'Confirmado', review_note = nullif(trim(coalesce(p_note,'')), ''), reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_request;
  update public.av_proformas set status = 'Paga'
   where id in (select proforma_id from public.av_payment_request_items where request_id = p_request);
  insert into public.av_invoices (invoice_number, staff_id, request_id, total, issued_by)
  values (public.av_next_number('factura'), r.staff_id, p_request, r.total, auth.uid()) returning id into inv;
  perform public.av_pay_audit('confirmar_pagamento', 'request', p_request::text, jsonb_build_object('factura', inv, 'total', r.total));
  return inv;
end $$;
revoke all on function public.av_do_confirm(uuid, text) from public, anon, authenticated;

create or replace function public.av_confirm_payment(p_request uuid, p_note text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
begin
  if not coalesce(public.av_is_admin(), false) then raise exception 'Apenas a administração pode confirmar pagamentos.'; end if;
  return public.av_do_confirm(p_request, p_note);
end $$;

-- Admin: regista directamente um pagamento (ex.: numerário no balcão) sem pedido prévio do formando.
-- Todas as pró-formas têm de ser do mesmo formando e estar "Por pagar".
create or replace function public.av_admin_register_payment(p_proformas uuid[], p_method text, p_reference text default null, p_note text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare n int; nd int; tot numeric(14,2); ns int; sid uuid; rid uuid;
begin
  if not coalesce(public.av_is_admin(), false) then raise exception 'Apenas a administração pode registar pagamentos.'; end if;
  if p_proformas is null or array_length(p_proformas, 1) is null then raise exception 'Seleccione pelo menos uma pró-forma.'; end if;
  if array_position(p_proformas, null) is not null then raise exception 'Seleccione apenas pró-formas válidas.'; end if;
  if p_method not in ('Multicaixa Express','Transferência bancária','Numerário') then raise exception 'Método inválido.'; end if;
  perform 1 from public.av_proformas where id = any (p_proformas) for update;
  select count(*), coalesce(sum(amount), 0), count(distinct staff_id), (array_agg(staff_id))[1]
    into n, tot, ns, sid
    from public.av_proformas where id = any (p_proformas) and status = 'Por pagar';
  select count(distinct x) into nd from unnest(p_proformas) x;
  if n = 0 or n <> nd then raise exception 'Uma ou mais pró-formas não estão disponíveis para pagamento.'; end if;
  if ns <> 1 then raise exception 'As pró-formas têm de ser do mesmo formando.'; end if;
  insert into public.av_payment_requests (staff_id, requested_by, method, notes, total, reference_number, status)
  values (sid, auth.uid(), p_method, 'Registado pela administração', tot, nullif(trim(coalesce(p_reference,'')), ''), 'Aguarda pagamento')
  returning id into rid;
  insert into public.av_payment_request_items (request_id, proforma_id, amount)
    select rid, id, amount from public.av_proformas where id = any (p_proformas);
  update public.av_proformas set status = 'Pagamento pendente' where id = any (p_proformas);
  return public.av_do_confirm(rid, p_note);
end $$;

-- Admin: rejeita um pedido (motivo obrigatório); as pró-formas voltam a "Por pagar".
create or replace function public.av_reject_payment(p_request uuid, p_reason text)
returns void language plpgsql security definer set search_path = ''
as $$
declare r public.av_payment_requests%rowtype;
begin
  if not coalesce(public.av_is_admin(), false) then raise exception 'Apenas a administração pode rejeitar pagamentos.'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'Indique o motivo.'; end if;
  select * into r from public.av_payment_requests where id = p_request for update;
  if not found or r.status not in ('Aguarda referência','Aguarda pagamento','Comprovativo enviado') then
    raise exception 'Este pedido já foi tratado.';
  end if;
  update public.av_payment_requests
     set status = 'Rejeitado', review_note = trim(p_reason), reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_request;
  update public.av_proformas set status = 'Por pagar'
   where status = 'Pagamento pendente'
     and id in (select proforma_id from public.av_payment_request_items where request_id = p_request);
  perform public.av_pay_audit('rejeitar_pagamento', 'request', p_request::text, jsonb_build_object('motivo', p_reason));
end $$;

-- Formando (antes de pagar) ou admin: cancela um pedido; as pró-formas voltam a "Por pagar".
create or replace function public.av_cancel_payment_request(p_request uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare r public.av_payment_requests%rowtype; adm boolean := coalesce(public.av_is_admin(), false);
begin
  select * into r from public.av_payment_requests where id = p_request for update;
  if not found or (not adm and r.staff_id is distinct from public.av_my_staff_id()) then
    raise exception 'Pedido não encontrado.';
  end if;
  if r.status not in ('Aguarda referência','Aguarda pagamento') and not (adm and r.status = 'Comprovativo enviado') then
    raise exception 'Este pedido já não pode ser cancelado.';
  end if;
  update public.av_payment_requests set status = 'Cancelado', reviewed_by = auth.uid(), reviewed_at = now() where id = p_request;
  update public.av_proformas set status = 'Por pagar'
   where status = 'Pagamento pendente'
     and id in (select proforma_id from public.av_payment_request_items where request_id = p_request);
  perform public.av_pay_audit('cancelar_pedido', 'request', p_request::text, null);
end $$;

-- Admin: anula uma factura emitida (motivo obrigatório); as pró-formas voltam a "Por pagar".
create or replace function public.av_void_invoice(p_invoice uuid, p_reason text)
returns void language plpgsql security definer set search_path = ''
as $$
declare i public.av_invoices%rowtype;
begin
  if not coalesce(public.av_is_admin(), false) then raise exception 'Apenas a administração pode anular facturas.'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'Indique o motivo.'; end if;
  select * into i from public.av_invoices where id = p_invoice for update;
  if not found or i.status <> 'Emitida' then raise exception 'Factura inexistente ou já anulada.'; end if;
  update public.av_invoices set status = 'Anulada', void_reason = trim(p_reason) where id = p_invoice;
  update public.av_payment_requests set status = 'Cancelado', review_note = 'Factura anulada: ' || trim(p_reason) where id = i.request_id;
  update public.av_proformas set status = 'Por pagar'
   where status = 'Paga'
     and id in (select proforma_id from public.av_payment_request_items where request_id = i.request_id);
  perform public.av_pay_audit('anular_factura', 'invoice', p_invoice::text, jsonb_build_object('motivo', p_reason, 'numero', i.invoice_number));
end $$;

-- Permissões de execução: só utilizadores autenticados (cada função valida o papel por dentro).
revoke all on function public.av_generate_proformas(uuid[], uuid, date), public.av_void_proforma(uuid, text),
  public.av_create_payment_request(uuid[], text, text), public.av_issue_reference(uuid, text, text, date),
  public.av_attach_proof(uuid, text), public.av_confirm_payment(uuid, text),
  public.av_admin_register_payment(uuid[], text, text, text), public.av_reject_payment(uuid, text),
  public.av_cancel_payment_request(uuid), public.av_void_invoice(uuid, text), public.av_my_staff_id(),
  public.av_next_number(text) from public, anon;
grant execute on function public.av_generate_proformas(uuid[], uuid, date), public.av_void_proforma(uuid, text),
  public.av_create_payment_request(uuid[], text, text), public.av_issue_reference(uuid, text, text, date),
  public.av_attach_proof(uuid, text), public.av_confirm_payment(uuid, text),
  public.av_admin_register_payment(uuid[], text, text, text), public.av_reject_payment(uuid, text),
  public.av_cancel_payment_request(uuid), public.av_void_invoice(uuid, text), public.av_my_staff_id() to authenticated;
revoke all on function public.av_next_number(text) from authenticated;

-- ---------------------------------------------------------------------------------------------
-- Resumo por formando (admin vê todos; formando vê só o seu, por RLS das tabelas)
-- ---------------------------------------------------------------------------------------------
create or replace view public.av_pay_summary with (security_invoker = true) as
select
  s.id as staff_id,
  s.staff_number,
  s.full_name,
  coalesce(sum(p.amount) filter (where p.status <> 'Anulada'), 0) as total_due,
  coalesce(sum(p.amount) filter (where p.status = 'Paga'), 0) as total_paid,
  coalesce(sum(p.amount) filter (where p.status in ('Por pagar','Pagamento pendente')), 0) as outstanding,
  coalesce(sum(p.amount) filter (where p.status in ('Por pagar','Pagamento pendente') and p.due_date < current_date), 0) as overdue,
  count(*) filter (where p.status in ('Por pagar','Pagamento pendente') and p.due_date < current_date) as overdue_count
from public.av_staff s
left join public.av_proformas p on p.staff_id = s.id
group by s.id, s.staff_number, s.full_name;
grant select on public.av_pay_summary to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Storage: bucket privado para comprovativos (pasta = id da ficha do formando)
-- ---------------------------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('av-comprovativos', 'av-comprovativos', false, 5242880, array['application/pdf','image/jpeg','image/png'])
on conflict (id) do update set public = false, file_size_limit = 5242880,
  allowed_mime_types = array['application/pdf','image/jpeg','image/png'];

drop policy if exists av_comp_read on storage.objects;
create policy av_comp_read on storage.objects for select to authenticated
  using (bucket_id = 'av-comprovativos'
    and ((select public.av_is_admin()) or (storage.foldername(name))[1] = (select public.av_my_staff_id())::text));

drop policy if exists av_comp_insert on storage.objects;
create policy av_comp_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'av-comprovativos'
    and ((select public.av_is_admin()) or (storage.foldername(name))[1] = (select public.av_my_staff_id())::text));

drop policy if exists av_comp_delete on storage.objects;
create policy av_comp_delete on storage.objects for delete to authenticated
  using (bucket_id = 'av-comprovativos' and (select public.av_is_admin()));
