-- 011_renomear_areas.sql
-- Renomeia as áreas formativas:
--   'Finanças'            -> 'Finanças e Investimentos'
--   'Gestão Estratégica'  -> 'Negócios'
-- Áreas finais: Finanças e Investimentos, Marketing e Vendas, Negócios, Oratória, Liderança.
-- Numa instalação nova NÃO é necessária (a 001 já traz os nomes novos).
-- É seguro correr mais do que uma vez.

do $$
declare
  r record;
begin
  -- 1) Largar as restrições de área antigas.
  for r in
    select c.conrelid::regclass as tbl, c.conname
      from pg_constraint c
     where c.contype = 'c'
       and c.conrelid in ('public.av_sessions'::regclass, 'public.av_forum_posts'::regclass)
       and pg_get_constraintdef(c.oid) like '%area%'
  loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
  end loop;
end $$;

-- 2) Actualizar os dados existentes.
update public.av_sessions    set area = 'Finanças e Investimentos' where area = 'Finanças';
update public.av_sessions    set area = 'Negócios'                 where area = 'Gestão Estratégica';
update public.av_forum_posts set area = 'Finanças e Investimentos' where area = 'Finanças';
update public.av_forum_posts set area = 'Negócios'                 where area = 'Gestão Estratégica';

update public.av_staff
   set areas = array(
     select case a when 'Finanças' then 'Finanças e Investimentos'
                   when 'Gestão Estratégica' then 'Negócios'
                   else a end
       from unnest(areas) with ordinality as t(a, ord)
      order by ord)
 where areas && array['Finanças','Gestão Estratégica'];

-- Tabela de pagamentos/planos (010), se existir.
do $$
declare t regclass;
begin
  for t in
    select c.conrelid::regclass
      from pg_constraint c
     where c.contype = 'c'
       and c.conrelid::regclass::text like 'public.%'
       and pg_get_constraintdef(c.oid) like '%Gestão Estratégica%'
  loop
    execute format('alter table %s drop constraint %I', t,
      (select conname from pg_constraint c where c.conrelid = t and c.contype='c' and pg_get_constraintdef(c.oid) like '%Gestão Estratégica%' limit 1));
    execute format('update %s set area = ''Finanças e Investimentos'' where area = ''Finanças''', t);
    execute format('update %s set area = ''Negócios'' where area = ''Gestão Estratégica''', t);
    execute format('alter table %s add constraint %I check (area is null or area in (''Finanças e Investimentos'',''Marketing e Vendas'',''Negócios'',''Oratória'',''Liderança''))', t, replace(t::text,'public.','')||'_area_check');
  end loop;
end $$;

-- 3) Novas restrições.
alter table public.av_sessions
  add constraint av_sessions_area_check
  check (area in ('Finanças e Investimentos','Marketing e Vendas','Negócios','Oratória','Liderança'));

alter table public.av_forum_posts
  add constraint av_forum_posts_area_check
  check (area is null or area in ('Finanças e Investimentos','Marketing e Vendas','Negócios','Oratória','Liderança'));
