# Portal de Formação AV — suporte a perguntas autodeclaradas

## Âmbito desta entrega

Base: pacote `Portal_Formacao_AV_Fase3_Diagnostico_Separador4.zip` recuperado da Biblioteca.

Esta entrega acrescenta suporte técnico para perguntas do tipo `sd` (autodeclaradas) e distingue finalidade de teste:

- `tematico`: classificação automática de 0 a 20; não aceita perguntas `sd`.
- `diagnostico`: sem classificação; permite perguntas `sd` e perguntas objectivas para recolha de evidência inicial.

A fórmula de certificação não foi alterada: 60% testes automáticos + 40% avaliação prática do formador.

## Alterações

- `index.html`: finalidade do teste no editor; selector de tipo de pergunta com opção autodeclarada; opções editáveis sem chave correcta; validação de opções; resposta do formando por escolha de rótulo; apresentação de diagnóstico sem nota; preservação de `score = null` na leitura.
- `supabase/migrations/015_perguntas_autodeclaradas_diagnostico.sql`: adiciona `test_purpose`; permite `sd` com opções sem chave correcta; permite `score` nulo; actualiza RPCs de leitura/submissão; valida no servidor as respostas autodeclaradas e impede `sd` em testes temáticos; exclui `sd` das métricas objectivas do diagnóstico de competências.

## Verificações efectuadas

- `node --check` executado sobre os scripts inline extraídos de `index.html`: passou sem erro de sintaxe JavaScript.
- Verificação estática da presença de campos, tipos e RPCs: concluída.

## Limitações e passos obrigatórios antes de produção

1. A migração SQL **não foi executada** em Supabase. Aplicar primeiro numa cópia/ambiente de teste e executar testes RLS e RPC.
2. Não foi possível testar login, permissões, submissão concorrente, janela de abertura/fecho ou persistência real contra uma base de dados ligada.
3. A migração reescreve a RPC de diagnóstico com a lógica actual de selecção da tentativa do formador (última tentativa para o material). A selecção de uma tentativa específica por colaborador continua a merecer correcção separada.
4. O banco final de 30 perguntas não foi carregado nesta entrega: o ZIP de origem não contém os enunciados completos e todas as opções/distratores validados. Não foram inventados enunciados para preencher lacunas.
5. A funcionalidade de colagem em lote continua orientada a V/F e escolha múltipla; as perguntas `sd` podem ser criadas pelo editor individual.

## Sequência recomendada

1. Fazer cópia de segurança da base de teste.
2. Aplicar `015_perguntas_autodeclaradas_diagnostico.sql` em ambiente de teste.
3. Validar testes antigos: leitura, submissão, nota, revisão após fecho e diagnóstico de competências.
4. Criar diagnóstico inicial com V/F, MC e `sd`; confirmar que a nota fica nula e que `sd` não entra nos acertos/erros.
5. Tentar inserir `sd` num teste temático; o servidor deve rejeitar a submissão.
6. Validar políticas RLS e que o formando nunca lê a chave correcta de MC/VF antes da submissão/fecho.
7. Só depois aprovar a aplicação em produção.
