// AR Portal de Formação — Edge Function "admin-utilizadores"
// Só a administração (av_profiles.role = 'admin') pode usá-la. Corre no servidor do Supabase.
// A chave secreta é fornecida pelo próprio Supabase à função e nunca chega ao browser.
// Acções: list_users | create_user | reset_password | set_login
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

// Lê a chave "default" da lista nova; se não existir, usa a variável antiga.
function chave(listaNova: string, antiga: string): string {
  try {
    const k = JSON.parse(Deno.env.get(listaNova) ?? "{}")["default"];
    if (k) return k;
  } catch (_) { /* ignora */ }
  return Deno.env.get(antiga) ?? "";
}

function palavraPasseProvisoria(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(14));
  return Array.from(bytes, (b) => chars[b % chars.length]).join("") + "!7";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Método não permitido" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "Sem sessão" }, 401);
  const jwt = authHeader.slice(7);

  // 1. Quem está a chamar? (com a sessão do próprio utilizador, sujeito ao RLS)
  const chamador = createClient(url, chave("SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: u, error: ue } = await chamador.auth.getUser(jwt);
  if (ue || !u?.user) return json({ error: "Sessão inválida" }, 401);
  const { data: perfil } = await chamador.from("av_profiles").select("role").eq("user_id", u.user.id).single();
  if (perfil?.role !== "admin") return json({ error: "Apenas a administração pode usar esta função" }, 403);

  // 2. Cliente administrativo (só depois de confirmado que é admin)
  const admin = createClient(url, chave("SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let body: any;
  try { body = await req.json(); } catch (_) { return json({ error: "Pedido inválido" }, 400); }
  const acao = body?.action;

  // Impede alterar contas de administração por esta função.
  async function alvoPermitido(userId: string): Promise<string | null> {
    if (!userId) return "Falta o utilizador";
    if (userId === u.user.id) return "Não pode alterar a sua própria conta por aqui";
    const { data: p } = await admin.from("av_profiles").select("role").eq("user_id", userId).maybeSingle();
    if (p?.role === "admin") return "Contas de administração não se alteram por aqui";
    return null;
  }

  if (acao === "list_users") {
    const { data: lista, error } = await admin.auth.admin.listUsers({ page: 1, perPage: 200 });
    if (error) return json({ error: error.message }, 500);
    const { data: perfis } = await admin.from("av_profiles").select("user_id, role, staff_id, display_name");
    const { data: fichas } = await admin.from("av_staff").select("id, staff_number, full_name");
    const fm = new Map((fichas ?? []).map((s) => [s.id, s]));
    const pm = new Map((perfis ?? []).map((p) => [p.user_id, p]));
    return json({
      users: lista.users.map((x) => {
        const p = pm.get(x.id);
        const s = p?.staff_id ? fm.get(p.staff_id) : null;
        return {
          user_id: x.id,
          email: x.email,
          role: p?.role ?? null,
          display_name: p?.display_name ?? null,
          staff_id: p?.staff_id ?? null,
          staff: s ? `${s.staff_number} — ${s.full_name}` : null,
          banned: !!x.banned_until && new Date(x.banned_until) > new Date(),
          last_sign_in_at: x.last_sign_in_at ?? null,
          must_change_password: !!x.user_metadata?.must_change_password,
        };
      }),
    });
  }

  if (acao === "create_user") {
    const email = String(body.email ?? "").trim().toLowerCase();
    const papel = body.role === "trainer" ? "trainer" : "collaborator";
    const staffId = body.staff_id ? String(body.staff_id) : null;
    const nome = body.display_name ? String(body.display_name).trim().slice(0, 120) : null;
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "Email inválido" }, 400);
    if (papel === "collaborator" && !staffId) return json({ error: "Escolha a ficha do colaborador" }, 400);
    if (staffId) {
      const { data: f } = await admin.from("av_staff").select("id").eq("id", staffId).maybeSingle();
      if (!f) return json({ error: "Ficha não encontrada" }, 400);
      const { data: usada } = await admin.from("av_profiles").select("user_id").eq("staff_id", staffId).maybeSingle();
      if (usada) return json({ error: "Esta ficha já está ligada a outra conta" }, 409);
    }
    const password = palavraPasseProvisoria();
    const { data: criado, error: ce } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { must_change_password: true, display_name: nome },
    });
    if (ce || !criado?.user) return json({ error: ce?.message ?? "Não foi possível criar a conta" }, 400);
    const { error: pe } = await admin.from("av_profiles").upsert(
      { user_id: criado.user.id, role: papel, staff_id: staffId, display_name: nome },
      { onConflict: "user_id" },
    );
    if (pe) {
      await admin.auth.admin.deleteUser(criado.user.id); // não deixa uma conta a meio
      return json({ error: pe.message }, 400);
    }
    return json({ user_id: criado.user.id, email, role: papel, temp_password: password });
  }

  if (acao === "reset_password") {
    const userId = String(body.user_id ?? "");
    const recusa = await alvoPermitido(userId);
    if (recusa) return json({ error: recusa }, 400);
    const { data: atual, error: ge } = await admin.auth.admin.getUserById(userId);
    if (ge || !atual?.user) return json({ error: "Utilizador não encontrado" }, 404);
    const password = palavraPasseProvisoria();
    const { error } = await admin.auth.admin.updateUserById(userId, {
      password,
      user_metadata: { ...(atual.user.user_metadata ?? {}), must_change_password: true },
    });
    if (error) return json({ error: error.message }, 400);
    return json({ user_id: userId, temp_password: password });
  }

  if (acao === "set_login") {
    const userId = String(body.user_id ?? "");
    const recusa = await alvoPermitido(userId);
    if (recusa) return json({ error: recusa }, 400);
    const { error } = await admin.auth.admin.updateUserById(userId, {
      ban_duration: body.enabled ? "none" : "876000h",
    });
    if (error) return json({ error: error.message }, 400);
    return json({ user_id: userId, enabled: !!body.enabled });
  }

  return json({ error: "Acção desconhecida" }, 400);
});
