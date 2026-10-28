# Fase 3 — Diagnóstico de competências

## Alterações nesta versão

1. O diagnóstico é apresentado no ecrã de resultado imediatamente após a submissão do teste, para além da área de diagnóstico do formando.
2. Na área administrativa de materiais > Resultados, foi acrescentada uma acção por tentativa para consultar o diagnóstico dessa tentativa. A consulta usa `attempt_id` e a tabela `av_competency_diagnostics`, evitando seleccionar por engano o diagnóstico de outro formando através da RPC que escolhe a tentativa mais recente do material.
3. São apresentadas apenas competências com evidência efectivamente mensurada: `answered > 0`, `total_mapped > 0` e percentagem não nula. Competências sem evidência são omitidas.
4. Foram adicionadas duas acções de impressão separadas: diagnóstico e recomendações. O navegador abre o diálogo de impressão, onde o utilizador pode escolher “Guardar como PDF”.

## Integridade e limites

- A ponderação oficial permanece fixa: 60% testes automáticos + 40% avaliação prática do formador.
- Não foram alteradas migrações SQL, funções, políticas RLS ou dados do Supabase.
- Não foi executado teste ponta-a-ponta com sessão autenticada contra o Supabase. O comportamento depende das permissões de leitura já configuradas para `av_competency_diagnostics`.
- A exportação usa o diálogo de impressão do navegador, não uma biblioteca PDF adicional.

## Verificações realizadas

- Verificação sintáctica do JavaScript inline com `node --check`: passou sem erros.
- Revisão estática dos pontos de integração: submissão/resultado do teste, área de diagnóstico do formando e tabela de resultados administrativos.

## Aplicação

Substituir o `index.html` do portal pela versão incluída neste pacote, seguindo o processo habitual de publicação. Não executar migrações SQL para estas alterações de interface.
