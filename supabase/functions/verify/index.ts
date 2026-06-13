/* ═══════════════════════════════════════════════════════
   DEBTORA CZ — Edge Function `verify`
   Lustrace subjektu v rejstřících podle zvolené úrovně.

   Režim (env VERIFY_MODE):
     mock  (DEFAULT) — deterministické výsledky, bez reálných rejstříků.
     live            — ISIR/ARES/DPH živě (SOAP/REST), CEE přes env adapter.

   Tok (sekce 9.2): vyber rejstříky dle matice úroveň×rejstřík → u placených
   ověř a strhni kredity (spend_credits) → dotaz → zápis verification_results
   (TTL 30 d) → verdikt per rejstřík + rizikové skóre. Selhání placené
   kontroly → refund kreditu (refund_credits).

   Deploy: supabase functions deploy verify
   ═══════════════════════════════════════════════════════ */

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  checkCee,
  fetchWithTimeout,
  validateSubject,
  type RegistryResult,
  type Subject,
  type SubjectPO,
} from "../_shared/cee.ts";
import {
  computeRiskScore,
  type Level,
  LEVELS,
  levelColumn,
  runRegistryMock,
  verdictGlyph,
} from "../_shared/registries.ts";

const ISIR_ENDPOINT = "https://isir.justice.cz:8443/isir_cuzk_ws/IsirWsCuzkService";
const ARES_ENDPOINT = "https://ares.gov.cz/ekonomicke-subjekty-v-be/rest/ekonomicke-subjekty/";
const DPH_ENDPOINT = "https://adisrws.mfcr.cz/adistc/axis2/services/rozhraniCRPDPH.rozhraniCRPDPHSOAP";
const RESULT_TTL_DAYS = 30;
const MODE = (Deno.env.get("VERIFY_MODE") ?? "mock").toLowerCase(); // 'mock' | 'live'

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
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
}

// ── XML helpery (live adaptery) ──
function xmlEscape(s: string): string {
  return s.replace(/[<>&'"]/g, (c) =>
    ({ "<": "&lt;", ">": "&gt;", "&": "&amp;", "'": "&apos;", '"': "&quot;" }[c]!));
}
function xmlText(xml: string, tag: string): string | null {
  const m = xml.match(new RegExp(`<(?:\\w+:)?${tag}[^>]*>([\\s\\S]*?)</(?:\\w+:)?${tag}>`));
  return m ? m[1].trim() : null;
}
function xmlBlocks(xml: string, tag: string): string[] {
  const re = new RegExp(`<(?:\\w+:)?${tag}[^>]*>([\\s\\S]*?)</(?:\\w+:)?${tag}>`, "g");
  const out: string[] = [];
  let m;
  while ((m = re.exec(xml)) !== null) out.push(m[1]);
  return out;
}

// ═══════════════ LIVE adaptery (jen v režimu live) ═══════════════
async function checkIsir(subject: Subject): Promise<RegistryResult> {
  let params = "";
  if (subject.type === "po") params = `<ic>${xmlEscape(subject.ico)}</ic>`;
  else if (subject.rc) params = `<rc>${xmlEscape(subject.rc)}</rc>`;
  else params = `<nazevOsoby>${xmlEscape(subject.lastName)}</nazevOsoby><jmeno>${xmlEscape(subject.firstName)}</jmeno><datumNarozeni>${xmlEscape(subject.birthDate)}</datumNarozeni>`;

  const envelope = `<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://isirws.cca.cz/types/"><soapenv:Body><typ:getIsirWsCuzkDataRequest>${params}<maxPocetVysledku>20</maxPocetVysledku><filtrAktualniRizeni>T</filtrAktualniRizeni><vyhledatBezDiakritiky>T</vyhledatBezDiakritiky></typ:getIsirWsCuzkDataRequest></soapenv:Body></soapenv:Envelope>`;
  const res = await fetchWithTimeout(ISIR_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "text/xml; charset=utf-8", SOAPAction: "" },
    body: envelope,
  });
  const xml = await res.text();
  if (!res.ok) throw new Error(`ISIR HTTP ${res.status}`);
  const kodChyby = xmlText(xml, "kodChyby");
  if (kodChyby) throw new Error(`ISIR ${kodChyby}`);
  const records = xmlBlocks(xml, "data");
  if (records.length === 0) return { status: "clear", detail: "Bez insolvenčního řízení." };
  return { status: "found", detail: `Nalezeno řízení: ${records.length}`, payload: { count: records.length } };
}

async function checkAres(subject: SubjectPO): Promise<RegistryResult> {
  const res = await fetchWithTimeout(ARES_ENDPOINT + encodeURIComponent(subject.ico), {
    headers: { Accept: "application/json" },
  });
  if (res.status === 404) return { status: "found", detail: "IČO v ARES nenalezeno." };
  if (!res.ok) throw new Error(`ARES HTTP ${res.status}`);
  const data = await res.json();
  const jmeno: string = data.obchodniJmeno ?? "";
  const problems: string[] = [];
  if (data.datumZaniku) problems.push(`zanikl ${data.datumZaniku}`);
  if (/v likvidaci/i.test(jmeno)) problems.push("v likvidaci");
  if (problems.length) return { status: "found", detail: `${jmeno} · ${problems.join(" · ")}` };
  return { status: "clear", detail: `${jmeno} · vznik ${data.datumVzniku ?? "—"}` };
}

async function checkDph(subject: SubjectPO): Promise<RegistryResult> {
  const envelope = `<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:roz="http://adis.mfcr.cz/rozhraniCRPDPH/"><soapenv:Body><roz:StatusNespolehlivyPlatceRequest><roz:dic>${xmlEscape(subject.ico)}</roz:dic></roz:StatusNespolehlivyPlatceRequest></soapenv:Body></soapenv:Envelope>`;
  const res = await fetchWithTimeout(DPH_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "text/xml; charset=utf-8", SOAPAction: "getStatusNespolehlivyPlatce" },
    body: envelope,
  });
  const xml = await res.text();
  if (!res.ok) throw new Error(`DPH HTTP ${res.status}`);
  const m = xml.match(/nespolehlivyPlatce="(\w+)"/);
  if (!m) throw new Error("DPH: neočekávaná odpověď");
  return m[1] === "ANO"
    ? { status: "found", detail: "Nespolehlivý plátce DPH." }
    : { status: "clear", detail: "Není veden jako nespolehlivý plátce." };
}

// Dispatch dle režimu. V live režimu mají adapter jen isir/ares/dph/cee.
async function runRegistry(registry: string, subject: Subject): Promise<RegistryResult> {
  if (MODE !== "live") return runRegistryMock(registry, subject);
  switch (registry) {
    case "isir": return await checkIsir(subject);
    case "ares": return subject.type === "po" ? await checkAres(subject) : { status: "skipped", message: "ARES jen pro PO." };
    case "dph": return subject.type === "po" ? await checkDph(subject) : { status: "skipped", message: "DPH jen pro PO." };
    case "cee": return await checkCee(subject);
    default: return { status: "unavailable", message: "Živý adapter zatím není k dispozici." };
  }
}

// ═══════════════ Konfigurace rejstříků pro danou úroveň ═══════════════
interface RegRow { registry: string; enabled: boolean; price_credits: number; included: boolean; }

async function loadRegistriesForLevel(admin: ReturnType<typeof adminClient>, level: Level): Promise<RegRow[]> {
  const col = levelColumn(level);
  const { data } = await admin
    .from("registry_config")
    .select(`registry, enabled, price_credits, ${col}`)
    .order("sort");
  return (data ?? []).map((r: Record<string, unknown>) => ({
    registry: r.registry as string,
    enabled: r.enabled as boolean,
    price_credits: (r.price_credits as number) ?? 0,
    included: Boolean(r[col]),
  }));
}

// ═══════════════ Perzistence ═══════════════
async function persist(
  admin: ReturnType<typeof adminClient>,
  userId: string | null,
  subject: Subject,
  level: Level,
  riskScore: number,
  results: Record<string, RegistryResult>,
): Promise<string | null> {
  try {
    const { data: req } = await admin.from("verification_requests").insert({
      user_id: userId,
      subject_type: subject.type,
      subject_name: subject.type === "fo" ? `${subject.firstName} ${subject.lastName}` : null,
      subject_birthdate: subject.type === "fo" ? subject.birthDate : null,
      subject_ico: subject.type === "po" ? subject.ico : null,
      level,
      risk_score: riskScore,
    }).select("id").single();
    if (!req) return null;

    const expiresAt = new Date(Date.now() + RESULT_TTL_DAYS * 86_400_000).toISOString();
    await admin.from("verification_results").insert(
      Object.entries(results).map(([registry, r]) => ({
        request_id: req.id,
        registry,
        status: r.status,
        payload: { detail: r.detail ?? r.message ?? null, data: r.payload ?? null, price: r.price ?? 0 },
        expires_at: expiresAt,
      })),
    );
    return req.id as string;
  } catch (_e) {
    return null; // audit nesmí shodit odpověď
  }
}

// ═══════════════ HANDLER ═══════════════
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // Identita (volitelná u foc_nologin)
  let userId: string | null = null;
  try {
    const authClient = createClient(
      Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
    );
    const { data } = await authClient.auth.getUser();
    userId = data.user?.id ?? null;
  } catch (_e) { /* anonym */ }

  // Vstup
  let subject: Subject | null = null;
  let level: Level = "basic";
  try {
    const body = await req.json();
    subject = validateSubject(body.subject);
    if (LEVELS.includes(body.level)) level = body.level;
  } catch (_e) { /* fallthrough */ }
  if (!subject) return json({ error: "Neplatné vstupní údaje." }, 400);

  // Úroveň foc_login+ vyžaduje přihlášení
  if (level !== "foc_nologin" && !userId) {
    return json({ error: "Pro tuto úroveň ověření se přihlaste.", needsAuth: true }, 401);
  }

  const admin = adminClient();
  const registries = (await loadRegistriesForLevel(admin, level))
    .filter((r) => r.enabled && r.included);

  // Dotaz na jednotlivé rejstříky (placené nejdřív strhnou kredit; selhání → refund)
  const results: Record<string, RegistryResult> = {};
  for (const reg of registries) {
    const price = reg.price_credits;

    if (price > 0) {
      if (!userId) { results[reg.registry] = { status: "locked", message: "Vyžaduje přihlášení.", price }; continue; }
      const { data: spent } = await admin.rpc("spend_credits", {
        p_user: userId, p_amount: price, p_reason: "spend",
      });
      if (!spent) {
        results[reg.registry] = { status: "locked", message: `Nedostatek kreditů (potřeba ${price}).`, price };
        continue;
      }
      let r: RegistryResult;
      try {
        r = await runRegistry(reg.registry, subject);
      } catch (e) {
        console.error(`[verify] ${reg.registry}:`, e);
        r = { status: "error", message: "Kontrolu se nepodařilo provést. Kredity jsme vrátili." };
      }
      // refund při selhání placené kontroly
      if (r.status === "error" || r.status === "locked") {
        await admin.rpc("refund_credits", { p_user: userId, p_amount: price, p_reason: "refund", p_payment: null });
      }
      r.price = price;
      results[reg.registry] = r;
    } else {
      try {
        results[reg.registry] = await runRegistry(reg.registry, subject);
      } catch (e) {
        console.error(`[verify] ${reg.registry}:`, e);
        results[reg.registry] = { status: "error", message: "Rejstřík se nepodařilo dotázat." };
      }
    }
  }

  const riskScore = computeRiskScore(results);
  await persist(admin, userId, subject, level, riskScore, results);

  // Odpověď s verdikt-glyphem per rejstřík
  const verdicts: Record<string, unknown> = {};
  for (const [registry, r] of Object.entries(results)) {
    verdicts[registry] = {
      status: r.status,
      glyph: verdictGlyph(r.status),
      detail: r.detail ?? r.message ?? null,
      price: r.price ?? 0,
    };
  }
  return json({ mode: MODE, level, risk_score: riskScore, results: verdicts });
});
