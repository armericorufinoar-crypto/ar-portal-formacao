# Migrações EXCELSA · ordem de execução

Esta pasta serve para **montar um projecto Supabase de raiz** (ambiente de teste) e para documentar a ordem
real. A produção já tem estas migrações aplicadas: não volte a executá-las lá. Os ficheiros `m010…m490`
têm o conteúdo dos originais (excepto o m440, ver abaixo); só mudaram o nome e a posição.
Os números vão de 10 em 10 para poder encaixar ficheiros em falta (o m200 está reservado).

Ordem verificada por análise estática (nomes de tabelas e funções) contra o conteúdo dos ficheiros.
**Não foi executada num Postgres**: a primeira execução num projecto vazio é o teste real.

## Ordem (novo ← original)
| Novo | Original | Nota |
|---|---|---|
| m010 | 001_initial_schema | só para projecto novo |
| m020 | 002_ajustes_rls | |
| m030 | 003_leitura_so_activos | |
| m040 | migracao-v11 | cria materiais e `av_user_seen`; **tem de vir antes** dos testes (a 004 depende dele) |
| m050 | migracao_reaccoes | reacções do fórum; antes de m130 |
| m060 | 025_forum_anexos | |
| m070 | 004_testes_escolha_multipla | |
| m080 | 005_correccao_imediata | |
| m090 | 006_nota_inteira | |
| m100 | 007_areas_de_acesso | |
| m110 | 008_areas_rls | |
| m120 | 023_diagnostico_sem_area | depois da 008 |
| m130 | 005_apagar_conteudo_e_utilizadores | |
| m140 | migracao_nota_0_20 | |
| m150 | 012_pesos_pauta | |
| m160 | 010_pagamentos | |
| m170 | 013_matriz_competencias | |
| m180 | 022_competencias_niveis | **antes** da 021: cria a coluna `levels` |
| m190 | 021_competencias_especificacao | usa `levels` |
| **m200** | **014_restituir_teste (FALTA)** | ver «Em falta» |
| m210 | 015_perguntas_autodeclaradas_diagnostico | |
| m220 | 016_revisao_imediata_diagnostico | |
| m230 | 023_sessao_nivel | |
| m240 | 015_treino_niveis | |
| m250 | 021_teste_feedback | depois da 015_treino_niveis (usa `av_train_staff_id`) |
| m260 | 024_teste_rascunho | |
| m270 | 017_treino_sessao | |
| m280 | 018_treino_trilha | |
| m290 | 025_treino_sessao_link | substitui a 019_treino_sessao_link |
| m300 | 020_treino_profundidade_cadencia | |
| m310 | 022_perguntas_sem_repeticao | depois do treino |
| m320 | 021_conversao_areas | |
| m330–m420 | 025_treino_xp, 026_treino_missoes, 027_treino_liga, 028_treino_liga_formador, 029_treino_missoes_xp, 030_treino_liga_promocao, 032_treino_avatar_extras, 033_treino_protecao_sequencia, 034_treino_bonus_rever_erros, 035_treino_bau_diario | ordem original, está coerente |
| m430 | 019_crm_interessados | |
| m440 | 020_novos_interessados | **só o esquema** (coluna `profession`) |
| m450 | sql_025_crm_proximo_passo | única versão completa dos campos de seguimento |
| m460–m480 | sql_fase1_simulador_markup, sql_fase2_crm_treino, sql_etapas_5_simulador | |
| m490 | F4-1_etapa_materiais | |

## Pastas auxiliares
- `_so_bases_antigas/` · 009 e 011: só migram nomes de áreas de bases antigas; a 001 já traz as áreas novas.
- `_opcionais/` · 016_diagnostico_org (nenhuma referência no index.html) e 017_verificar (script de teste que termina em erro de propósito).
- `_substituidas_nao_executar/` · 019_treino_sessao_link (substituída pela 025, que tem guarda), crm_followup_fields e 026_crm_proximo_passo (substituídas pela sql_025; a 026 usa a coluna `next_contact`, que o portal não usa, e refere `av_crm_leads`/`av_crm_opps`, que não existem).

## Em falta (não estão no zip, mas o index.html usa)
1. **014_restituir_teste.sql**: `av_test_starts`, `av_start_test`, `av_abandon_test`, `av_reset_test_start`.
2. **feedback_respostas**: `av_feedback_reactions`, `av_feedback_replies`.
3. **Origem de `av_competency_diagnostics`** (usada pela m210) e de `av_get_competency_diagnosis`.
4. `migracao_chat_anexos.sql` (citada pela migracao_reaccoes; talvez coberta pela 025_forum_anexos) e a numeração 031 (salta de 030 para 032).

Sem estes não se monta um ambiente de teste igual à produção. Recuperá-los: nas conversas anteriores, ou exportando o esquema
de produção (Supabase CLI: `supabase db dump --schema public --linked`) e guardando o resultado como m200.

## Riscos encontrados
1. **Funções de teste sobrepostas.** `av_get_test` e `av_submit_test` são redefinidas 5 e 4 vezes. A m210 reescreve ambas sem a verificação de áreas da m100 e com nota de 2 casas decimais (a m090 queria nota inteira). Pode ter sido intencional (a m120 diz que a verificação de áreas bloqueava o diagnóstico), mas deixa o servidor sem verificação de áreas nos testes. Corra `verificar_producao.sql` para ver o estado real.
2. **Dados pessoais numa migração.** O original da 020 inseria 4 interessados reais (nome, telefone, e-mail). Retirei isso do m440. Não o suba para o GitHub nem para o ambiente de teste.
3. **Ficheiros destrutivos ou de uma só execução:** 020 (apaga a coluna `interest`) e 021_conversao_areas.
4. **Cabeçalhos desactualizados:** 015_treino_niveis, 017, 019, 025_link e outros ainda dizem «RASCUNHO… não executar», mas já foram executados.
5. **Mensagens do index.html** referem nomes antigos (010_pagamentos, 013, 014, 015_treino_niveis, 022_competencias_niveis, 024_crm_proximo_passo, 024_teste_rascunho). Actualizar na próxima versão do index.html.
