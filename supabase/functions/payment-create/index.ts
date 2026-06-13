/* ═══════════════════════════════════════════════════════
   DEBTORA CZ — Edge Function `payment-create`
   Akce:
     create — založí platbu v Comgate, vrátí redirect URL
              (jednorázová kontrola bez účtu; balíček jen s účtem;
               e-mail povinný vždy — faktura + doručení reportu)
     status — stav platby dle tajného tokenu (polling po návratu z brány)

   Env: COMGATE_MERCHANT, COMGATE_SECRET, COMGATE_TEST ("true"/"false")
   Deploy: supabase functions deploy payment-create
   ═══════════════════════════════════════════════════════ */

import { createClient } from "npm:@supabase/supabase-js@2";
import { validateSubject, type Subject } from "../_shared/cee.ts";

const COMGATE_CREATE = "https://payments.comgate.cz/v1.0/create";

// Produktový katalog (sekce 5). `months` = délka předplatného; `credits` = balíček.
const PRODUCTS: Record<
  string,
  { haleru: number; credits: number; months: number; label: string; needsAuth: boolean }
> = {
  single:              { haleru: 12_200,  credits: 0,  months: 0, label: "Kontrola exekucí (CEE) — Debtora",     needsAuth: false },
  pack5:               { haleru: 57_500,  credits: 5,  months: 0, label: "Balíček 5 kreditů — Debtora",          needsAuth: true },
  pack20:              { haleru: 188_000, credits: 20, months: 0, label: "Balíček 20 kreditů — Debtora",         needsAuth: true },
  pack50:              { haleru: 425_000, credits: 50, months: 0, label: "Balíček 50 kreditů — Debtora",         needsAuth: true },
  sub_inzerce_monthly: { haleru: 49_000,  credits: 0,  months: 1, label: "Inzerce — měsíční předplatné",         needsAuth: true },
};

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function adminClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

async function getUserId(req: Request): Promise<string | null> {
  try {
    const client = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
    );
    const { data } = await client.auth.getUser();
    return data.user?.id ?? null;
  } catch (_e) {
    return null;
  }
}

// ── create ──
async function handleCreate(req: Request, body: Record<string, unknown>): Promise<Response> {
  const product = PRODUCTS[String(body.product ?? "")];
  if (!product) return json({ error: "Neznámý produkt." }, 400);

  const email = String(body.email ?? "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
    return json({ error: "Zadejte platný e-mail — potřebujeme ho pro fakturu a zaslání výsledku." }, 400);
  }

  const userId = await getUserId(req);
  if (product.needsAuth && !userId) {
    return json({ error: "Balíček kontrol vyžaduje přihlášení k účtu." }, 401);
  }

  // Subjekt (koho lustrovat) je potřeba jen u jednorázové kontroly 'single'.
  let subject: Subject | null = null;
  if (String(body.product) === "single") {
    subject = validateSubject(body.subject);
    if (!subject) return json({ error: "Chybí údaje ověřované osoby." }, 400);
  }

  const admin = adminClient();
  const token = crypto.randomUUID();
  const { data: payment, error } = await admin
    .from("payments")
    .insert({
      token,
      user_id: userId,
      email,
      product: String(body.product),
      amount_haleru: product.haleru,
      subject: subject ? (subject as unknown) : null,
      credits_granted: 0, // připíše až callback po zaplacení
    })
    .select("id")
    .single();
  if (error || !payment) return json({ error: "Platbu se nepodařilo založit." }, 500);

  // Comgate /v1.0/create (form-encoded, prepareOnly)
  const params = new URLSearchParams({
    merchant: Deno.env.get("COMGATE_MERCHANT") ?? "",
    secret: Deno.env.get("COMGATE_SECRET") ?? "",
    test: Deno.env.get("COMGATE_TEST") === "false" ? "false" : "true",
    price: String(product.haleru),
    curr: "CZK",
    label: product.label,
    refId: payment.id,
    method: "ALL",
    email,
    prepareOnly: "true",
    lang: "cs",
  });
  const res = await fetch(COMGATE_CREATE, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: params.toString(),
  });
  const resp = new URLSearchParams(await res.text());

  if (resp.get("code") !== "0") {
    console.error("[payment-create] Comgate:", resp.get("code"), resp.get("message"));
    await admin.from("payments").update({ status: "error" }).eq("id", payment.id);
    return json({ error: "Platební brána je momentálně nedostupná. Zkuste to prosím později." }, 502);
  }

  await admin.from("payments")
    .update({ comgate_trans_id: resp.get("transId") })
    .eq("id", payment.id);

  return json({ redirect: resp.get("redirect"), token });
}

// ── status (polling po návratu z brány) ──
async function handleStatus(body: Record<string, unknown>): Promise<Response> {
  const token = String(body.token ?? "");
  if (!token) return json({ error: "Chybí token." }, 400);

  const admin = adminClient();
  const { data: p } = await admin
    .from("payments")
    .select("status, product, credits_granted, request_id, email")
    .eq("token", token)
    .single();
  if (!p) return json({ error: "Platba nenalezena." }, 404);

  const out: Record<string, unknown> = {
    status: p.status,
    product: p.product,
    credits: p.credits_granted,
  };

  if (p.status === "paid" && p.request_id) {
    const { data: results } = await admin
      .from("verification_results")
      .select("registry, status, payload")
      .eq("request_id", p.request_id);
    const cee = (results ?? []).find((r) => r.registry === "cee");
    if (cee) {
      out.cee = { status: cee.status, detail: (cee.payload as { detail?: string })?.detail ?? null };
    }
  }
  return json(out);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_e) {
    return json({ error: "Neplatný požadavek." }, 400);
  }

  switch (body.action) {
    case "create":
      return handleCreate(req, body);
    case "status":
      return handleStatus(body);
    default:
      return json({ error: "Neznámá akce." }, 400);
  }
});
