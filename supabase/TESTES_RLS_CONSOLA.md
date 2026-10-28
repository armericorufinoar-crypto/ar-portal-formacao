# Testes RLS pela consola do browser (chamadas directas à API)

Estes testes falam com o Supabase **sem passar pelo ecrã do portal**. Usam só a chave publishable que já está no `index.html`.
Cada linha mostra ✅ (comportamento esperado) ou ❌ (falha de segurança ou de configuração). Usar apenas contas e dados de teste.

**Nunca escrever palavras-passe no código.** A função `rlsEntrar` pede a palavra-passe numa caixa (`prompt`) e não a guarda.

## Preparação (uma vez por sessão do browser)

1. Aplicar a migração `003_leitura_so_activos.sql` no SQL Editor e correr a verificação no fim do ficheiro.
2. No SQL Editor, obter os identificadores das fichas de teste:

```sql
select staff_number, id from public.av_staff where staff_number in ('AR-001','AR 002');
```

3. Abrir o portal, carregar em **F12 → Console**. Se o Chrome avisar sobre colar código, escrever `allow pasting` e Enter.
4. Colar primeiro estas duas linhas. O `index.html` guarda estes valores dentro de uma função e a consola não os vê, por isso são definidos aqui. A chave é a **publishable**, a mesma que já está no `index.html`; nunca usar a `service_role`:

```js
var SUPABASE_URL='https://xpeeaekzomusoqjdpbxn.supabase.co';
var SUPABASE_KEY='sb_publishable_SGpFuCynHYERrDllnSjPuw_S0VzAY7S';
```

5. Colar depois este bloco (definições; se recarregares a página, cola de novo as duas linhas e o bloco):

```js
var rlsMk=()=>window.supabase.createClient(SUPABASE_URL,SUPABASE_KEY,{auth:{persistSession:false,autoRefreshToken:false,storageKey:'rls-'+Math.random()}});
async function rlsEntrar(email){const c=rlsMk();const r=await c.auth.signInWithPassword({email,password:prompt('Palavra-passe de '+email)});if(r.error){console.error('Login falhou:',r.error.message);return null}console.log('Sessão aberta:',email);return c}
var rlsOk=(n,v,x='')=>console.log((v?'✅ ':'❌ ')+n+(x!==''&&x!==undefined?'  → '+x:''));
var rlsNeg=r=>!!r.error&&(r.error.code==='42501'||/row-level security|permission denied/i.test(r.error.message));
var rlsZero=r=>!r.error&&Array.isArray(r.data)&&r.data.length===0;
var rlsEu=async c=>(await c.auth.getUser()).data.user.id;

async function rlsAnon(){
 const a=rlsMk();let r;
 for(const t of ['av_profiles','av_staff','av_sessions','av_attendance','av_assessments','av_forum_posts','av_forum_replies','av_session_feedback','av_private_messages','av_private_replies']){
  r=await a.from(t).select('*').limit(5);rlsOk('Sem sessão não lê '+t,rlsZero(r)||rlsNeg(r),r.error?r.error.code:'linhas='+r.data.length)}
 r=await a.from('av_forum_posts').insert({author_user_id:'00000000-0000-0000-0000-000000000000',body:'TESTE-RLS'});rlsOk('Sem sessão não escreve no fórum',rlsNeg(r),r.error?.code);
 for(const f of ['av_current_role','av_can_manage_training','av_is_active_participant']){r=await a.rpc(f);rlsOk('Sem sessão não chama '+f,!!r.error,r.error?.code)}
}

async function rlsColab(c,outroId,alvoId){
 const uid=await rlsEu(c);let r;
 const p=(await c.from('av_profiles').select('role,staff_id').eq('user_id',uid).single()).data;const meu=p.staff_id;
 rlsOk('Papel é collaborator',p.role==='collaborator',p.role);
 const sess=(await c.from('av_sessions').select('id').limit(1)).data?.[0]?.id;
 rlsOk('Colaborador activo vê as sessões',!!sess);
 r=await c.from('av_staff').select('id');rlsOk('Só vê a própria ficha',!r.error&&r.data.length===1&&r.data[0].id===meu,'linhas='+r.data?.length);
 r=await c.from('av_staff').select('*').eq('id',outroId);rlsOk('Não vê a ficha do outro',rlsZero(r));
 r=await c.from('av_profiles').select('user_id');rlsOk('Só vê o próprio perfil',!r.error&&r.data.length===1&&r.data[0].user_id===uid,'linhas='+r.data?.length);
 for(const t of ['av_attendance','av_assessments','av_session_feedback','av_private_messages']){
  r=await c.from(t).select('staff_id');rlsOk(t+': só registos próprios',!r.error&&r.data.every(x=>x.staff_id===meu),'linhas='+r.data?.length);
  r=await c.from(t).select('*').eq('staff_id',outroId);rlsOk(t+': nada do outro',rlsZero(r))}
 const ms=await c.from('av_private_messages').select('id');const ids=new Set((ms.data||[]).map(x=>x.id));
 r=await c.from('av_private_replies').select('message_id');rlsOk('Respostas privadas só das próprias mensagens',!r.error&&r.data.every(x=>ids.has(x.message_id)),'linhas='+r.data?.length);
 r=await c.from('av_attendance').insert({session_id:sess,staff_id:meu,status:'Presente'});rlsOk('Não insere presenças',rlsNeg(r),r.error?.code);
 r=await c.from('av_attendance').update({status:'Presente'}).eq('staff_id',meu).select();rlsOk('Não altera presenças',rlsZero(r),'afectadas='+r.data?.length);
 r=await c.from('av_assessments').insert({session_id:sess,staff_id:meu,exercise_title:'TESTE-RLS',score:100});rlsOk('Não insere avaliações',rlsNeg(r),r.error?.code);
 r=await c.from('av_assessments').update({score:100}).eq('staff_id',meu).select();rlsOk('Não altera avaliações',rlsZero(r),'afectadas='+r.data?.length);
 r=await c.from('av_private_messages').insert({staff_id:outroId,sender_user_id:uid,body:'TESTE-RLS'});rlsOk('Não cria mensagem privada no nome do outro',rlsNeg(r),r.error?.code);
 r=await c.from('av_session_feedback').insert({staff_id:outroId,session_id:sess,rating:1});rlsOk('Não cria feedback no nome do outro',rlsNeg(r),r.error?.code);
 r=await c.from('av_profiles').update({role:'admin'}).eq('user_id',uid).select();rlsOk('Não se promove a admin',rlsZero(r),'afectadas='+r.data?.length);
 r=await c.from('av_profiles').update({role:'trainer'}).eq('user_id',uid).select();rlsOk('Não se promove a trainer',rlsZero(r),'afectadas='+r.data?.length);
 r=await c.from('av_profiles').update({staff_id:outroId}).eq('user_id',uid).select();rlsOk('Não se liga a outra ficha',rlsZero(r),'afectadas='+r.data?.length);
 r=await c.from('av_profiles').insert({user_id:uid,role:'admin'});rlsOk('Não cria perfil admin',rlsNeg(r),r.error?.code);
 r=await c.from('av_staff').insert({staff_number:'TESTE-RLS-X',full_name:'x',department:'x',job_title:'x'});rlsOk('Não cria colaboradores',rlsNeg(r),r.error?.code);
 r=await c.from('av_staff').update({department:'TESTE-RLS'}).eq('id',meu).select();rlsOk('Não edita a própria ficha',rlsZero(r),'afectadas='+r.data?.length);
 if(alvoId){
  r=await c.from('av_staff').update({department:'ALTERADO'}).eq('id',alvoId).select();rlsOk('Não edita a ficha-alvo',rlsZero(r),'afectadas='+r.data?.length);
  r=await c.from('av_staff').delete().eq('id',alvoId).select();rlsOk('Não elimina a ficha-alvo',rlsZero(r),'afectadas='+r.data?.length)}
 r=await c.from('av_sessions').insert({title:'TESTE-RLS',area:'RH',session_date:'2099-01-01',trainer_name:'x'});rlsOk('Não cria sessões',rlsNeg(r),r.error?.code);
}

async function rlsFormador(c,staffId,alvoId){
 const uid=await rlsEu(c);let r;
 const p=(await c.from('av_profiles').select('role').eq('user_id',uid).single()).data;rlsOk('Papel é trainer',p.role==='trainer',p.role);
 r=await c.from('av_sessions').insert({title:'TESTE-RLS',area:'RH',session_date:'2099-01-01',trainer_name:'Teste'}).select().single();rlsOk('Cria sessão',!r.error,r.error?.code);const sid=r.data?.id;
 if(sid){
  r=await c.from('av_sessions').update({title:'TESTE-RLS 2'}).eq('id',sid).select();rlsOk('Edita sessão',!r.error&&r.data.length===1);
  r=await c.from('av_attendance').insert({session_id:sid,staff_id:staffId,status:'Presente'});rlsOk('Marca presença',!r.error,r.error?.code);
  r=await c.from('av_assessments').insert({session_id:sid,staff_id:staffId,exercise_title:'TESTE-RLS',score:50});rlsOk('Lança avaliação',!r.error,r.error?.code);
  r=await c.from('av_forum_posts').insert({author_user_id:uid,session_id:sid,body:'TESTE-RLS'}).select().single();rlsOk('Publica no fórum',!r.error,r.error?.code);const pid=r.data?.id;
  r=await c.from('av_private_messages').insert({staff_id:staffId,sender_user_id:uid,body:'TESTE-RLS'}).select().single();rlsOk('Inicia mensagem privada',!r.error,r.error?.code);const mid=r.data?.id;
  if(pid){r=await c.from('av_forum_posts').delete().eq('id',pid).select();rlsOk('Apaga publicação (moderação)',!r.error&&r.data.length===1)}
  if(mid){r=await c.from('av_private_messages').delete().eq('id',mid).select();rlsOk('Apaga mensagem de teste',!r.error&&r.data.length===1)}
  r=await c.from('av_sessions').delete().eq('id',sid).select();rlsOk('Elimina sessão (limpa presença e avaliação)',!r.error&&r.data.length===1)}
 r=await c.from('av_staff').insert({staff_number:'TESTE-RLS-X',full_name:'x',department:'x',job_title:'x'});rlsOk('Não cria colaboradores',rlsNeg(r),r.error?.code);
 if(alvoId){
  r=await c.from('av_staff').update({department:'ALTERADO'}).eq('id',alvoId).select();rlsOk('Não edita a ficha-alvo',rlsZero(r),'afectadas='+r.data?.length);
  r=await c.from('av_staff').delete().eq('id',alvoId).select();rlsOk('Não elimina a ficha-alvo',rlsZero(r),'afectadas='+r.data?.length)}
 r=await c.from('av_profiles').update({role:'admin'}).eq('user_id',uid).select();rlsOk('Não se promove a admin',rlsZero(r),'afectadas='+r.data?.length);
 r=await c.from('av_profiles').select('user_id');rlsOk('Só vê o próprio perfil',!r.error&&r.data.length===1,'linhas='+r.data?.length);
 for(const t of ['av_session_feedback','av_private_messages','av_attendance','av_assessments']){r=await c.from(t).select('id');rlsOk('Vê '+t+' de todos',!r.error,'linhas='+r.data?.length)}
}

async function rlsInactivo(c){
 const uid=await rlsEu(c);let r;const rnd='11111111-1111-1111-1111-111111111111';
 const meu=(await c.from('av_profiles').select('staff_id').eq('user_id',uid).single()).data.staff_id;
 r=await c.from('av_staff').select('id');rlsOk('Inactivo não vê a própria ficha',rlsZero(r),'linhas='+r.data?.length);
 for(const t of ['av_attendance','av_assessments','av_session_feedback','av_private_messages','av_private_replies','av_sessions','av_forum_posts','av_forum_replies']){
  r=await c.from(t).select('*').limit(5);rlsOk('Inactivo não lê '+t,rlsZero(r),'linhas='+r.data?.length)}
 r=await c.from('av_forum_posts').insert({author_user_id:uid,body:'TESTE-RLS'});rlsOk('Inactivo não publica no fórum',rlsNeg(r),r.error?.code);
 r=await c.from('av_forum_replies').insert({post_id:rnd,author_user_id:uid,body:'TESTE-RLS'});rlsOk('Inactivo não responde no fórum',rlsNeg(r),r.error?.code);
 r=await c.from('av_session_feedback').insert({staff_id:meu,session_id:rnd,rating:3});rlsOk('Inactivo não envia feedback',rlsNeg(r),r.error?.code);
 r=await c.from('av_private_messages').insert({staff_id:meu,sender_user_id:uid,body:'TESTE-RLS'});rlsOk('Inactivo não envia mensagem privada',rlsNeg(r),r.error?.code);
 r=await c.from('av_forum_posts').update({body:'ALTERADO'}).eq('author_user_id',uid).select();rlsOk('Inactivo não edita publicações',rlsZero(r),'afectadas='+r.data?.length);
 r=await c.from('av_forum_posts').delete().eq('author_user_id',uid).select();rlsOk('Inactivo não apaga publicações',rlsZero(r),'afectadas='+r.data?.length);
}

async function rlsAdmin(c){
 const uid=await rlsEu(c);let r;
 const p=(await c.from('av_profiles').select('role').eq('user_id',uid).single()).data;rlsOk('Papel é admin',p.role==='admin',p.role);
 r=await c.from('av_profiles').select('user_id,role');rlsOk('Vê todos os perfis',!r.error&&r.data.length>=4,'linhas='+r.data?.length);
 r=await c.from('av_staff').insert({staff_number:'TESTE-RLS-ADM',full_name:'Alvo admin',department:'Teste',job_title:'Teste'}).select().single();rlsOk('Cria colaborador',!r.error,r.error?.code);const id=r.data?.id;
 if(id){
  r=await c.from('av_staff').update({department:'Editado'}).eq('id',id).select();rlsOk('Edita colaborador',!r.error&&r.data.length===1);
  r=await c.from('av_staff').update({status:'Inactivo'}).eq('id',id).select();rlsOk('Desactiva colaborador',!r.error&&r.data.length===1&&r.data[0].status==='Inactivo');
  r=await c.from('av_staff').delete().eq('id',id).select();rlsOk('Elimina colaborador',!r.error&&r.data.length===1)}
 r=await c.from('av_profiles').select('user_id').eq('role','trainer').limit(1);const t=r.data?.[0];
 if(t){r=await c.from('av_profiles').update({role:'trainer'}).eq('user_id',t.user_id).select();rlsOk('Gere papéis (volta a atribuir trainer ao formador, sem mudar nada)',!r.error&&r.data.length===1)}
 for(const tb of ['av_staff','av_sessions','av_attendance','av_assessments','av_session_feedback','av_private_messages']){r=await c.from(tb).select('id');rlsOk('Vê '+tb+' de todos',!r.error,'linhas='+r.data?.length)}
}
```

## Teste A — sem sessão (anónimo)

```js
await rlsAnon()
```

Esperado: todas as linhas ✅.

## Teste B — ficha-alvo criada pelo administrador

Serve para provar, de forma segura, que formador e colaborador não conseguem editar nem apagar fichas.

```js
var admin=await rlsEntrar('formacao@av.com');
var r=await admin.from('av_staff').insert({staff_number:'TESTE-RLS',full_name:'Alvo de teste RLS',department:'Teste',job_title:'Teste'}).select().single();
var ALVO=r.data.id; console.log(r.error?('❌ '+r.error.message):'✅ Ficha-alvo criada')
```

## Teste C — colaborador 1 (AR-001)

Substituir `ID_AR_002` pelo identificador de AR 002 obtido no SQL.

```js
var c1=await rlsEntrar('formando@av.com');
await rlsColab(c1,'ID_AR_002',ALVO)
```

## Teste D — colaborador 2 (AR 002)

Substituir `ID_AR_001` pelo identificador de AR-001.

```js
var c2=await rlsEntrar('formando2@av.com');
await rlsColab(c2,'ID_AR_001',ALVO)
```

## Teste E — formador

Substituir `ID_AR_001` pelo identificador de AR-001.

```js
var f=await rlsEntrar('formador@av.com');
await rlsFormador(f,'ID_AR_001',ALVO)
```

## Teste F — colaborador inactivo

1. No SQL Editor: `update public.av_staff set status = 'Inactivo' where staff_number = 'AR 002';`
2. Na consola (cria nova sessão para a conta, já inactiva):

```js
var c2i=await rlsEntrar('formando2@av.com');
await rlsInactivo(c2i)
```

3. Reactivar no SQL Editor: `update public.av_staff set status = 'Activo' where staff_number = 'AR 002';`

## Teste G — limpeza e prova de que a ficha-alvo não foi tocada

```js
var q=await admin.from('av_staff').select('department,full_name').eq('id',ALVO).single();
console.log(q.data&&q.data.department==='Teste'?'✅ Ficha-alvo intacta':'❌ Ficha-alvo alterada ou apagada',q.data);
var d=await admin.from('av_staff').delete().eq('id',ALVO).select();
console.log(!d.error&&d.data.length===1?'✅ Ficha-alvo eliminada pelo admin':'❌ '+(d.error?.message||'não eliminou'))
```

## Teste H — administrador

Prova o lado contrário da regra: a administração **consegue** criar, editar, desactivar e eliminar colaboradores e gerir papéis. Cria uma ficha `TESTE-RLS-ADM`, edita-a, desactiva-a e apaga-a. Não muda nenhum papel (só volta a atribuir `trainer` ao formador).

```js
await rlsAdmin(admin)
```

Esperado: 12 linhas, todas ✅.

## Como ler os resultados

- **❌ numa linha "Não …"** significa que a operação proibida passou. Parar, copiar a linha e enviar. Não avançar para produção.
- **Update/delete bloqueados não dão erro**: o Supabase responde com 0 linhas afectadas. Por isso esses testes verificam `afectadas=0`.
- **Insert bloqueado dá erro `42501`**. Qualquer outro código (por exemplo `23505` ou `23503`) quer dizer que o RLS deixou passar e foi parado mais à frente.

## Fora destes testes

- **Ficheiros privados** (bucket e políticas de armazenamento): só existem quando houver upload (ponto 10).
- **Utilizador removido**: apagar a conta em Authentication → Users e confirmar que já não consegue entrar. Fazer no fim, com uma conta de teste.
