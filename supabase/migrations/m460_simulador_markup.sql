-- ============================================================================
-- AV Formação · Fase 1 · Simulador de Markup
-- Correr UMA vez no SQL Editor do Supabase (é seguro repetir: usa IF NOT EXISTS
-- e ON CONFLICT). Não toca em av_crm_deals nem em nenhuma tabela existente.
-- Papéis em av_profiles: 'admin', 'trainer' (equipa) e 'collaborator' (formando).
-- ============================================================================

-- 0. Auxiliar: é da equipa (administrador ou formador)?
create or replace function public.av_sim_is_staff()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.av_profiles p
    where p.user_id = auth.uid() and p.role in ('admin','trainer')
  );
$$;
revoke all on function public.av_sim_is_staff() from public;
grant execute on function public.av_sim_is_staff() to authenticated;

-- 1. Exercícios (enunciados visíveis aos formandos; SEM solução)
create table if not exists public.av_sim_exercises (
  id          uuid primary key default gen_random_uuid(),
  code        text unique not null,
  kind        text not null default 'markup',
  level       int  not null check (level between 1 and 3),
  position    int  not null default 0,
  title       text not null,
  statement   text not null,
  unit        text not null default 'Kz',      -- 'Kz', '%' ou 'un'
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- 2. Soluções (só a equipa lê; o formando nunca vê esta tabela)
create table if not exists public.av_sim_solutions (
  exercise_id uuid primary key references public.av_sim_exercises(id) on delete cascade,
  answer      numeric not null,
  tolerance   numeric not null default 0,
  explanation text    not null,                -- método completo, mostrado ao acertar ou após 3 tentativas
  wrong_hint  text                              -- pista curta, mostrada ao errar
);

-- 3. Tentativas (escritas só pela função av_sim_check)
create table if not exists public.av_sim_attempts (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid(),
  exercise_id uuid not null references public.av_sim_exercises(id) on delete cascade,
  answer      numeric not null,
  correct     boolean not null,
  created_at  timestamptz not null default now()
);
create index if not exists av_sim_attempts_user_idx on public.av_sim_attempts(user_id, exercise_id);

-- 4. Fichas de preço guardadas pelo formando
create table if not exists public.av_sim_pricing (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid(),
  name       text not null,
  data       jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists av_sim_pricing_user_idx on public.av_sim_pricing(user_id);

-- 5. RLS
alter table public.av_sim_exercises  enable row level security;
alter table public.av_sim_solutions  enable row level security;
alter table public.av_sim_attempts   enable row level security;
alter table public.av_sim_pricing    enable row level security;

drop policy if exists sim_ex_read   on public.av_sim_exercises;
drop policy if exists sim_ex_staff  on public.av_sim_exercises;
create policy sim_ex_read  on public.av_sim_exercises for select to authenticated using (active or public.av_sim_is_staff());
create policy sim_ex_staff on public.av_sim_exercises for all    to authenticated using (public.av_sim_is_staff()) with check (public.av_sim_is_staff());

drop policy if exists sim_sol_staff on public.av_sim_solutions;
create policy sim_sol_staff on public.av_sim_solutions for all to authenticated using (public.av_sim_is_staff()) with check (public.av_sim_is_staff());

drop policy if exists sim_att_read on public.av_sim_attempts;
create policy sim_att_read on public.av_sim_attempts for select to authenticated using (user_id = auth.uid() or public.av_sim_is_staff());
-- (sem política de insert/update/delete: só a função av_sim_check escreve)

drop policy if exists sim_pr_own   on public.av_sim_pricing;
drop policy if exists sim_pr_staff on public.av_sim_pricing;
create policy sim_pr_own   on public.av_sim_pricing for all    to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy sim_pr_staff on public.av_sim_pricing for select to authenticated using (public.av_sim_is_staff());

revoke all on public.av_sim_exercises, public.av_sim_solutions, public.av_sim_attempts, public.av_sim_pricing from anon;
grant select on public.av_sim_exercises to authenticated;
grant select on public.av_sim_attempts  to authenticated;
grant select, insert, update, delete on public.av_sim_pricing to authenticated;

-- 6. Correcção no servidor
create or replace function public.av_sim_check(p_exercise uuid, p_answer numeric)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  s record;
  ok boolean;
  n  int;
begin
  if auth.uid() is null then
    raise exception 'Sessão inválida';
  end if;
  select * into s from public.av_sim_solutions where exercise_id = p_exercise;
  if not found then
    raise exception 'Exercício sem solução registada';
  end if;
  ok := abs(p_answer - s.answer) <= s.tolerance;
  insert into public.av_sim_attempts(user_id, exercise_id, answer, correct)
  values (auth.uid(), p_exercise, p_answer, ok);
  select count(*) into n from public.av_sim_attempts
   where user_id = auth.uid() and exercise_id = p_exercise;
  return jsonb_build_object(
    'correct',     ok,
    'attempts',    n,
    'hint',        case when ok then null else s.wrong_hint end,
    'explanation', case when ok or n >= 3 then s.explanation end,
    'expected',    case when ok or n >= 3 then s.answer end
  );
end;
$$;
revoke all on function public.av_sim_check(uuid, numeric) from public;
grant execute on function public.av_sim_check(uuid, numeric) to authenticated;

-- 7. Os 12 exercícios iniciais (RASCUNHO para o formador validar e alterar)
insert into public.av_sim_exercises(code, level, position, title, statement, unit) values
('MK-01',1, 1,'Do custo ao preço',
 'Uma loja compra um telemóvel por 60.000 Kz e aplica um markup de 40% sobre o custo. Qual é o preço de venda?','Kz'),
('MK-02',1, 2,'Markup e margem',
 'Um produto tem markup de 50% sobre o custo. Qual é a margem sobre o preço de venda? (em %, com uma casa decimal)','%'),
('MK-03',1, 3,'Margem de um produto vendido',
 'Um produto custa 9.000 Kz e vende-se a 12.000 Kz. Qual é a margem sobre o preço? (em %)','%'),
('MK-04',1, 4,'Preço para uma margem',
 'Quer uma margem de 20% sobre o preço de venda. O custo do produto é 8.000 Kz. Qual deve ser o preço?','Kz'),
('MK-05',2, 5,'Padaria: custo total do pão',
 'Uma padaria gasta 45 Kz em farinha, fermento e gás por cada pão. Os custos fixos são 180.000 Kz por mês (renda, salários, electricidade) e vende 6.000 pães por mês. Qual é o custo total de cada pão?','Kz'),
('MK-06',2, 6,'Salão: preço do serviço',
 'Um serviço de salão custa 3.500 Kz em materiais e mão-de-obra directa. A dona quer um markup de 120% sobre esse custo. Qual é o preço do serviço?','Kz'),
('MK-07',2, 7,'Revenda de roupa com comissão',
 'Compra roupa a 15.000 Kz por peça. Paga ao vendedor uma comissão de 10% do preço de venda e quer uma margem de 25% sobre o preço. Qual deve ser o preço de venda? (arredonde ao Kz)','Kz'),
('MK-08',2, 8,'Restaurante: markup do prato',
 'Um prato custa 2.800 Kz a fazer e vende-se a 6.500 Kz. Qual é o markup sobre o custo? (em %, com uma casa decimal)','%'),
('MK-09',2, 9,'Ponto de equilíbrio',
 'Os custos fixos são 240.000 Kz por mês. Cada unidade vende-se a 4.000 Kz e o custo variável é 2.500 Kz. Quantas unidades por mês são precisas para cobrir os custos fixos?','un'),
('MK-10',3,10,'O desconto de 10%',
 'Um produto vende-se a 10.000 Kz e custa 6.000 Kz. Hoje vendem-se 200 unidades por mês (contribuição de 800.000 Kz). Com um desconto de 10%, quantas unidades por mês são precisas para manter a mesma contribuição? (arredonde para cima)','un'),
('MK-11',3,11,'Preço da turma',
 'Uma turma custa 97.500 Kz a dar (25 h × 3.500 Kz + 10.000 Kz de custos directos). Com 8 formandos, que preço por formando dá uma margem de 55% sobre a receita? (arredonde ao Kz)','Kz'),
('MK-12',3,12,'Impostos, comissão e margem',
 'Um produto custa 20.000 Kz. Os impostos e taxas são 6% do preço e a comissão de vendas é 8% do preço. Quer 30% de margem sobre o preço. Qual deve ser o preço? (arredonde ao Kz)','Kz')
on conflict (code) do update set
  level = excluded.level, position = excluded.position, title = excluded.title,
  statement = excluded.statement, unit = excluded.unit;

insert into public.av_sim_solutions(exercise_id, answer, tolerance, explanation, wrong_hint)
select e.id, v.answer, v.tol, v.expl, v.hint
from (values
 ('MK-01', 84000,    0,   'Preço = custo × (1 + markup) = 60.000 × 1,40 = 84.000 Kz.',
                          'O markup incide sobre o custo: multiplique o custo por 1 mais o markup.'),
 ('MK-02', 33.3,      0.1, 'Com custo 100 e markup 50%, o preço é 150. A margem é (150 − 100) / 150 = 33,3%. Fórmula: margem = markup / (1 + markup).',
                          'Calcule um exemplo: custo 100, preço 150. A margem divide o lucro pelo preço, não pelo custo.'),
 ('MK-03', 25,        0.1, 'Lucro = 12.000 − 9.000 = 3.000 Kz. Margem = 3.000 / 12.000 = 25%. (33,3% seria o markup, sobre o custo.)',
                          'Divida o lucro pelo preço de venda, não pelo custo.'),
 ('MK-04', 10000,     1,   'Preço = custo / (1 − margem) = 8.000 / 0,80 = 10.000 Kz. Multiplicar por 1,20 daria 9.600 Kz, que é uma margem de só 16,7%.',
                          'A margem é sobre o preço: o custo representa 80% do preço.'),
 ('MK-05', 75,        0.5, 'Custos fixos por pão = 180.000 / 6.000 = 30 Kz. Custo total = 45 + 30 = 75 Kz.',
                          'Distribua os custos fixos pelos 6.000 pães e some o custo variável.'),
 ('MK-06', 7700,      1,   'Preço = 3.500 × (1 + 1,20) = 3.500 × 2,20 = 7.700 Kz.',
                          'Markup de 120% quer dizer multiplicar o custo por 2,20.'),
 ('MK-07', 23077,     5,   'Custo + comissão + margem = 100% do preço. O custo é 100% − 10% − 25% = 65% do preço. Preço = 15.000 / 0,65 ≈ 23.077 Kz.',
                          'Comissão e margem são percentagens do preço: o custo fica com o que sobra de 100%.'),
 ('MK-08', 132.1,     0.1, 'Lucro = 6.500 − 2.800 = 3.700 Kz. Markup = 3.700 / 2.800 = 132,1% (a margem seria 56,9%).',
                          'O markup divide o lucro pelo custo.'),
 ('MK-09', 160,       0.5, 'Contribuição por unidade = 4.000 − 2.500 = 1.500 Kz. Equilíbrio = 240.000 / 1.500 = 160 unidades.',
                          'Cada unidade contribui com o preço menos o custo variável para pagar os custos fixos.'),
 ('MK-10', 267,       0.5, 'Novo preço 9.000 Kz; contribuição por unidade = 9.000 − 6.000 = 3.000 Kz (antes 4.000). Unidades = 800.000 / 3.000 = 266,7, ou seja 267. Um desconto de 10% obriga a vender 33% mais.',
                          'Calcule a nova contribuição por unidade e divida os 800.000 Kz por ela.'),
 ('MK-11', 27083,     5,   'Receita necessária = custo / (1 − margem) = 97.500 / 0,45 ≈ 216.667 Kz. Por formando: 216.667 / 8 ≈ 27.083 Kz.',
                          'O custo é 45% da receita (100% − 55%). Depois divida pelos 8 formandos.'),
 ('MK-12', 35714,     5,   'Impostos + comissão + margem = 44% do preço, e o custo fica com 56%. Preço = 20.000 / 0,56 ≈ 35.714 Kz.',
                          'Some as três percentagens do preço; o custo é o que sobra de 100%.')
) as v(code, answer, tol, expl, hint)
join public.av_sim_exercises e on e.code = v.code
on conflict (exercise_id) do update set
  answer = excluded.answer, tolerance = excluded.tolerance,
  explanation = excluded.explanation, wrong_hint = excluded.wrong_hint;
