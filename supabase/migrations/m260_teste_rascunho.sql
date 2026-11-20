-- =====================================================================
-- 024_teste_rascunho.sql
-- Guardar as respostas do teste PERGUNTA A PERGUNTA no servidor.
--
-- PROBLEMA: hoje as respostas ficam só no ecrã até se carregar em
-- «Submeter». Se a ligação cai ou o telemóvel bloqueia a meio, a
-- tentativa perde-se e o formador tem de «restituir» o teste à mão.
--
-- SOLUÇÃO (aditiva): esta migração NÃO altera nenhuma função existente
-- (av_start_test, av_submit_test, av_check_test_answer, av_abandon_test,
-- av_reset_test_start ficam como estão). Só cria uma tabela e três
-- funções novas. Se a migração não estiver instalada, o portal continua
-- a funcionar como hoje (o código detecta e ignora).
--
-- ANTES DE EXECUTAR — confirme que estas colunas existem (cole no
-- SQL Editor; deve devolver 3 linhas com "ok"):
--
--   select 'av_test_starts' t, count(*) filter (where column_name in
--     ('material_id','staff_id','abandoned_at')) = 3 as ok
--     from information_schema.columns where table_name='av_test_starts'
--   union all
--   select 'av_test_attempts', count(*) filter (where column_name in
--     ('material_id','staff_id')) = 2
--     from information_schema.columns where table_name='av_test_attempts'
--   union all
--   select 'av_profiles', count(*) filter (where column_name in
--     ('user_id','staff_id','role')) = 3
--     from information_schema.columns where table_name='av_profiles';
--
-- Se alguma linha vier "false", NÃO execute e diga-me qual.
--
-- E confirme o TIPO dos identificadores (as colunas staff_id e id devem
-- ser todas do mesmo tipo; esta migração assume uuid):
--
--   select table_name, column_name, data_type from information_schema.columns
--   where (table_name='av_profiles' and column_name='staff_id')
--      or (table_name='av_test_starts' and column_name in ('staff_id','material_id'))
--      or (table_name='av_test_questions' and column_name in ('id','material_id'))
--      or (table_name='av_session_materials' and column_name='id');
--
-- Se vier "text" em vez de "uuid", diga-me e troco os tipos antes de executar.
-- =====================================================================


-- ---------------------------------------------------------------------
-- PASSO 1 — Tabela de rascunhos.
-- Uma linha por (formando, teste, pergunta) com a resposta dada até
-- agora. «checked» passa a true quando o formando carrega em «Verificar»
-- naquela pergunta: a partir daí a resposta fica bloqueada (assim ninguém
-- sai, volta, e muda uma resposta depois de ver se estava certa).
-- ---------------------------------------------------------------------
create table if not exists public.av_test_drafts (
  staff_id    uuid        not null,
  material_id uuid        not null,
  question_id uuid        not null,
  answer      jsonb       not null,
  checked     boolean     not null default false,
  saved_at    timestamptz not null default now(),
  primary key (staff_id, material_id, question_id)
);

-- Segurança ao nível da linha: o formando só pode LER os seus próprios
-- rascunhos; formadores/admin podem ler todos. Ninguém escreve
-- directamente: a escrita passa pelas funções abaixo (que validam).
alter table public.av_test_drafts enable row level security;

drop policy if exists av_test_drafts_select on public.av_test_drafts;
create policy av_test_drafts_select on public.av_test_drafts
  for select using (
    staff_id = (select staff_id from public.av_profiles where user_id = auth.uid())
    or exists (select 1 from public.av_profiles p
               where p.user_id = auth.uid() and p.role <> 'collaborator')
  );


-- ---------------------------------------------------------------------
-- PASSO 2 — av_save_test_answer: grava (ou actualiza) UMA resposta.
-- Só aceita se o formando tem o teste aberto (existe início em
-- av_test_starts), ainda não submeteu e não saiu de propósito.
-- Se a pergunta já foi verificada, ignora alterações (resposta bloqueada).
-- ---------------------------------------------------------------------
create or replace function public.av_save_test_answer(
  p_material uuid, p_question uuid, p_answer jsonb, p_checked boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_staff uuid;
begin
  select staff_id into v_staff from av_profiles where user_id = auth.uid();
  if v_staff is null then raise exception 'sem perfil de formando'; end if;

  if not exists (select 1 from av_test_starts s
                 where s.material_id = p_material and s.staff_id = v_staff
                   and s.abandoned_at is null)
     or exists (select 1 from av_test_attempts a
                where a.material_id = p_material and a.staff_id = v_staff) then
    return jsonb_build_object('saved', false);   -- teste não está aberto
  end if;

  -- a pergunta tem de pertencer a este teste
  if not exists (select 1 from av_test_questions q
                 where q.id = p_question and q.material_id = p_material) then
    return jsonb_build_object('saved', false);
  end if;

  insert into av_test_drafts (staff_id, material_id, question_id, answer, checked)
  values (v_staff, p_material, p_question, p_answer, coalesce(p_checked, false))
  on conflict (staff_id, material_id, question_id) do update
    set answer   = case when av_test_drafts.checked then av_test_drafts.answer else excluded.answer end,
        checked  = av_test_drafts.checked or excluded.checked,
        saved_at = now();
  return jsonb_build_object('saved', true);
end $$;


-- ---------------------------------------------------------------------
-- PASSO 3 — av_resume_test: «continuar o teste» depois de uma falha.
-- Só devolve as perguntas e as respostas guardadas quando:
--   • o formando abriu o teste (existe início),
--   • não submeteu,
--   • NÃO saiu de propósito (abandoned_at vazio — quem carrega em
--     «Sair e perder a tentativa» continua a perder, como hoje),
--   • há pelo menos uma resposta guardada.
-- Caso contrário devolve {resumed:false} e o ecrã mostra o aviso de
-- «teste bloqueado» de sempre. As perguntas vêm SEM a resposta certa.
-- ---------------------------------------------------------------------
create or replace function public.av_resume_test(p_material uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_staff uuid; v_purpose text;
begin
  select staff_id into v_staff from av_profiles where user_id = auth.uid();
  if v_staff is null then return jsonb_build_object('resumed', false); end if;

  if not exists (select 1 from av_test_starts s
                 where s.material_id = p_material and s.staff_id = v_staff
                   and s.abandoned_at is null)
     or exists (select 1 from av_test_attempts a
                where a.material_id = p_material and a.staff_id = v_staff)
     or not exists (select 1 from av_test_drafts d
                    where d.material_id = p_material and d.staff_id = v_staff) then
    return jsonb_build_object('resumed', false);
  end if;

  select coalesce(test_purpose, 'tematico') into v_purpose
    from av_session_materials where id = p_material;

  return jsonb_build_object(
    'resumed', true,
    'purpose', v_purpose,
    'questions', (select coalesce(jsonb_agg(jsonb_build_object(
                    'id', q.id, 'kind', q.kind, 'statement', q.statement,
                    'options', q.options) order by q.position), '[]'::jsonb)
                  from av_test_questions q where q.material_id = p_material),
    'answers', (select coalesce(jsonb_object_agg(d.question_id::text, d.answer), '{}'::jsonb)
                from av_test_drafts d
                where d.material_id = p_material and d.staff_id = v_staff),
    'checked', (select coalesce(jsonb_agg(d.question_id), '[]'::jsonb)
                from av_test_drafts d
                where d.material_id = p_material and d.staff_id = v_staff and d.checked)
  );
end $$;


-- ---------------------------------------------------------------------
-- PASSO 4 — Limpeza: quando a tentativa é submetida, os rascunhos
-- deixam de ser precisos. Um gatilho apaga-os por si, sem mexer na
-- função av_submit_test.
-- ---------------------------------------------------------------------
create or replace function public.av_drafts_cleanup() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from av_test_drafts where material_id = new.material_id and staff_id = new.staff_id;
  return new;
end $$;

drop trigger if exists av_drafts_cleanup_trg on public.av_test_attempts;
create trigger av_drafts_cleanup_trg
  after insert on public.av_test_attempts
  for each row execute function public.av_drafts_cleanup();


-- ---------------------------------------------------------------------
-- PASSO 5 — Permissões: só utilizadores com sessão iniciada.
-- ---------------------------------------------------------------------
revoke all on function public.av_save_test_answer(uuid, uuid, jsonb, boolean) from public;
revoke all on function public.av_resume_test(uuid) from public;
grant execute on function public.av_save_test_answer(uuid, uuid, jsonb, boolean) to authenticated;
grant execute on function public.av_resume_test(uuid) to authenticated;

-- Para reverter tudo (se algo correr mal):
--   drop trigger if exists av_drafts_cleanup_trg on public.av_test_attempts;
--   drop function if exists public.av_drafts_cleanup();
--   drop function if exists public.av_resume_test(uuid);
--   drop function if exists public.av_save_test_answer(uuid, uuid, jsonb, boolean);
--   drop table if exists public.av_test_drafts;
