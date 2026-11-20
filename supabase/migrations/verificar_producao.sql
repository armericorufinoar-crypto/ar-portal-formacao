-- verificar_producao.sql · SÓ LEITURA (select). Corra no SQL Editor do Supabase de PRODUÇÃO.
-- Mostra o que falta e o estado das funções de teste, para decidir antes de montar o ambiente de teste.

-- 1) Objectos que o index.html usa e que não têm ficheiro no zip: existem em produção?
with esperado(nome, tipo) as (values
  ('av_test_starts','tabela'),('av_competency_diagnostics','tabela'),
  ('av_feedback_reactions','tabela'),('av_feedback_replies','tabela'),
  ('av_start_test','função'),('av_abandon_test','função'),
  ('av_reset_test_start','função'),('av_get_competency_diagnosis','função'))
select e.nome, e.tipo,
       case e.tipo
         when 'tabela' then exists (select 1 from information_schema.tables t
                                    where t.table_schema='public' and t.table_name=e.nome)
         else exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                      where n.nspname='public' and p.proname=e.nome)
       end as existe
from esperado e order by e.tipo, e.nome;

-- 2) Funções de teste: qual versão está activa?
--    confere_area  = true  -> ainda tem a verificação de áreas da 007
--    nota_2_casas  = true  -> nota com 2 decimais (015_perguntas_autodeclaradas), em vez de inteira (006)
select p.proname,
       pg_get_functiondef(p.oid) ilike '%st.areas%' as confere_area,
       pg_get_functiondef(p.oid) ~* 'round\([^)]*,\s*2\)' as nota_2_casas,
       pg_get_functiondef(p.oid) ilike '%test_purpose%' as conhece_diagnostico
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in ('av_get_test','av_submit_test')
order by p.proname;

-- 3) Colunas recentes
select table_name, column_name from information_schema.columns
where table_schema='public'
  and ((table_name='av_session_materials' and column_name in ('stage','test_purpose'))
    or (table_name='av_crm_deals' and column_name in ('next_step','next_contact_date','last_contact','lost_reason','cohort','profession'))
    or (table_name='av_competencies' and column_name='levels'))
order by table_name, column_name;
