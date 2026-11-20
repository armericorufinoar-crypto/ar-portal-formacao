-- Fase 2: matriz pedagógica de competências para diagnóstico.
-- Aditiva e idempotente. Não altera perguntas, tentativas, notas ou regras de submissão.
-- A ponderação da pauta mantém-se em 60% testes / 40% avaliações práticas.

begin;

create table if not exists public.av_competencies (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (char_length(btrim(code)) between 3 and 24),
  theme text not null check (char_length(btrim(theme)) between 2 and 120),
  name text not null check (char_length(btrim(name)) between 2 and 160),
  evidence text not null default '',
  reinforcement text not null default '',
  active boolean not null default true,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.av_test_questions
  add column if not exists competency_id uuid
  references public.av_competencies(id) on delete set null;

create index if not exists av_test_questions_competency_idx
  on public.av_test_questions (competency_id);

alter table public.av_competencies enable row level security;

revoke all on table public.av_competencies from public, anon, authenticated;
grant select, insert, update, delete on table public.av_competencies to authenticated;

drop policy if exists av_competencies_select_team on public.av_competencies;
create policy av_competencies_select_team
  on public.av_competencies for select to authenticated
  using (public.av_test_is_team());

drop policy if exists av_competencies_insert_team on public.av_competencies;
create policy av_competencies_insert_team
  on public.av_competencies for insert to authenticated
  with check (public.av_test_is_team());

drop policy if exists av_competencies_update_team on public.av_competencies;
create policy av_competencies_update_team
  on public.av_competencies for update to authenticated
  using (public.av_test_is_team())
  with check (public.av_test_is_team());

drop policy if exists av_competencies_delete_team on public.av_competencies;
create policy av_competencies_delete_team
  on public.av_competencies for delete to authenticated
  using (public.av_test_is_team());

insert into public.av_competencies
  (code, theme, name, evidence, reinforcement, position)
values
  ('FIN-01', 'Finanças pessoais', 'Mentalidade financeira',
   'Distingue mentalidade de escassez de criação de valor e mentalidade de entrada.',
   'Rever o exercício de mentalidade financeira e explicar a diferença através de um exemplo próprio.', 10),
  ('FIN-02', 'Finanças pessoais', 'Planeamento financeiro',
   'Aplica o plano 70/20/10 a um cenário simples e interpreta cada parcela.',
   'Refazer o exercício do plano 70/20/10 e justificar a distribuição.', 20),
  ('FIN-03', 'Finanças pessoais', 'Protecção financeira',
   'Calcula uma meta de reserva e distingue poupança de protecção contra imprevistos.',
   'Rever o exercício de reserva e identificar um passo concreto para criar ou reforçar a reserva.', 30),
  ('MKT-01', 'Marketing e posicionamento', 'Marketing e marca',
   'Distingue marketing directo de construção de marca e posicionamento.',
   'Comparar dois exemplos de comunicação e identificar o objectivo de cada um.', 40),
  ('VND-01', 'Vendas e negociação', 'Comunicação comercial',
   'Estrutura uma mensagem com gancho, prova, preço e chamada para acção.',
   'Reescrever uma oferta usando os quatro elementos e testar a mensagem em role-play.', 50),
  ('VND-02', 'Vendas e negociação', 'Negociação de objecções',
   'Escuta, reconhece a objecção, responde e confirma o próximo passo; evita concessões sem contrapartida.',
   'Repetir o role-play de objecção e registar a contrapartida negociada.', 60),
  ('CRM-01', 'CRM e gestão comercial', 'Organização comercial',
   'Identifica etapas do funil, qualifica contactos e acompanha propostas, ganhos, perdas e pós-venda.',
   'Reconstituir o percurso de um contacto no funil e indicar a próxima acção.', 70),
  ('CRES-01', 'Crescimento e Pareto', 'Prioridades de crescimento',
   'Analisa novos clientes, ticket médio e recorrência e identifica a variável com maior impacto.',
   'Refazer o exercício de crescimento e justificar a prioridade escolhida.', 80)
on conflict (code) do update set
  theme = excluded.theme,
  name = excluded.name,
  evidence = excluded.evidence,
  reinforcement = excluded.reinforcement,
  position = excluded.position,
  updated_at = now();

commit;
