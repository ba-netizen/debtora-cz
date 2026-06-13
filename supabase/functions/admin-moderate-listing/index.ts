/* ═══════════════════════════════════════════════════════
   DEBTORA CZ — Edge Function `admin-moderate-listing`
   Admin schválí/zamítne inzerát a majiteli odejde e-mail (fail-soft).

   Autorizace: volá se s JWT admina → admin_set_listing_status() ověří
   is_admin(auth.uid()). Servisní klient pak dohledá majitele a pošle e-mail.

   Deploy: supabase functions deploy admin-moderate-listing
   ═══════════════════════════════════════════════════════ */

import { createClient } from "npm:@supabase/supabase-js@2";
import { sendEmail, tplListingModerated } from "../_shared/email.ts";

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

  let listingId = "", status = "";
  try {
    const body = await req.json();
    listingId = String(body.listing_id ?? "");
    status = String(body.status ?? "");
  } catch (_e) { /* fallthrough */ }
  if (!listingId || !status) return json({ error: "Chybí listing_id/status." }, 400);

  // Klient s JWT volajícího → RPC ověří admina (is_admin) a změní stav.
  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );
  const { data: result, error } = await userClient.rpc("admin_set_listing_status", {
    p_listing: listingId, p_status: status,
  });
  if (error) return json({ error: error.message }, 500);
  if (!result || result.ok !== true) {
    return json(result ?? { ok: false, error: "unauthorized" }, 403);
  }

  // Servisní klient: dohledat majitele + titul a poslat e-mail (fail-soft).
  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: listing } = await admin.from("listings").select("title, owner_id").eq("id", listingId).maybeSingle();
    if (listing?.owner_id && (status === "active" || status === "rejected")) {
      const { data: profile } = await admin.from("users").select("email").eq("id", listing.owner_id).maybeSingle();
      if (profile?.email && !profile.email.endsWith("@debtora.invalid")) {
        const t = tplListingModerated(status === "active", listing.title ?? "");
        await sendEmail(profile.email, t.subject, t.html);
      }
    }
  } catch (e) {
    console.error("[admin-moderate-listing] email:", e); // fail-soft
  }

  return json({ ok: true });
});
