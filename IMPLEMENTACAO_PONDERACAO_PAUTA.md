# Implementação de ponderação da pauta — cópia de validação

## O que foi alterado

- A pauta individual passa a usar dois pesos globais: **testes automáticos: 60%** e **avaliações práticas do formador: 40%**.
- Dentro de cada componente, os itens desse componente dividem o peso igualmente.
- A contribuição de cada item é calculada na escala de 0–20 e a soma das contribuições forma a classificação final.
- Se só existir uma das componentes, a pauta identifica a classificação como **provisória** e normaliza a componente disponível para 100%, evitando penalizar o formando por uma componente ainda não avaliada. Quando as duas componentes existirem, aplicam-se os pesos configurados.
- A média por sessão mantém-se como resumo informativo e fica explicitamente separada do cálculo global ponderado.
- A administração dispõe de um painel para alterar os pesos, com validação para garantir que são números inteiros e somam 100%.

## Persistência

A configuração não é guardada apenas no navegador. A aplicação lê e grava os pesos na tabela Supabase `public.av_assessment_settings`, para que a mesma configuração seja usada por todos os formandos e dispositivos.

A migração `supabase/migrations/012_pesos_pauta.sql` cria a tabela se necessário, preserva uma configuração já existente, activa RLS e limita explicitamente os privilégios a `SELECT`, `INSERT` e `UPDATE` para `authenticated`. Utilizadores autenticados podem ler os pesos; apenas o papel `admin` pode inserir/alterar a configuração. As restrições da tabela exigem que os pesos somem 100%. Os nomes das políticas foram alinhados com os que foram confirmados na base de dados, para evitar duplicações.

## Antes de usar em produção

1. Rever a migração `012_pesos_pauta.sql` contra o estado real do projecto Supabase.
2. Confirmar as permissões e políticas RLS existentes, incluindo a auditoria de segurança que ainda está pendente.
3. Aplicar a migração manualmente num ambiente de teste primeiro.
4. Entrar com uma conta `admin`, confirmar que a configuração 60/40 é carregada e guardar uma alteração de teste (por exemplo 50/50).
5. Entrar como formando e confirmar que a pauta mostra os mesmos pesos e o cálculo esperado.
6. Repor 60/40 no fim do teste, caso o ambiente seja usado para formação real.

Se a migração ainda não estiver aplicada, a aplicação mantém 60/40 apenas como valor temporário em memória, apresenta um aviso à administração e não consegue persistir alterações. **Esta cópia não aplica qualquer alteração à base de dados real.**

## Validações executadas nesta cópia

- `node --check` passou para o JavaScript inline do `index.html`.
- Testes de modelo passaram para: ambas as componentes presentes; apenas testes; apenas prática; e teste com peso 0%.
- Foram verificadas as referências à leitura/gravação Supabase e à migração.

## Limites da validação

Não foi possível executar um teste integrado com a instância real do Supabase nem testar a interface num navegador autenticado. A migração não foi executada. As funcionalidades já validadas de submissão e revisão dos testes não foram alteradas intencionalmente.
