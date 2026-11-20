-- =====================================================================
-- 016_diagnostico_org.sql  ·  Diagnóstico Organizacional (uso interno)
-- Fluxo de 4 etapas: Empresa · Necessidades · Investimento · Plano
-- ESTADO: RASCUNHO PARA REVISÃO. Não executar sem autorização expressa.
-- Acesso: só administração e formador (usa av_train_is_staff() da 015).
-- Todo o catálogo semeado abaixo é RASCUNHO (reviewed = false).
-- =====================================================================
begin;

-- 1. Parâmetros (linha única; só a administração altera)
create table public.av_diag_settings (
  id               int primary key default 1 check (id = 1),
  priority_weights jsonb not null default '{"critica":4,"alta":3,"media":2,"baixa":1}',
  horizon_weights  jsonb not null default '{"imediatamente":4,"1_3m":3,"3_6m":2,"6_12m":1.5,"indefinido":1}',
  volume_cap       int   not null default 50,
  investment_bands jsonb not null default '[
    {"code":"b1","label":"1.500.000 – 3.000.000 Kz"},
    {"code":"b2","label":"3.000.000 – 5.000.000 Kz"},
    {"code":"b3","label":"5.000.000 – 10.000.000 Kz"},
    {"code":"b4","label":"10.000.000 – 15.000.000 Kz"},
    {"code":"b5","label":"15.000.000 – 25.000.000 Kz"},
    {"code":"b6","label":"Acima de 25.000.000 Kz"},
    {"code":"indefinido","label":"Ainda não definido"}]'
);
insert into public.av_diag_settings (id) values (1);

-- 2. Catálogo gerador (áreas → problemas → regras → soluções)
create table public.av_diag_areas (
  code text primary key, name text not null, description text, sort int not null default 0);

create table public.av_diag_problems (
  code text primary key,
  area_code text not null references public.av_diag_areas(code) on delete cascade,
  label text not null, sort int not null default 0, reviewed boolean not null default false);

create table public.av_diag_solutions (
  code text primary key, name text not null,
  family text not null default 'Soft skills — Competências Comportamentais',
  default_format text not null check (default_format in ('Programa','Treinamento','Formação','Workshop','Teambuilding','Mentoria')),
  reviewed boolean not null default false);

create table public.av_diag_rules (
  id uuid primary key default gen_random_uuid(),
  problem_code  text not null references public.av_diag_problems(code)  on delete cascade,
  solution_code text not null references public.av_diag_solutions(code) on delete cascade,
  weight numeric not null default 1 check (weight > 0),
  unique (problem_code, solution_code));

-- 3. Processos
create table public.av_org_diag (
  id uuid primary key default gen_random_uuid(),
  code         text not null unique,   -- ex.: PL-2026-3F9A1C
  consult_code text not null unique,   -- ex.: IL-7QX2KD
  company_name text, sector text, headcount_band text,
  contact_name text, contact_email text, contact_whatsapp text,
  step int not null default 1 check (step between 1 and 4),
  status text not null default 'rascunho' check (status in ('rascunho','concluido')),
  investment_band text,
  next_meeting date,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz);

create table public.av_org_diag_needs (
  id uuid primary key default gen_random_uuid(),
  diag_id   uuid not null references public.av_org_diag(id) on delete cascade,
  area_code text not null references public.av_diag_areas(code),
  problems  text[] not null default '{}',
  -- [{"public":"tecnicos","people":6}, ...]
  publics   jsonb  not null default '[]',
  priority  text   not null check (priority in ('critica','alta','media','baixa')),
  horizon   text   not null check (horizon in ('imediatamente','1_3m','3_6m','6_12m','indefinido')),
  score     numeric,
  unique (diag_id, area_code));

create table public.av_org_diag_recs (
  id uuid primary key default gen_random_uuid(),
  diag_id   uuid not null references public.av_org_diag(id) on delete cascade,
  area_code text not null,
  public_code text not null check (public_code in ('alta_direccao','gestores','chefias','tecnicos','operacionais','toda_org')),
  solution_code text not null references public.av_diag_solutions(code),
  level text not null check (level in ('Estratégico','Tático','Operacional')),
  priority text not null, format text not null,
  matches int not null default 1, score numeric not null,
  selected boolean not null default false,
  unique (diag_id, area_code, public_code, solution_code));

-- 4. RLS: tudo interno
alter table public.av_diag_settings  enable row level security;
alter table public.av_diag_areas     enable row level security;
alter table public.av_diag_problems  enable row level security;
alter table public.av_diag_solutions enable row level security;
alter table public.av_diag_rules     enable row level security;
alter table public.av_org_diag       enable row level security;
alter table public.av_org_diag_needs enable row level security;
alter table public.av_org_diag_recs  enable row level security;

create policy ds_sel on public.av_diag_settings for select using (public.av_train_is_staff());
create policy ds_upd on public.av_diag_settings for update using (public.av_train_role()='admin') with check (public.av_train_role()='admin');
create policy da_sel on public.av_diag_areas     for select using (public.av_train_is_staff());
create policy dp_sel on public.av_diag_problems  for select using (public.av_train_is_staff());
create policy dsol_sel on public.av_diag_solutions for select using (public.av_train_is_staff());
create policy dr_sel on public.av_diag_rules     for select using (public.av_train_is_staff());
create policy da_adm on public.av_diag_areas     for all using (public.av_train_role()='admin') with check (public.av_train_role()='admin');
create policy dp_adm on public.av_diag_problems  for all using (public.av_train_role()='admin') with check (public.av_train_role()='admin');
create policy dsol_adm on public.av_diag_solutions for all using (public.av_train_role()='admin') with check (public.av_train_role()='admin');
create policy dr_adm on public.av_diag_rules     for all using (public.av_train_role()='admin') with check (public.av_train_role()='admin');
-- Processos: leitura para a equipa; escrita só pelas funções abaixo.
create policy od_sel on public.av_org_diag       for select using (public.av_train_is_staff());
create policy on_sel on public.av_org_diag_needs for select using (public.av_train_is_staff());
create policy or_sel on public.av_org_diag_recs  for select using (public.av_train_is_staff());

-- 5. Semente do catálogo (RASCUNHO a rever; Gestão & Performance segue o vídeo de referência)
insert into public.av_diag_areas (code,name,description,sort) values
 ('lideranca_cultura','Liderança & Cultura','Capacidade dos líderes de inspirar, decidir e desenvolver equipas, e os valores que definem a cultura.',1),
 ('gestao_performance','Gestão & Performance','Clareza dos objectivos, medição de resultados e capacidade de executar a estratégia com eficácia.',2),
 ('negocio_comercial','Negócio & Comercial','Estratégia, processos e competências que impulsionam vendas, negociação e relação com clientes.',3),
 ('digital_tecnologia','Digital, Tecnologia & Futuro','Adopção de tecnologia, automação e inteligência artificial para transformar e modernizar a organização.',4),
 ('pessoas_comportamento','Pessoas & Comportamento','Atracção, retenção, desenvolvimento e comportamento dos colaboradores, incluindo inteligência emocional e dinâmicas de equipa.',5);

insert into public.av_diag_problems (code,area_code,label,sort) values
 ('lid_sem_inspirar','lideranca_cultura','Líderes que não inspiram nem desenvolvem as equipas',1),
 ('lid_decisoes_lentas','lideranca_cultura','Decisões lentas ou pouco fundamentadas',2),
 ('lid_valores_nao_vividos','lideranca_cultura','Valores definidos mas não vividos no dia a dia',3),
 ('lid_resistencia_mudanca','lideranca_cultura','Resistência à mudança',4),
 ('gp_objectivos_pouco_claros','gestao_performance','Objectivos pouco claros',1),
 ('gp_ausencia_indicadores','gestao_performance','Ausência de indicadores',2),
 ('gp_baixa_execucao','gestao_performance','Baixa execução estratégica',3),
 ('gp_resultados_inconsistentes','gestao_performance','Resultados inconsistentes',4),
 ('gp_fraca_gestao_processos','gestao_performance','Fraca gestão de processos',5),
 ('nc_vendas_baixas','negocio_comercial','Vendas abaixo do potencial',1),
 ('nc_sem_registo_leads','negocio_comercial','Sem registo nem acompanhamento de leads',2),
 ('nc_negociacao_fraca','negocio_comercial','Negociação fraca com clientes',3),
 ('nc_proposta_pouco_clara','negocio_comercial','Proposta de valor pouco clara',4),
 ('dt_baixa_literacia','digital_tecnologia','Baixa literacia digital das equipas',1),
 ('dt_processos_manuais','digital_tecnologia','Processos manuais e repetitivos',2),
 ('dt_ferramentas_subutilizadas','digital_tecnologia','Ferramentas disponíveis mal utilizadas',3),
 ('dt_resistencia_tecnologia','digital_tecnologia','Resistência à adopção de tecnologia',4),
 ('pc_rotatividade_alta','pessoas_comportamento','Rotatividade elevada',1),
 ('pc_conflitos_equipa','pessoas_comportamento','Conflitos e má comunicação na equipa',2),
 ('pc_baixa_motivacao','pessoas_comportamento','Baixa motivação e envolvimento',3),
 ('pc_falta_responsabilizacao','pessoas_comportamento','Falta de responsabilização',4);

insert into public.av_diag_solutions (code,name,default_format) values
 ('produtividade','Produtividade','Teambuilding'),
 ('resolucao_problemas','Resolução de Problemas','Teambuilding'),
 ('qualidade_trabalho','Qualidade no Trabalho','Teambuilding'),
 ('gestao_objectivos_kpis','Gestão por Objectivos e KPIs','Programa'),
 ('gestao_processos','Gestão de Processos','Programa'),
 ('lideranca_situacional','Liderança Situacional','Mentoria'),
 ('comunicacao_eficaz','Comunicação Eficaz','Workshop'),
 ('gestao_mudanca','Gestão da Mudança','Workshop'),
 ('vendas_negociacao','Vendas e Negociação','Treinamento'),
 ('crm_leads','CRM e Gestão de Leads','Treinamento'),
 ('literacia_digital','Literacia Digital','Formação'),
 ('retencao_motivacao','Retenção e Motivação de Equipas','Programa'),
 ('inteligencia_emocional','Inteligência Emocional','Workshop');

insert into public.av_diag_rules (problem_code, solution_code, weight) values
 ('lid_sem_inspirar','lideranca_situacional',1),('lid_sem_inspirar','comunicacao_eficaz',1),
 ('lid_decisoes_lentas','resolucao_problemas',1),('lid_decisoes_lentas','lideranca_situacional',1),
 ('lid_valores_nao_vividos','comunicacao_eficaz',1),('lid_valores_nao_vividos','gestao_mudanca',1),
 ('lid_resistencia_mudanca','gestao_mudanca',1),('lid_resistencia_mudanca','comunicacao_eficaz',1),
 ('gp_objectivos_pouco_claros','gestao_objectivos_kpis',1),('gp_objectivos_pouco_claros','produtividade',1),
 ('gp_ausencia_indicadores','gestao_objectivos_kpis',1),
 ('gp_baixa_execucao','produtividade',1),('gp_baixa_execucao','resolucao_problemas',1),('gp_baixa_execucao','qualidade_trabalho',1),
 ('gp_resultados_inconsistentes','qualidade_trabalho',1),('gp_resultados_inconsistentes','gestao_processos',1),
 ('gp_fraca_gestao_processos','gestao_processos',1),('gp_fraca_gestao_processos','qualidade_trabalho',1),
 ('nc_vendas_baixas','vendas_negociacao',1),('nc_vendas_baixas','crm_leads',1),
 ('nc_sem_registo_leads','crm_leads',1),
 ('nc_negociacao_fraca','vendas_negociacao',1),
 ('nc_proposta_pouco_clara','vendas_negociacao',1),('nc_proposta_pouco_clara','comunicacao_eficaz',1),
 ('dt_baixa_literacia','literacia_digital',1),
 ('dt_processos_manuais','literacia_digital',1),('dt_processos_manuais','gestao_processos',1),
 ('dt_ferramentas_subutilizadas','literacia_digital',1),('dt_ferramentas_subutilizadas','produtividade',1),
 ('dt_resistencia_tecnologia','gestao_mudanca',1),('dt_resistencia_tecnologia','literacia_digital',1),
 ('pc_rotatividade_alta','retencao_motivacao',1),('pc_rotatividade_alta','lideranca_situacional',1),
 ('pc_conflitos_equipa','inteligencia_emocional',1),('pc_conflitos_equipa','comunicacao_eficaz',1),
 ('pc_baixa_motivacao','retencao_motivacao',1),('pc_baixa_motivacao','inteligencia_emocional',1),
 ('pc_falta_responsabilizacao','lideranca_situacional',1),('pc_falta_responsabilizacao','produtividade',1);

-- 6. Funções (todas exigem administração ou formador)
create or replace function public.av_org_diag_new(p_company jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v public.av_org_diag%rowtype;
begin
  if not public.av_train_is_staff() then raise exception 'sem_permissao'; end if;
  insert into public.av_org_diag (code, consult_code, created_by)
  values ('PL-' || to_char(now(),'YYYY') || '-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,6)),
          'IL-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,6)), auth.uid())
  returning * into v;
  return jsonb_build_object('id', v.id, 'code', v.code, 'consult_code', v.consult_code);
end $$;

-- payload: {"company":{...}} (etapa 1) · {"needs":[...]} (etapa 2) · {"investment_band":"b3"} (etapa 3)
create or replace function public.av_org_diag_save(p_id uuid, p_step int, p_payload jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare c jsonb; n jsonb; v_codes text[];
begin
  if not public.av_train_is_staff() then raise exception 'sem_permissao'; end if;
  perform 1 from public.av_org_diag where id = p_id and status = 'rascunho' for update;
  if not found then raise exception 'processo_inexistente_ou_concluido'; end if;

  if p_payload ? 'company' then
    c := p_payload->'company';
    if length(trim(coalesce(c->>'company_name',''))) < 2 or length(trim(coalesce(c->>'contact_name',''))) < 2 then
      raise exception 'empresa_e_responsavel_obrigatorios';
    end if;
    update public.av_org_diag set
      company_name = trim(c->>'company_name'), sector = nullif(trim(c->>'sector'),''),
      headcount_band = nullif(trim(c->>'headcount_band'),''), contact_name = trim(c->>'contact_name'),
      contact_email = nullif(trim(c->>'contact_email'),''), contact_whatsapp = nullif(trim(c->>'contact_whatsapp'),'')
    where id = p_id;
  end if;

  if p_payload ? 'needs' then
    if jsonb_typeof(p_payload->'needs') <> 'array' or jsonb_array_length(p_payload->'needs') = 0 then
      raise exception 'indique_pelo_menos_uma_area';
    end if;
    delete from public.av_org_diag_needs where diag_id = p_id;
    for n in select * from jsonb_array_elements(p_payload->'needs') loop
      if jsonb_array_length(coalesce(n->'problems','[]')) = 0 or jsonb_array_length(coalesce(n->'publics','[]')) = 0 then
        raise exception 'cada_area_precisa_de_problemas_e_publicos';
      end if;
      insert into public.av_org_diag_needs (diag_id, area_code, problems, publics, priority, horizon)
      values (p_id, n->>'area_code',
              array(select jsonb_array_elements_text(n->'problems')),
              n->'publics', n->>'priority', n->>'horizon');
    end loop;
    -- problemas têm de pertencer à área indicada
    if exists (select 1 from public.av_org_diag_needs nd, unnest(nd.problems) pc
                where nd.diag_id = p_id
                  and not exists (select 1 from public.av_diag_problems p where p.code = pc and p.area_code = nd.area_code)) then
      raise exception 'problema_fora_da_area';
    end if;
  end if;

  if p_payload ? 'investment_band' then
    select array(select e->>'code' from public.av_diag_settings s, jsonb_array_elements(s.investment_bands) e) into v_codes;
    if not (p_payload->>'investment_band') = any (v_codes) then raise exception 'faixa_invalida'; end if;
    update public.av_org_diag set investment_band = p_payload->>'investment_band' where id = p_id;
  end if;

  update public.av_org_diag set step = greatest(step, least(p_step,4)), updated_at = now() where id = p_id;
end $$;

-- Pontuação = peso(prioridade) × peso(horizonte) × (1 + min(pessoas, cap) / cap)
create or replace function public.av_org_diag_generate(p_id uuid) returns int
language plpgsql security definer set search_path = public as $$
declare s public.av_diag_settings%rowtype; n record; total int; sc numeric; cnt int;
begin
  if not public.av_train_is_staff() then raise exception 'sem_permissao'; end if;
  perform 1 from public.av_org_diag where id = p_id and status = 'rascunho' for update;
  if not found then raise exception 'processo_inexistente_ou_concluido'; end if;
  select * into s from public.av_diag_settings where id = 1;

  create temp table _keep on commit drop as
    select area_code, public_code, solution_code from public.av_org_diag_recs where diag_id = p_id and selected;
  delete from public.av_org_diag_recs where diag_id = p_id;

  for n in select * from public.av_org_diag_needs where diag_id = p_id loop
    select coalesce(sum((e->>'people')::int),0) into total from jsonb_array_elements(n.publics) e;
    sc := round( (s.priority_weights->>n.priority)::numeric * (s.horizon_weights->>n.horizon)::numeric
                 * (1 + least(total, s.volume_cap)::numeric / s.volume_cap), 1);
    update public.av_org_diag_needs set score = sc where id = n.id;

    insert into public.av_org_diag_recs (diag_id, area_code, public_code, solution_code, level, priority, format, matches, score)
    select p_id, n.area_code, pub.code, r.solution_code,
           case pub.code when 'alta_direccao' then 'Estratégico'
                         when 'gestores' then 'Tático' when 'chefias' then 'Tático' else 'Operacional' end,
           n.priority, sol.default_format, count(*)::int, sc
      from (select e->>'public' as code from jsonb_array_elements(n.publics) e) pub
      join public.av_diag_rules r on r.problem_code = any (n.problems)
      join public.av_diag_solutions sol on sol.code = r.solution_code
     group by pub.code, r.solution_code, sol.default_format;
  end loop;

  update public.av_org_diag_recs r set selected = true
   where r.diag_id = p_id and exists (select 1 from _keep k where k.area_code = r.area_code
          and k.public_code = r.public_code and k.solution_code = r.solution_code);
  select count(*) into cnt from public.av_org_diag_recs where diag_id = p_id;
  update public.av_org_diag set updated_at = now() where id = p_id;
  return cnt;
end $$;

create or replace function public.av_org_diag_select(p_id uuid, p_rec_ids uuid[]) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.av_train_is_staff() then raise exception 'sem_permissao'; end if;
  perform 1 from public.av_org_diag where id = p_id and status = 'rascunho';
  if not found then raise exception 'processo_inexistente_ou_concluido'; end if;
  update public.av_org_diag_recs set selected = (id = any (coalesce(p_rec_ids,'{}'))) where diag_id = p_id;
end $$;

create or replace function public.av_org_diag_complete(p_id uuid, p_next_meeting date default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.av_train_is_staff() then raise exception 'sem_permissao'; end if;
  if not exists (select 1 from public.av_org_diag_recs where diag_id = p_id and selected) then
    raise exception 'seleccione_pelo_menos_uma_recomendacao';
  end if;
  update public.av_org_diag set status = 'concluido', step = 4, next_meeting = p_next_meeting,
         completed_at = now(), updated_at = now() where id = p_id and status = 'rascunho';
end $$;

create or replace function public.av_org_diag_get(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.av_train_is_staff() then raise exception 'sem_permissao'; end if;
  return (select jsonb_build_object(
    'diag', to_jsonb(d),
    'needs', coalesce((select jsonb_agg(to_jsonb(n) order by n.score desc nulls last) from public.av_org_diag_needs n where n.diag_id = d.id), '[]'),
    'recs',  coalesce((select jsonb_agg(to_jsonb(r) || jsonb_build_object('solution', s.name, 'family', s.family) order by r.score desc, r.matches desc)
                       from public.av_org_diag_recs r join public.av_diag_solutions s on s.code = r.solution_code where r.diag_id = d.id), '[]'))
    from public.av_org_diag d where d.id = p_id);
end $$;

revoke all on function public.av_org_diag_new(jsonb), public.av_org_diag_save(uuid,int,jsonb),
  public.av_org_diag_generate(uuid), public.av_org_diag_select(uuid,uuid[]),
  public.av_org_diag_complete(uuid,date), public.av_org_diag_get(uuid) from public, anon;
grant execute on function public.av_org_diag_new(jsonb), public.av_org_diag_save(uuid,int,jsonb),
  public.av_org_diag_generate(uuid), public.av_org_diag_select(uuid,uuid[]),
  public.av_org_diag_complete(uuid,date), public.av_org_diag_get(uuid) to authenticated;

commit;
