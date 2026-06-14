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
  subjectHash,
  verdictGlyph,
} from "../_shared/registries.ts";

const ISIR_ENDPOINT = "https://isir.justice.cz:8443/isir_cuzk_ws/IsirWsCuzkService";
const ARES_ENDPOINT = "https://ares.gov.cz/ekonomicke-subjekty-v-be/rest/ekonomicke-subjekty/";
const DPH_ENDPOINT = "https://adisrws.mfcr.cz/adistc/axis2/services/rozhraniCRPDPH.rozhraniCRPDPHSOAP";
const RESULT_TTL_DAYS = 30;
const MODE = (Deno.env.get("VERIFY_MODE") ?? "live").toLowerCase(); // 'mock' | 'live' (default live; secret může přepnout)

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
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/'/g, "&apos;").replace(/"/g, "&quot;");
}
function xmlText(xml: string, tag: string): string | null {
  const m = xml.match(new RegExp(`<(?:[A-Za-z0-9_]+:)?${tag}[^>]*>([^]*?)</(?:[A-Za-z0-9_]+:)?${tag}>`));
  return m ? m[1].trim() : null;
}
function xmlBlocks(xml: string, tag: string): string[] {
  const re = new RegExp(`<(?:[A-Za-z0-9_]+:)?${tag}[^>]*>([^]*?)</(?:[A-Za-z0-9_]+:)?${tag}>`, "g");
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
  // WS2 = "Prázdný výsledek" → žádné záznamy = subjekt není v insolvenci (clear).
  if (kodChyby === "WS2") return { status: "clear", detail: "Bez insolvenčního řízení." };
  if (kodChyby) return { status: "error", message: `ISIR: ${xmlText(xml, "textChyby") ?? kodChyby}` };
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
  const m = xml.match(/nespolehlivyPlatce="([A-Za-z0-9_]+)"/);
  if (!m) throw new Error("DPH: neočekávaná odpověď");
  return m[1] === "ANO"
    ? { status: "found", detail: "Nespolehlivý plátce DPH." }
    : { status: "clear", detail: "Není veden jako nespolehlivý plátce." };
}

// Dohledání názvu firmy z ARES (vždy — i v mock režimu; veřejné REST, fail-soft).
async function aresName(ico: string): Promise<string | null> {
  try {
    const res = await fetchWithTimeout(ARES_ENDPOINT + encodeURIComponent(ico), { headers: { Accept: "application/json" } });
    if (!res.ok) return null;
    const data = await res.json();
    return (data.obchodniJmeno as string) ?? null;
  } catch (_e) {
    return null;
  }
}

// Plná ARES data (pro RŽP/CEÚ/sbírku). Fail-soft.
async function aresJson(ico: string): Promise<Record<string, unknown> | null> {
  try {
    const res = await fetchWithTimeout(ARES_ENDPOINT + encodeURIComponent(ico), { headers: { Accept: "application/json" } });
    if (!res.ok) return null;
    return await res.json();
  } catch (_e) { return null; }
}

// VIES — ověření DIČ v rámci EU (veřejné SOAP, zdarma). PO/DIČ.
async function checkVies(subject: SubjectPO): Promise<RegistryResult> {
  const env = `<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:ec.europa.eu:taxud:vies:services:checkVat:types"><soapenv:Body><urn:checkVat><urn:countryCode>CZ</urn:countryCode><urn:vatNumber>${xmlEscape(subject.ico)}</urn:vatNumber></urn:checkVat></soapenv:Body></soapenv:Envelope>`;
  const res = await fetchWithTimeout("https://ec.europa.eu/taxation_customs/vies/services/checkVatService", { method: "POST", headers: { "Content-Type": "text/xml; charset=utf-8" }, body: env });
  const xml = await res.text();
  if (!res.ok) throw new Error(`VIES HTTP ${res.status}`);
  const valid = xmlText(xml, "valid");
  if (valid === "true") { const nm = xmlText(xml, "name"); return { status: "clear", detail: `Platné DIČ v EU (VIES)${nm && nm !== "---" ? " · " + nm : ""}.` }; }
  return { status: "found", detail: "DIČ není v EU systému VIES platné." };
}

// Živnostenský rejstřík (RŽP) — přes ARES seznamRegistraci. PO/IČO.
async function checkZivnost(subject: SubjectPO): Promise<RegistryResult> {
  const d = await aresJson(subject.ico);
  if (!d) return { status: "unavailable", message: "ARES nedostupný." };
  const reg = (d.seznamRegistraci ?? {}) as Record<string, unknown>;
  return reg.stavZdrojeRzp === "AKTIVNI"
    ? { status: "clear", detail: "Aktivní živnostenské oprávnění (RŽP)." }
    : { status: "clear", detail: "Bez aktivního živnostenského oprávnění." };
}

// Evidence úpadců (CEÚ) — přes ARES. PO/IČO.
async function checkUpadci(subject: SubjectPO): Promise<RegistryResult> {
  const d = await aresJson(subject.ico);
  if (!d) return { status: "unavailable", message: "ARES nedostupný." };
  const reg = (d.seznamRegistraci ?? {}) as Record<string, unknown>;
  return reg.stavZdrojeCeu === "AKTIVNI"
    ? { status: "found", detail: "Záznam v evidenci úpadců (CEÚ)." }
    : { status: "clear", detail: "Bez záznamu v evidenci úpadců." };
}

// Sbírka listin / účetní závěrky — odkaz do veřejného rejstříku. PO/IČO.
function checkSbirka(subject: SubjectPO): RegistryResult {
  return { status: "clear", detail: `Účetní závěrky dostupné ve sbírce listin (or.justice.cz, IČO ${subject.ico}).`, payload: { url: `https://or.justice.cz/ias/ui/rejstrik-$firma?ico=${subject.ico}` } };
}

// Dispatch dle režimu.
async function runRegistry(registry: string, subject: Subject): Promise<RegistryResult> {
  if (MODE !== "live") return runRegistryMock(registry, subject);
  const poOnly = (msg: string): RegistryResult => ({ status: "skipped", message: msg });
  switch (registry) {
    case "isir": return await checkIsir(subject);
    case "ares": return subject.type === "po" ? await checkAres(subject) : poOnly("ARES jen pro firmy.");
    case "dph": return subject.type === "po" ? await checkDph(subject) : poOnly("DPH jen pro firmy.");
    case "vies": return subject.type === "po" ? await checkVies(subject) : poOnly("VIES jen pro firmy (DIČ).");
    case "zivnost": return subject.type === "po" ? await checkZivnost(subject) : poOnly("Živnost jen pro IČO.");
    case "upadci": return subject.type === "po" ? await checkUpadci(subject) : poOnly("CEÚ jen pro IČO.");
    case "sbirka": return subject.type === "po" ? checkSbirka(subject) : poOnly("Sbírka listin jen pro firmy.");
    case "cee": return await checkCee(subject);
    case "isds": return { status: "unavailable", message: "Datová schránka — vyžaduje přístup ISDS (konfigurace)." };
    case "sankce": return { status: "unavailable", message: "Sankční/PEP seznamy — připravujeme." };
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
  requestId: string | null,
  subjectName: string | null,
): Promise<string | null> {
  try {
    const { data: req } = await admin.from("verification_requests").insert({
      user_id: userId,
      request_id: requestId,
      subject_type: subject.type,
      subject_name: subjectName,
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

// Verdikt-objekty pro odpověď.
function toVerdicts(results: Record<string, RegistryResult>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [registry, r] of Object.entries(results)) {
    out[registry] = {
      status: r.status,
      glyph: verdictGlyph(r.status),
      detail: r.detail ?? r.message ?? null,
      price: r.price ?? 0,
    };
  }
  return out;
}

// Klientská IP (za proxy Supabase/Vercel).
function clientIp(req: Request): string | null {
  const xff = req.headers.get("x-forwarded-for");
  if (xff) return xff.split(",")[0].trim();
  return req.headers.get("x-real-ip");
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
  let requestId: string | null = null;
  let confirm = false;
  try {
    const body = await req.json();
    subject = validateSubject(body.subject);
    if (LEVELS.includes(body.level)) level = body.level;
    if (typeof body.request_id === "string") requestId = body.request_id;
    confirm = body.confirm === true;
  } catch (_e) { /* fallthrough */ }
  if (!subject) return json({ error: "Neplatné vstupní údaje." }, 400);

  if (level !== "foc_nologin" && !userId) {
    return json({ error: "Pro tuto úroveň ověření se přihlaste.", needsAuth: true }, 401);
  }

  const admin = adminClient();

  // Název subjektu do výsledku: FO = jméno+příjmení; PO = reálný název z ARES.
  let subjectName: string | null = subject.type === "fo"
    ? `${subject.firstName} ${subject.lastName}`
    : await aresName(subject.ico);

  // ── A1: IDEMPOTENCE ── stejný request_id → vrať uložený výsledek, bez strhu.
  if (requestId) {
    const { data: prev } = await admin
      .from("verification_requests")
      .select("id, risk_score, level, subject_name")
      .eq("request_id", requestId)
      .maybeSingle();
    if (prev) {
      const { data: rows } = await admin
        .from("verification_results")
        .select("registry, status, payload")
        .eq("request_id", prev.id);
      const results: Record<string, RegistryResult> = {};
      for (const row of rows ?? []) {
        const p = (row.payload ?? {}) as { detail?: string; price?: number };
        results[row.registry] = { status: row.status, detail: p.detail ?? undefined, price: p.price ?? 0 };
      }
      return json({
        mode: MODE, level: prev.level ?? level, risk_score: prev.risk_score ?? 0,
        results: toVerdicts(results), subject_name: prev.subject_name ?? subjectName, idempotent: true,
      });
    }
  }

  // ── A2/A3: rozpočet podle úrovně ── vyber zapnuté rejstříky dostupné v úrovni.
  const registries = (await loadRegistriesForLevel(admin, level)).filter((r) => r.enabled && r.included);
  const totalCredits = registries.reduce((sum, r) => sum + (r.price_credits ?? 0), 0);
  const budget = {
    registries: registries.map((r) => ({ registry: r.registry, price: r.price_credits })),
    total_credits: totalCredits,
  };

  // Placená úroveň bez potvrzení → vrať jen rozpočet (předběžný souhlas).
  if (totalCredits > 0 && !confirm) {
    return json({ mode: MODE, level, quote: budget, request_id: requestId });
  }

  // ── D4: rate limit pro FOC (bezplatné) úrovně ──
  if (totalCredits === 0) {
    const ip = clientIp(req);
    const { data: allowed } = await admin.rpc("foc_check_and_count", {
      p_ip: ip, p_subject_hash: subjectHash(subject),
    });
    if (allowed === false) {
      return json({
        error: "Překročen denní limit bezplatných kontrol. Přihlaste se nebo zvolte placenou úroveň.",
        rateLimited: true,
      }, 429);
    }
  }

  // ── Strh celkové ceny jedním spend_credits (placené úrovně) ──
  if (totalCredits > 0) {
    if (!userId) return json({ error: "Pro placenou kontrolu se přihlaste.", needsAuth: true }, 401);
    const { data: spent } = await admin.rpc("spend_credits", {
      p_user: userId, p_amount: totalCredits, p_reason: "spend",
    });
    if (!spent) {
      return json({ error: `Nedostatek kreditů (potřeba ${totalCredits}).`, needCredits: totalCredits, quote: budget }, 402);
    }
  }

  // ── Dotaz na rejstříky; selhání placeného → refund jeho podílu ──
  const results: Record<string, RegistryResult> = {};
  for (const reg of registries) {
    const price = reg.price_credits ?? 0;
    let r: RegistryResult;
    try {
      r = await runRegistry(reg.registry, subject);
    } catch (e) {
      console.error(`[verify] ${reg.registry}:`, e);
      r = { status: "error", message: "Kontrolu se nepodařilo provést." };
    }
    // Technické selhání placené kontroly → vrať podíl ceny.
    if (price > 0 && userId && (r.status === "error" || r.status === "unavailable")) {
      await admin.rpc("refund_credits", { p_user: userId, p_amount: price, p_reason: "refund", p_payment: null });
    }
    r.price = price;
    results[reg.registry] = r;
  }

  const riskScore = computeRiskScore(results);
  await persist(admin, userId, subject, level, riskScore, results, requestId, subjectName);

  return json({ mode: MODE, level, risk_score: riskScore, results: toVerdicts(results), subject_name: subjectName, budget });
});
