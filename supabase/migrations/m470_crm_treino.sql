-- ============================================================================
-- AV Formação · Fase 2 · CRM de treino
-- Correr DEPOIS da Fase 1 (usa av_sim_is_staff()). Seguro repetir.
-- Tabelas próprias av_sim_*: NUNCA escreve em av_crm_deals.
-- ============================================================================

-- 1. Contactos
create table if not exists public.av_sim_contacts (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid(),
  mode       text not null default 'negocio' check (mode in ('guiado','negocio')),
  name       text not null,
  phone      text,
  source     text,
  created_at timestamptz not null default now()
);
create index if not exists av_sim_contacts_user_idx on public.av_sim_contacts(user_id, mode);

-- 2. Oportunidades (mesmas 7 etapas do CRM real)
create table if not exists public.av_sim_deals (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid(),
  mode           text not null default 'negocio' check (mode in ('guiado','negocio')),
  contact_id     uuid not null references public.av_sim_contacts(id) on delete cascade,
  title          text not null default '',
  stage          text not null default 'NOVO'
                 check (stage in ('NOVO','CONTACTADO','QUALIFICADO','PROPOSTA','NEGOCIACAO','GANHO','PERDIDO')),
  value          numeric not null default 0 check (value >= 0),
  expected_close date,
  last_activity  date not null default current_date,
  lost_reason    text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists av_sim_deals_user_idx on public.av_sim_deals(user_id, mode);

-- 3. Tarefas de follow-up
create table if not exists public.av_sim_tasks (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid(),
  mode       text not null default 'negocio' check (mode in ('guiado','negocio')),
  deal_id    uuid not null references public.av_sim_deals(id) on delete cascade,
  title      text not null,
  due        date not null,
  done       boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists av_sim_tasks_user_idx on public.av_sim_tasks(user_id, mode);

-- 4. RLS: o formando só vê e altera o que é seu; a equipa só lê
alter table public.av_sim_contacts enable row level security;
alter table public.av_sim_deals    enable row level security;
alter table public.av_sim_tasks    enable row level security;

drop policy if exists sim_ct_own   on public.av_sim_contacts;
drop policy if exists sim_ct_staff on public.av_sim_contacts;
create policy sim_ct_own   on public.av_sim_contacts for all    to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy sim_ct_staff on public.av_sim_contacts for select to authenticated using (public.av_sim_is_staff());

drop policy if exists sim_dl_own   on public.av_sim_deals;
drop policy if exists sim_dl_staff on public.av_sim_deals;
create policy sim_dl_own   on public.av_sim_deals for all    to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy sim_dl_staff on public.av_sim_deals for select to authenticated using (public.av_sim_is_staff());

drop policy if exists sim_tk_own   on public.av_sim_tasks;
drop policy if exists sim_tk_staff on public.av_sim_tasks;
create policy sim_tk_own   on public.av_sim_tasks for all    to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy sim_tk_staff on public.av_sim_tasks for select to authenticated using (public.av_sim_is_staff());

revoke all on public.av_sim_contacts, public.av_sim_deals, public.av_sim_tasks from anon;
grant select, insert, update, delete on public.av_sim_contacts, public.av_sim_deals, public.av_sim_tasks to authenticated;

-- 5. Cenário guiado: 25 contactos fictícios, com armadilhas de propósito
--    · 2 pares de duplicados (mesmo telefone)
--    · 7 oportunidades abertas sem tarefa de follow-up
--    · 4 oportunidades paradas há mais de 14 dias
--    Datas relativas a hoje, para as armadilhas funcionarem sempre.
create or replace function public.av_sim_seed(p_mode text default 'guiado')
returns void
language plpgsql security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
  r   record;
  cid uuid;
  did uuid;
begin
  if uid is null then raise exception 'Sessão inválida'; end if;
  if p_mode <> 'guiado' then raise exception 'Só o cenário guiado tem dados iniciais'; end if;
  if exists (select 1 from av_sim_deals where user_id = uid and mode = 'guiado') then return; end if;

  for r in
    select * from (values
      ( 1,'Ana Beatriz Mateus','923100001','Indicação',          'NOVO',       'Turma de empreendedores', 27000,  1, 2,20,null),
      ( 2,'Carlos Domingos',   '923100002','WhatsApp',           'NOVO',       'Turma de empreendedores', 27000,  3,null,25,null),
      ( 3,'Joana Kiala',       '923100003','Instagram',          'NOVO',       'Turma de empreendedores', 27000,  2, 1,25,null),
      ( 4,'Joana Kyala',       '923100003','Instagram',          'NOVO',       'Turma de empreendedores', 27000,  2,null,25,null),
      ( 5,'Pedro Manuel',      '923100005','Facebook',           'NOVO',       'Turma de empreendedores', 27000, 20,null,30,null),
      ( 6,'Luísa Sebastião',   '923100006','Indicação',          'CONTACTADO', 'Turma de empreendedores', 27000,  4, 3,15,null),
      ( 7,'Mário Fernandes',   '923100007','WhatsApp',           'CONTACTADO', 'Consultoria no negócio',  60000,  5, 2,18,null),
      ( 8,'Mario Fernandes',   '923100007','WhatsApp',           'CONTACTADO', 'Consultoria no negócio',  60000,  5,null,18,null),
      ( 9,'Teresa Gaspar',     '923100009','Presencial / Evento','CONTACTADO', 'Turma de empreendedores', 27000, 18, 5,10,null),
      (10,'Bento Cassoma',     '923100010','Telefone',           'QUALIFICADO','Turma de empreendedores', 27000,  6, 4,12,null),
      (11,'Helena Tomás',      '923100011','Indicação',          'QUALIFICADO','Turma de empreendedores', 27000,  9,null,14,null),
      (12,'Paulo Nzinga',      '923100012','Facebook',           'QUALIFICADO','Consultoria no negócio',  90000, 25,null, 7,null),
      (13,'Sónia Ventura',     '923100013','WhatsApp',           'QUALIFICADO','Turma de empreendedores', 27000,  2, 1,10,null),
      (14,'Domingos Lemos',    '923100014','Indicação',          'PROPOSTA',   'Turma de empreendedores', 27000,  3, 2, 8,null),
      (15,'Isabel Pinto',      '923100015','Instagram',          'PROPOSTA',   'Consultoria no negócio', 120000, 16, 6,10,null),
      (16,'André Quissanga',   '923100016','WhatsApp',           'PROPOSTA',   'Turma de empreendedores', 27000,  7,null, 9,null),
      (17,'Rosa Capita',       '923100017','Presencial / Evento','PROPOSTA',   'Turma de empreendedores', 27000,  4, 3,12,null),
      (18,'Fernando Chivela',  '923100018','Indicação',          'NEGOCIACAO', 'Consultoria no negócio', 150000,  2, 1, 5,null),
      (19,'Marta Kimbamba',    '923100019','Telefone',           'NEGOCIACAO', 'Turma de empreendedores', 27000,  3, 2, 6,null),
      (20,'Joaquim Neto',      '923100020','Facebook',           'NEGOCIACAO', 'Turma de empreendedores', 27000,  1, 1, 4,null),
      (21,'Cristina Bento',    '923100021','Indicação',          'GANHO',      'Turma de empreendedores', 27000, 10, 4,null,null),
      (22,'Rui Calado',        '923100022','WhatsApp',           'GANHO',      'Turma de empreendedores', 27000, 12,null,null,null),
      (23,'Nádia Pedro',       '923100023','Indicação',          'GANHO',      'Consultoria no negócio',  90000,  8,10,null,null),
      (24,'Elias Miguel',      '923100024','Instagram',          'PERDIDO',    'Turma de empreendedores', 27000, 30,null,null,'Preço'),
      (25,'Ruth Sakala',       '923100025','Facebook',           'PERDIDO',    'Turma de empreendedores', 27000, 22,null,null,'Sem resposta')
    ) as t(n,name,phone,source,stage,title,value,last_days,task_days,close_days,lost)
    order by n
  loop
    insert into av_sim_contacts(user_id, mode, name, phone, source)
    values (uid, 'guiado', r.name, r.phone, r.source) returning id into cid;

    insert into av_sim_deals(user_id, mode, contact_id, title, stage, value, expected_close, last_activity, lost_reason)
    values (uid, 'guiado', cid, r.title, r.stage, r.value,
            case when r.close_days is null then null else current_date + r.close_days end,
            current_date - r.last_days, r.lost)
    returning id into did;

    if r.task_days is not null then
      insert into av_sim_tasks(user_id, mode, deal_id, title, due)
      values (uid, 'guiado', did, 'Contacto de follow-up', current_date + r.task_days);
    end if;
  end loop;
end;
$$;
revoke all on function public.av_sim_seed(text) from public;
grant execute on function public.av_sim_seed(text) to authenticated;

-- 6. Repor o cenário guiado (apaga só os dados guiados do próprio formando e volta a criá-los)
create or replace function public.av_sim_reset(p_mode text default 'guiado')
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Sessão inválida'; end if;
  if p_mode <> 'guiado' then raise exception 'Só o cenário guiado pode ser reposto'; end if;
  delete from av_sim_contacts where user_id = auth.uid() and mode = 'guiado';  -- apaga oportunidades e tarefas em cascata
  perform public.av_sim_seed('guiado');
end;
$$;
revoke all on function public.av_sim_reset(text) from public;
grant execute on function public.av_sim_reset(text) to authenticated;
