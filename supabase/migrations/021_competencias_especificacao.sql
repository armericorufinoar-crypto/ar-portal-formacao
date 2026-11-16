-- 021_competencias_especificacao.sql
-- Acrescenta 14 competências alinhadas com os temas dos 4 percursos da especificação.
-- Não altera nem apaga as 8 competências que já existem (FIN-01..03, MKT-01, VND-01..02, CRM-01, CRES-01).
-- Repetível: só insere o código que ainda não existe.
-- levels usa os códigos de nível do portal: estudante, empreendedor, empreendedor_plus, empresario.

insert into public.av_competencies (code, theme, name, evidence, reinforcement, position, active, levels)
select v.code, v.theme, v.name, v.evidence, v.reinforcement, v.position, true, v.levels
from (values
 ('EMP-01','Empreendedorismo e Modelo de Negócio','Habilidade e canais de rendimento',
  'Identifica a sua habilidade e compara os canais de saída: emprego, negócio, formações e livros.',
  'Rever os quatro canais de rendimento e escolher um para testar nas próximas duas semanas.',101,'{estudante}'::text[]),
 ('EMP-02','Empreendedorismo e Modelo de Negócio','Plano de negócio e Business Model Canvas',
  'Descreve o problema, a solução e o desejo de compra do cliente, e preenche o Business Model Canvas.',
  'Escrever o problema e a solução do negócio em duas frases e confirmar com um cliente real.',102,'{estudante}'::text[]),
 ('EMP-03','Empreendedorismo e Modelo de Negócio','Capital inicial, empréstimos e sociedades',
  'Sabe de onde pode vir o dinheiro para começar, os critérios dos empréstimos e os critérios para constituir uma sociedade.',
  'Listar as fontes de capital possíveis e os critérios de cada uma antes de decidir.',103,'{estudante}'::text[]),
 ('FIN-04','Gestão Financeira e Tesouraria','Precificação e margem',
  'Calcula o preço com markup, a margem e o lucro de uma venda.',
  'Refazer o cálculo do preço de um produto próprio, com custos e margem desejada.',104,'{estudante,empreendedor}'::text[]),
 ('FIN-05','Gestão Financeira e Tesouraria','Separação de contas e controlo financeiro',
  'Separa o dinheiro pessoal do do negócio e regista o que entra e o que sai.',
  'Registar durante uma semana todas as entradas e saídas, numa folha ou caderno único.',105,'{empreendedor}'::text[]),
 ('FIN-06','Gestão Financeira e Tesouraria','Fluxo de caixa, investimento e reservas',
  'Distingue gasto de investimento, planeia o fluxo de caixa e constrói uma reserva de emergência.',
  'Definir uma reserva mínima e separar todos os meses um valor fixo para ela.',106,'{empreendedor,empreendedor_plus}'::text[]),
 ('FIN-07','Gestão Financeira e Tesouraria','Orçamento simples e empresarial',
  'Constrói um orçamento com receitas e despesas previstas e compara-o com o realizado.',
  'Montar o orçamento do próximo trimestre e rever os desvios todos os meses.',107,'{empreendedor_plus,empresario}'::text[]),
 ('MKT-02','Marketing, Prospecção e CRM','Prospecção e registo de potenciais clientes',
  'Prospecta com marketing e regista cada potencial cliente (leads) com contacto e data de seguimento.',
  'Registar três contactos novos por semana e marcar a data do próximo contacto.',108,'{empreendedor,empreendedor_plus}'::text[]),
 ('VND-03','Marketing, Prospecção e CRM','Negociação de venda',
  'Negoceia como vendedor e como comprador, e conduz a conversa até um acordo com próximo passo marcado.',
  'Ensaiar uma negociação por semana com um colega, trocando os papéis de comprador e vendedor.',109,'{estudante,empreendedor}'::text[]),
 ('CRM-02','Marketing, Prospecção e CRM','CRM e acompanhamento de leads',
  'Acompanha cada lead no CRM, do primeiro contacto até à venda, sem perder oportunidades.',
  'Rever todos os leads parados há mais de 7 dias e decidir o próximo passo de cada um.',110,'{empreendedor_plus}'::text[]),
 ('EQP-01','Gestão de Equipas, Processos e KPIs','Delegação, processos e KPIs da equipa',
  'Delega tarefas com responsável e prazo, documenta os primeiros processos e acompanha indicadores da equipa.',
  'Escolher uma tarefa para delegar esta semana e definir como o resultado será medido.',111,'{empreendedor_plus,empresario}'::text[]),
 ('EQP-02','Gestão de Equipas, Processos e KPIs','Departamentos e sistemas de gestão',
  'Organiza o funcionamento dos departamentos e usa sistemas e KPIs que servem a decisão.',
  'Mapear as responsabilidades de cada departamento e escolher três KPIs para acompanhar.',112,'{empresario}'::text[]),
 ('EST-01','Gestão Estratégica e Liderança','Planeamento estratégico',
  'Liga o orçamento empresarial a objectivos estratégicos, com metas e prazos.',
  'Escrever três objectivos do ano com meta, prazo e responsável.',113,'{empresario}'::text[]),
 ('EST-02','Gestão Estratégica e Liderança','Marca, vendas, liderança e comunicação',
  'Constrói a marca, melhora as vendas e comunica com a equipa com clareza e liderança.',
  'Escolher uma conversa de liderança difícil e prepará-la com objectivo e próximo passo.',114,'{empresario}'::text[])
) as v(code, theme, name, evidence, reinforcement, position, levels)
where not exists (select 1 from public.av_competencies c where c.code = v.code);

-- Verificação (deve devolver 22 linhas: 8 antigas + 14 novas):
-- select code, theme, name, levels, active from public.av_competencies order by position, code;
