-- Conversão das áreas formativas (executar uma vez no SQL Editor do Supabase)
-- Finanças e Investimentos            -> Gestão Financeira e Tesouraria
-- Marketing e Vendas                  -> Marketing, Prospecção e CRM
-- Negócios                            -> Empreendedorismo e Modelo de Negócio
-- Oratória e Liderança                -> Gestão Estratégica e Liderança
-- Gestão de Equipas, Processos e KPIs -> área nova (sem origem)
-- Versão 2: as tabelas têm restrições CHECK com os nomes antigos (ex.: av_sessions_area_check);
-- o script retira-as, converte os dados e volta a criá-las com a lista nova.

begin;

-- 1) Guardar e retirar as restrições CHECK que referem as áreas antigas
create temp table _area_checks on commit drop as
select c.conrelid::regclass::text as tbl, c.conname,
       (pg_get_constraintdef(c.oid) ~ '\mareas\M') as is_array
from pg_constraint c
where c.contype = 'c'
  and c.conrelid::regclass::text in ('av_staff','av_sessions','av_fee_plans','av_train_questions')
  and (pg_get_constraintdef(c.oid) like '%Finanças e Investimentos%'
    or pg_get_constraintdef(c.oid) like '%Marketing e Vendas%'
    or pg_get_constraintdef(c.oid) like '%Oratória%');

do $$
declare r record;
begin
  for r in select * from _area_checks loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
  end loop;
end $$;

-- 2) Fichas dos formandos (array de áreas; quem tinha Oratória e Liderança fica só com uma)
update av_staff s
set areas = (
  select coalesce(array_agg(distinct m.nova), '{}')
  from unnest(s.areas) as a(v)
  cross join lateral (select case a.v
    when 'Finanças e Investimentos' then 'Gestão Financeira e Tesouraria'
    when 'Marketing e Vendas'       then 'Marketing, Prospecção e CRM'
    when 'Negócios'                 then 'Empreendedorismo e Modelo de Negócio'
    when 'Oratória'                 then 'Gestão Estratégica e Liderança'
    when 'Liderança'                then 'Gestão Estratégica e Liderança'
    else a.v end as nova) m
)
where s.areas && array['Finanças e Investimentos','Marketing e Vendas','Negócios','Oratória','Liderança'];

-- 3) Sessões, planos de pagamento e perguntas de treino (campo de texto simples)
do $$
declare t text;
begin
  foreach t in array array['av_sessions','av_fee_plans','av_train_questions'] loop
    if to_regclass(t) is not null then
      execute format($f$update %I set area = case area
        when 'Finanças e Investimentos' then 'Gestão Financeira e Tesouraria'
        when 'Marketing e Vendas'       then 'Marketing, Prospecção e CRM'
        when 'Negócios'                 then 'Empreendedorismo e Modelo de Negócio'
        when 'Oratória'                 then 'Gestão Estratégica e Liderança'
        when 'Liderança'                then 'Gestão Estratégica e Liderança'
        else area end
        where area in ('Finanças e Investimentos','Marketing e Vendas','Negócios','Oratória','Liderança')$f$, t);
    end if;
  end loop;
end $$;

-- 4) Recriar as restrições com a lista nova de áreas
do $$
declare r record;
  lista constant text := $l$'Gestão Financeira e Tesouraria','Marketing, Prospecção e CRM','Empreendedorismo e Modelo de Negócio','Gestão Estratégica e Liderança','Gestão de Equipas, Processos e KPIs'$l$;
begin
  for r in select * from _area_checks loop
    if r.is_array then
      execute format('alter table %s add constraint %I check (areas <@ array[%s]::text[])', r.tbl, r.conname, lista);
    else
      execute format('alter table %s add constraint %I check (area is null or area in (%s))', r.tbl, r.conname, lista);
    end if;
  end loop;
end $$;

commit;
