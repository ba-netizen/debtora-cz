/* ═══════════════════════════════════════════════════════
   DEBTORA CZ — Edge Function `payment-callback`
   Server-to-server notifikace z Comgate. Stav VŽDY znovu
   ověřujeme dotazem na /v1.0/status (notifikaci nevěříme).

   Po zaplacení:
     - balíček  → připíše kredity (add_credits)
     - single   → provede CEE kontrolu a uloží výsledek

   ⚠ Deploy BEZ ověřování JWT (Comgate neposílá Authorization):
     supabase functions deploy payment-callback --no-verify-jwt
   ═══════════════════════════════════════════════════════ */

import { createClient } from "npm:@supabase/supabase-js@2";
import { checkCee, type RegistryResult, type Subject } from "../_shared/cee.ts";

const COMGATE_STATUS = "https://payments.comgate.cz/v1.0/status";
const RESULT_TTL_DAYS = 30;

function adminClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

async function comgateStatus(transId: string): Promise<URLSearchParams> {
  const params = new URLSearchParams({
    merchant: Deno.env.get("COMGATE_MERCHANT") ?? "",
    secret: Deno.env.get("COMGATE_SECRET") ?? "",
    transId,
  });
  const res = await fetch(COMGATE_STATUS, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: params.toString(),
  });
  return new URLSearchParams(await res.text());
}

async function runCeeAndStore(
  admin: ReturnType<typeof adminClient>,
  paymentId: string,
  userId: string | null,
  subject: Subject,
): Promise<void> {
  let result: RegistryResult;
  try {
    result = await checkCee(subject);
  } catch (e) {
    console.error("[payment-callback] CEE:", e);
    result = { status: "error", message: "Kontrolu CEE se nepodařilo provést — kontaktujte podporu, platba bude vrácena." };
  }

  const { data: req } = await admin
    .from("verification_requests")
    .insert({
      user_id: userId,
      subject_type: subject.type,
      subject_name: subject.type === "fo" ? `${subject.firstName} ${subject.lastName}` : null,
      subject_birthdate: subject.type === "fo" ? subject.birthDate : null,
      subject_ico: subject.type === "po" ? subject.ico : null,
    })
    .select("id")
    .single();
  if (!req) return;

  await admin.from("verification_results").insert({
    request_id: req.id,
    registry: "cee",
    status: result.status,
    payload: { detail: result.detail ?? result.message ?? null, data: result.payload ?? null },
    expires_at: new Date(Date.now() + RESULT_TTL_DAYS * 86_400_000).toISOString(),
  });
  await admin.from("payments").update({ request_id: req.id }).eq("id", paymentId);
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  // Comgate posílá application/x-www-form-urlencoded
  let transId = "";
  try {
    const form = new URLSearchParams(await req.text());
    transId = form.get("transId") ?? "";
  } catch (_e) { /* fallthrough */ }
  if (!transId) return new Response("Missing transId", { status: 400 });

  // Ověření stavu přímo u Comgate
  const status = await comgateStatus(transId);
  if (status.get("code") !== "0") {
    console.error("[payment-callback] status error:", status.get("message"));
    return new Response("Status check failed", { status: 502 });
  }

  const admin = adminClient();
  const refId = status.get("refId") ?? "";
  const { data: payment } = await admin
    .from("payments")
    .select("id, user_id, product, amount_haleru, status, subject, credits_granted")
    .eq("id", refId)
    .eq("comgate_trans_id", transId)
    .single();
  if (!payment) return new Response("Unknown payment", { status: 404 });

  // Idempotence — notifikace může přijít opakovaně
  if (payment.status === "paid") return new Response("OK");

  const cgStatus = status.get("status");
  if (cgStatus === "CANCELLED") {
    await admin.from("payments").update({ status: "cancelled" }).eq("id", payment.id);
    return new Response("OK");
  }
  if (cgStatus !== "PAID") return new Response("OK"); // PENDING aj. — čekáme

  // Kontrola částky
  if (Number(status.get("price")) !== payment.amount_haleru || status.get("curr") !== "CZK") {
    console.error("[payment-callback] amount mismatch", refId);
    await admin.from("payments").update({ status: "failed" }).eq("id", payment.id);
    return new Response("Amount mismatch", { status: 400 });
  }

  await admin.from("payments")
    .update({ status: "paid", paid_at: new Date().toISOString() })
    .eq("id", payment.id);

  // Počet kreditů per balíček
  const CREDITS: Record<string, number> = { pack5: 5, pack20: 20, pack50: 50 };

  if (payment.product === "single") {
    // jednorázová CEE kontrola po zaplacení
    const subject = payment.subject as Subject | null;
    if (subject) await runCeeAndStore(admin, payment.id, payment.user_id, subject);
  } else if (payment.product === "sub_inzerce_monthly") {
    // měsíční předplatné Inzerce — aktivace/prodloužení období
    if (payment.user_id) {
      await admin.rpc("activate_subscription", {
        p_user: payment.user_id, p_service: "inzerce", p_months: 1, p_payment: payment.id,
      });
    }
  } else if (CREDITS[payment.product]) {
    // balíček kreditů — add_credits je IDEMPOTENTNÍ dle payment_id (D8)
    const credits = CREDITS[payment.product];
    if (payment.user_id) {
      await admin.rpc("add_credits", {
        p_user: payment.user_id, p_amount: credits, p_reason: "purchase", p_payment: payment.id,
      });
      await admin.from("payments").update({ credits_granted: credits }).eq("id", payment.id);
    }
  }

  // TODO fáze 2: vystavit fakturu (Fakturoid API) a poslat e-mail s reportem
  return new Response("OK");
});
