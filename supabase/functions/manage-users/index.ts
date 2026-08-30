import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json" },
});

const permissionsFrom = (value: Record<string, unknown> = {}) => ({
  can_view: value.can_view !== false,
  can_create: value.can_create === true,
  can_edit: value.can_edit === true,
  can_delete: value.can_delete === true,
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Método não permitido." }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Sessão ausente." }, 401);

    const userClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });
    const token = authHeader.replace(/^Bearer\s+/i, "");
    const { data: authData, error: authError } = await userClient.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "Sessão inválida." }, 401);

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
    const caller = authData.user;
    const { data: callerProfile } = await admin.from("profiles")
      .select("is_master")
      .eq("id", caller.id)
      .maybeSingle();
    if (!callerProfile?.is_master) return json({ error: "Apenas o usuário master pode gerenciar usuários." }, 403);

    const body = await req.json().catch(() => ({}));
    const action = String(body.action || "list");

    if (action === "list") {
      const [{ data: allowed, error: allowedError }, { data: profiles, error: profilesError }] = await Promise.all([
        admin.from("allowed_emails").select("email,role,approved_at,can_manage_users,can_view,can_create,can_edit,can_delete").order("email"),
        admin.from("profiles").select("email,role,is_master,must_change_password,last_login,can_view,can_create,can_edit,can_delete"),
      ]);
      if (allowedError || profilesError) throw allowedError || profilesError;
      const profileByEmail = new Map((profiles || []).map((p) => [String(p.email).toLowerCase(), p]));
      return json({ users: (allowed || []).map((a) => ({
        email: a.email,
        role: a.role,
        ...permissionsFrom(a),
        approved_at: a.approved_at,
        can_manage_users: a.can_manage_users,
        profile: profileByEmail.get(String(a.email).toLowerCase()) || null,
      })) });
    }

    const email = String(body.email || "").trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "Email inválido." }, 400);
    if (email === String(caller.email || "").toLowerCase()) {
      return json({ error: "O master não pode alterar o próprio acesso por este painel." }, 400);
    }

    if (action === "create") {
      const permissions = permissionsFrom(body.permissions);
      const role = permissions.can_create || permissions.can_edit || permissions.can_delete ? "editor" : "viewer";
      const password = String(body.password || "");
      if (password.length < 8) return json({ error: "A senha temporária deve ter pelo menos 8 caracteres." }, 400);
      const { data: protectedProfile } = await admin.from("profiles").select("is_master").eq("email", email).maybeSingle();
      if (protectedProfile?.is_master) return json({ error: "O acesso de um master não pode ser alterado por este painel." }, 400);
      const { error: allowError } = await admin.from("allowed_emails").upsert({
        email,
        role,
        ...permissions,
        can_manage_users: false,
        approved_by: caller.id,
        approved_at: new Date().toISOString(),
      }, { onConflict: "email" });
      if (allowError) throw allowError;

      const { data: usersData, error: usersError } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
      if (usersError) throw usersError;
      const existing = usersData.users.find((u) => String(u.email || "").toLowerCase() === email);
      if (existing) {
        const { error: updateError } = await admin.auth.admin.updateUserById(existing.id, { password, email_confirm: true, ban_duration: "none" });
        if (updateError) throw updateError;
        const { error: profileError } = await admin.from("profiles").upsert({ id: existing.id, email, role, ...permissions, must_change_password: true }, { onConflict: "id" });
        if (profileError) throw profileError;
      } else {
        const { error: createError } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
        if (createError) throw createError;
      }
      await admin.from("audit_log").insert({
        user_id: caller.id,
        action: existing ? "user_reactivated" : "user_created_by_master",
        table_name: "allowed_emails",
        record_id: email,
        changes: { role, permissions },
      });
      return json({ message: existing ? "Usuário reativado com uma nova senha temporária." : "Usuário criado com sucesso." });
    }

    if (action === "update_permissions") {
      const permissions = permissionsFrom(body.permissions);
      const role = permissions.can_create || permissions.can_edit || permissions.can_delete ? "editor" : "viewer";

      const [{ data: targetProfile, error: profileLookupError }, { data: allowedUser, error: allowedLookupError }] = await Promise.all([
        admin.from("profiles").select("id,is_master,role,can_view,can_create,can_edit,can_delete").eq("email", email).maybeSingle(),
        admin.from("allowed_emails").select("role,can_view,can_create,can_edit,can_delete").eq("email", email).maybeSingle(),
      ]);
      if (profileLookupError || allowedLookupError) throw profileLookupError || allowedLookupError;
      if (!allowedUser) return json({ error: "Usuário autorizado não encontrado." }, 404);
      if (targetProfile?.is_master) return json({ error: "A permissão de um usuário master não pode ser alterada." }, 400);

      const { error: allowUpdateError } = await admin.from("allowed_emails").update({ role, ...permissions }).eq("email", email);
      if (allowUpdateError) throw allowUpdateError;
      if (targetProfile?.id) {
        const { error: profileUpdateError } = await admin.from("profiles").update({ role, ...permissions }).eq("id", targetProfile.id);
        if (profileUpdateError) {
          await admin.from("allowed_emails").update(allowedUser).eq("email", email);
          throw profileUpdateError;
        }
      }

      await admin.from("audit_log").insert({
        user_id: caller.id,
        action: "user_permissions_updated",
        table_name: "profiles",
        record_id: email,
        changes: { permissions },
      });
      return json({ message: "Permissões alteradas com sucesso." });
    }

    if (action === "revoke") {
      const { data: targetProfile } = await admin.from("profiles").select("id,is_master").eq("email", email).maybeSingle();
      if (targetProfile?.is_master) return json({ error: "Não é permitido revogar outro usuário master." }, 400);
      if (targetProfile?.id) {
        await admin.auth.admin.updateUserById(targetProfile.id, { ban_duration: "876000h" });
        const { error: profileDeleteError } = await admin.from("profiles").delete().eq("id", targetProfile.id);
        if (profileDeleteError) throw profileDeleteError;
      }
      const { error: allowDeleteError } = await admin.from("allowed_emails").delete().eq("email", email);
      if (allowDeleteError) throw allowDeleteError;
      await admin.from("audit_log").insert({
        user_id: caller.id,
        action: "user_revoked",
        table_name: "allowed_emails",
        record_id: email,
      });
      return json({ message: "Acesso revogado com sucesso." });
    }

    return json({ error: "Ação inválida." }, 400);
  } catch (error) {
    console.error(error);
    return json({ error: error instanceof Error ? error.message : "Erro interno." }, 500);
  }
});
