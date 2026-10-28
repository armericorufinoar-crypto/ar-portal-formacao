# Próxima fase — ligação do frontend ao Supabase

## Estado

A fundação de dados e autorização está preparada em `supabase/migrations/001_initial_schema.sql`. O portal `index.html` continua a funcionar em modo local (`localStorage`) até a integração de autenticação e dados ser implementada e testada. Isto evita apresentar como multiutilizador um portal que ainda não sincroniza registos.

## Decisões de implementação já fixadas

- Projecto Supabase separado de outros sistemas.
- Papéis: `admin`, `trainer`, `collaborator`.
- Cinco áreas formativas: Finanças e Investimentos, Marketing e Vendas, Negócios, Oratória e Liderança.
- O formando entra com conta autenticada; não usar token previsível em query string como autenticação.
- A autorização é aplicada na base de dados através de RLS, não apenas escondendo botões na interface.
- Não implementar emissão de certificados nesta fase.

## Informação técnica necessária para concluir a ligação

O projecto ainda precisa de um URL Supabase e de uma chave pública `anon`/publishable, bem como dos redirect URLs finais. Estes valores não estão disponíveis neste ambiente. Não usar a chave `service_role` no navegador. Até os valores serem configurados, o backend não está ligado e não há sincronização entre dispositivos.
