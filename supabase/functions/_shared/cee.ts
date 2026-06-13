/* Sdílený adapter CEE (Smart Collectors) + společné typy.
   Používají funkce `verify` a `payment-callback`. */

export interface RegistryResult {
  status: "clear" | "found" | "locked" | "error" | "unavailable" | "skipped";
  detail?: string;
  message?: string;
  payload?: unknown;
  /** Cena v kreditech u placené kontroly (stav `locked`) — z registry_config. */
  price?: number;
}

export interface SubjectFO {
  type: "fo";
  firstName: string;
  lastName: string;
  birthDate: string; // YYYY-MM-DD
  rc?: string | null;
}
export interface SubjectPO {
  type: "po";
  ico: string;
}
export type Subject = SubjectFO | SubjectPO;

export const TIMEOUT_MS = 10_000;

export async function fetchWithTimeout(url: string, init: RequestInit): Promise<Response> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    return await fetch(url, { ...init, signal: ctrl.signal });
  } finally {
    clearTimeout(t);
  }
}

// Smart Collectors API — kontrakt bude upřesněn po podpisu smlouvy.
// Bez CEE_API_URL/KEY vrací 'locked'.
export async function checkCee(subject: Subject): Promise<RegistryResult> {
  const url = Deno.env.get("CEE_API_URL");
  const key = Deno.env.get("CEE_API_KEY");
  if (!url || !key) return { status: "locked" };

  // TODO: přizpůsobit dle technické specifikace Smart Collectors
  const body =
    subject.type === "po"
      ? { ico: subject.ico }
      : {
          firstName: subject.firstName,
          lastName: subject.lastName,
          birthDate: subject.birthDate,
          rc: subject.rc ?? undefined,
        };

  const res = await fetchWithTimeout(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`CEE HTTP ${res.status}`);
  const data = await res.json();

  // TODO: mapování dle skutečné odpovědi; očekáváme { executions: [...] }
  const count = Array.isArray(data.executions) ? data.executions.length : 0;
  if (count === 0) return { status: "clear", detail: "V centrální evidenci exekucí nebyl nalezen žádný záznam.", payload: data };
  return { status: "found", detail: `Nalezeno exekucí: ${count}`, payload: data };
}

export function validateSubject(s: unknown): Subject | null {
  if (!s || typeof s !== "object") return null;
  const o = s as Record<string, unknown>;
  if (o.type === "po") {
    const ico = String(o.ico ?? "").replace(/\D/g, "");
    return ico.length === 8 ? { type: "po", ico } : null;
  }
  if (o.type === "fo") {
    const firstName = String(o.firstName ?? "").trim();
    const lastName = String(o.lastName ?? "").trim();
    const birthDate = String(o.birthDate ?? "");
    const rc = o.rc ? String(o.rc).replace(/\D/g, "") : null;
    if (!firstName || !lastName || !/^\d{4}-\d{2}-\d{2}$/.test(birthDate)) return null;
    if (rc && (rc.length < 9 || rc.length > 10)) return null;
    return { type: "fo", firstName, lastName, birthDate, rc };
  }
  return null;
}
