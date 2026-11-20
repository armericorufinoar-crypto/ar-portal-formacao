-- m225 · Testes: voltar a conferir a área do formando, aceitando sessões sem área (diagnóstico inicial).
-- Contexto: a m210 (015_perguntas_autodeclaradas) redefiniu av_get_test e av_submit_test sem a verificação
-- de áreas da m100 (007). Confirmado em produção: confere_area = false nas duas funções.
--
-- Como funciona: lê a definição ACTUAL de cada função no servidor (pg_get_functiondef) e acrescenta,
-- logo depois de «Teste não encontrado», a verificação abaixo. Tudo o resto fica exactamente como está
-- (nota, diagnóstico, rascunho…). Idempotente: se a função já tiver «Sem acesso a este teste», não mexe.
--
--   a sessão do material tem área nula (diagnóstico)  OU  a área está nas áreas do formando.
--
-- Não altera a nota de 2 casas decimais da av_submit_test (decisão à parte).
-- Reverter: voltar a executar m210 (av_submit_test e av_get_test) e m220 (av_get_test).
begin;

do $$
declare
  fn  text;
  def text;
  novo text;
  chk constant text :=
    E'\n  if not exists (select 1 from public.av_sessions s join public.av_staff st on st.id = v_staff '
    'where s.id = m.session_id and (s.area is null or s.area = any (st.areas))) then '
    'raise exception ''Sem acesso a este teste.''; end if;';
begin
  foreach fn in array array['av_get_test','av_submit_test'] loop
    select pg_get_functiondef(p.oid) into def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = fn
     order by p.oid limit 1;

    if def is null then
      raise exception 'Função % não encontrada.', fn;
    elsif def like '%Sem acesso a este teste%' then
      raise notice '% já confere a área; nada a fazer.', fn;
    elsif def not like '%raise exception ''Teste não encontrado.''; end if;%' then
      raise exception 'Definição inesperada em %: não encontrei o ponto de inserção. Nada foi alterado.', fn;
    else
      novo := regexp_replace(def,
                '(raise exception ''Teste não encontrado\.''; end if;)',
                '\1' || chk);
      if novo = def then
        raise exception 'A substituição não alterou % . Nada foi alterado.', fn;
      end if;
      execute novo;
      raise notice '% actualizada.', fn;
    end if;
  end loop;
end $$;

commit;

-- Confirmação: confere_area deve ficar true nas duas.
select p.proname,
       pg_get_functiondef(p.oid) ilike '%st.areas%' as confere_area,
       pg_get_functiondef(p.oid) ilike '%s.area is null%' as aceita_sem_area
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('av_get_test','av_submit_test')
order by p.proname;
