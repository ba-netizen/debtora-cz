/* ═══════════════════════════════════════════════════════
   DEBTORA CZ — Edge Function `delete-account` (GDPR, D3)
   1) delete_account() RPC anonymizuje osobní údaje a odváže účetní doklady
      (payments, credit_transactions zůstávají kvůli zákonné retenci),
   2) servisní admin API smaže auth.users (cascade smaže neúčetní data).

   Deploy: supabase functions deploy delete-account
   ═══════════════════════════════════════════════════════ */

import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // Klient s JWT volajícího → identita + anonymizace na jeho účtu.
  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );
  const { data: u } = await userClient.auth.getUser();
  const userId = u.user?.id;
  if (!userId) return json({ error: "Nepřihlášený uživatel." }, 401);

  // 1) anonymizace (RPC běží jako auth.uid() volajícího)
  const { data: anon, error: anonErr } = await userClient.rpc("delete_account");
  if (anonErr || !anon || anon.ok !== true) {
    return json({ error: anonErr?.message ?? "Anonymizaci se nepodařilo provést." }, 500);
  }

  // 2) skutečné smazání auth.users přes admin API
  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { error: delErr } = await admin.auth.admin.deleteUser(userId);
    if (delErr) {
      console.error("[delete-account] auth delete:", delErr);
      // Anonymizace proběhla; účet je nepoužitelný i bez smazání → 207-like.
      return json({ ok: true, anonymized: true, authDeleted: false });
    }
  } catch (e) {
    console.error("[delete-account]:", e);
    return json({ ok: true, anonymized: true, authDeleted: false });
  }

  return json({ ok: true, anonymized: true, authDeleted: true });
});
