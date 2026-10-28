PORTAL DE FORMAÇÃO AV — FASE 3
AUDITORIA E CORRECÇÃO CIRÚRGICA DO DIAGNÓSTICO

Base utilizada:
Portal_Formacao_AV_Fase3_Diagnostico_Competencias(1).zip fornecido nesta sessão.

Constatações:
- O formulário inclui o selector opcional de competência por pergunta.
- A chamada RPC av_get_competency_diagnosis existe no fluxo de submissão.
- A submissão ignora o erro da chamada RPC, mantendo separada a submissão do teste.
- A área de diagnóstico do colaborador chama a RPC e trata explicitamente a ausência da função.
- Antes desta correcção, erros RPC diferentes de "função inexistente" eram ignorados e a interface podia apresentar uma mensagem genérica enganadora de ausência de perguntas mapeadas.
- O teste real já confirmado pelo utilizador gerou os 8 registos de diagnóstico; FIN-01 ficou com 0%, "Precisa de reforço", e as outras 7 competências com "Ainda sem evidência".

Alteração:
- No index.html, a área de diagnóstico passa agora a mostrar uma mensagem explícita quando a RPC falha por um erro diferente de função inexistente.
- A mensagem esclarece que a falha de diagnóstico não altera a nota do teste nem a fórmula oficial de certificação.
- Não foram alteradas migrações SQL, políticas RLS, funções SQL, dados, nem a fórmula de certificação (60% testes automáticos + 40% avaliação prática).

Validação:
- Verificação sintáctica do JavaScript inline com `node --check`: concluída sem erros.
- Não foi possível executar teste de interface ponta-a-ponta contra o Supabase nesta sessão.
- A correcção deve ser validada no portal após publicação/aplicação do index.html.

Estado:
- Correcção frontend preparada.
- Fase 3 ainda não deve ser declarada concluída até confirmar a mensagem/diagnóstico na interface real.
