-- Diagnóstico inicial como ficha própria: sem área, sem formador (executar uma vez no SQL Editor do Supabase)

alter table av_sessions alter column area drop not null;
alter table av_sessions alter column trainer_name drop not null;

-- Os formandos precisam de ler as sessões e os materiais sem área (o diagnóstico é para todos).
-- Cada bloco é independente: se um falhar, aparece só um aviso e os outros continuam.
do $$
begin
  begin
    execute $p$create policy av_sessions_sem_area_leitura on av_sessions
      for select to authenticated using (area is null)$p$;
  exception when duplicate_object then null;
            when others then raise notice 'av_sessions: %', sqlerrm;
  end;
  begin
    execute $p$create policy av_session_materials_sem_area_leitura on av_session_materials
      for select to authenticated
      using (exists (select 1 from av_sessions s where s.id = av_session_materials.session_id and s.area is null))$p$;
  exception when duplicate_object then null;
            when others then raise notice 'av_session_materials: %', sqlerrm;
  end;
end $$;

-- Se um formando não conseguir abrir o teste do diagnóstico, é porque alguma função do servidor
-- confere a área da sessão. Corre esta consulta e envia-me o resultado:
-- select p.proname, pg_get_functiondef(p.oid)
-- from pg_proc p join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public' and p.prokind = 'f' and p.proname like 'av\_%'
--   and pg_get_functiondef(p.oid) ilike '%area%';
