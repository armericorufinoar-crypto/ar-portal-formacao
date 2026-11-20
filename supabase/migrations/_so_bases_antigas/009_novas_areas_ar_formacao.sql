-- 009_novas_areas_ar_formacao.sql
-- Para uma base de dados que JÁ tem as tabelas criadas com as áreas antigas
-- (Comercial, Marketing, RH, Transporte, Liderança).
-- Passa a aceitar: Finanças e Investimentos, Marketing e Vendas, Negócios, Oratória, Liderança.
-- Numa instalação nova NÃO é necessária: a 001 já traz as áreas novas.
-- É seguro correr mais do que uma vez.

do $$
declare
  novas text[] := array['Finanças e Investimentos','Marketing e Vendas','Negócios','Oratória','Liderança'];
  r record;
  n int;
begin
  -- 1) Parar se existirem registos com áreas que já não existem (remapear à mão primeiro).
  select count(*) into n from public.av_sessions where area <> all (novas);
  if n > 0 then
    raise exception 'av_sessions tem % sessão(ões) com área antiga. Remapeie primeiro, ex.: update public.av_sessions set area = ''Marketing e Vendas'' where area in (''Comercial'',''Marketing'');', n;
  end if;
  select count(*) into n from public.av_forum_posts where area is not null and area <> all (novas);
  if n > 0 then
    raise exception 'av_forum_posts tem % publicação(ões) com área antiga. Remapeie ou ponha a NULL: update public.av_forum_posts set area = null where area not in (''Finanças e Investimentos'',''Marketing e Vendas'',''Negócios'',''Oratória'',''Liderança'');', n;
  end if;
  select count(*) into n from public.av_staff s where exists (select 1 from unnest(s.areas) a where a <> all (novas));
  if n > 0 then
    raise exception 'av_staff tem % formando(es) com áreas antigas em "areas". Actualize a lista de áreas de cada ficha primeiro.', n;
  end if;

  -- 2) Trocar as restrições de área.
  for r in
    select c.conrelid::regclass as tbl, c.conname
      from pg_constraint c
     where c.contype = 'c'
       and c.conrelid in ('public.av_sessions'::regclass, 'public.av_forum_posts'::regclass)
       and pg_get_constraintdef(c.oid) like '%area%'
       and pg_get_constraintdef(c.oid) like '%Transporte%'
  loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
  end loop;
end $$;

alter table public.av_sessions drop constraint if exists av_sessions_area_check;
alter table public.av_sessions
  add constraint av_sessions_area_check
  check (area in ('Finanças e Investimentos','Marketing e Vendas','Negócios','Oratória','Liderança'));

alter table public.av_forum_posts drop constraint if exists av_forum_posts_area_check;
alter table public.av_forum_posts
  add constraint av_forum_posts_area_check
  check (area is null or area in ('Finanças e Investimentos','Marketing e Vendas','Negócios','Oratória','Liderança'));
