/* ═══════════════════════════════════════════════════════
   DEBTORA CZ — sdílená logika rejstříků
   • mock adaptery (deterministické, pro testy a default běh),
   • matice úroveň × rejstřík,
   • výpočet rizikového skóre a verdiktu.
   Používá edge funkce `verify`.
   ═══════════════════════════════════════════════════════ */

import type { RegistryResult, Subject } from "./cee.ts";

export type Level = "foc_nologin" | "foc_login" | "basic" | "medium" | "full";
export const LEVELS: Level[] = ["foc_nologin", "foc_login", "basic", "medium", "full"];

/** Sloupec dostupnosti v registry_config pro danou úroveň. */
export function levelColumn(level: Level): string {
  return `lvl_${level}`;
}

/** Deterministický pseudo-hash subjektu (stabilní napříč voláními). */
function subjectSeed(subject: Subject): number {
  const s = subject.type === "po"
    ? `po:${subject.ico}`
    : `fo:${subject.firstName}|${subject.lastName}|${subject.birthDate}`;
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return h;
}

/** Sentinel pro simulaci selhání kontroly (test refundu kreditu). */
export function isFailureSentinel(subject: Subject): boolean {
  if (subject.type === "po") return subject.ico === "00000000";
  return /selhani|fail/i.test(`${subject.firstName} ${subject.lastName}`);
}

/** Váha rizika pro nález v daném rejstříku (0–100 agregace). */
const RISK_WEIGHT: Record<string, number> = {
  cee: 45, isir: 35, dph: 25, atp: 20, vozidla: 10, katastr: 10, ares: 15, bankid: 0,
};

/**
 * Mock adapter — deterministický výsledek. Bez volání reálných rejstříků.
 * Pravidlo: ~1 ze 4 subjektů má v „rizikovém" rejstříku nález.
 */
export function runRegistryMock(registry: string, subject: Subject): RegistryResult {
  if (isFailureSentinel(subject)) {
    return { status: "error", message: "Mock: simulované selhání kontroly." };
  }
  const seed = subjectSeed(subject);
  const hit = (seed >> (registry.length % 8)) % 4 === 0; // deterministické „nalezeno"

  switch (registry) {
    case "ares":
      return { status: "clear", detail: "Mock ARES: subjekt existuje a je aktivní." };
    case "isir":
      return hit
        ? { status: "found", detail: "Mock ISIR: aktivní insolvenční řízení.", payload: { count: 1 } }
        : { status: "clear", detail: "Mock ISIR: bez záznamu." };
    case "dph":
      return hit
        ? { status: "found", detail: "Mock DPH: veden jako nespolehlivý plátce." }
        : { status: "clear", detail: "Mock DPH: spolehlivý plátce." };
    case "cee":
      return hit
        ? { status: "found", detail: "Mock CEE: nalezeny 2 exekuce.", payload: { count: 2 } }
        : { status: "clear", detail: "Mock CEE: bez exekucí." };
    case "katastr":
      return { status: "clear", detail: "Mock Katastr: 1 nemovitost, bez zástav." };
    case "vozidla":
      return { status: "clear", detail: "Mock Registr vozidel: bez záznamu." };
    case "atp":
      return { status: "clear", detail: "Mock ATP: bez dalších záznamů." };
    case "bankid":
      return { status: "clear", detail: "Mock Bank iD: totožnost ověřena." };
    default:
      return { status: "unavailable", message: "Mock: neznámý rejstřík." };
  }
}

/** Verdikt-glyph dle spec (✓ nenalezen / ⚠ nalezen / — nekontrolováno). */
export function verdictGlyph(status: RegistryResult["status"]): string {
  switch (status) {
    case "clear": return "✓";
    case "found": return "⚠";
    case "error": return "✕";
    case "locked": return "🔒";
    default: return "—"; // unavailable | skipped
  }
}

/** Agregované rizikové skóre 0–100 z výsledků per rejstřík. */
export function computeRiskScore(results: Record<string, RegistryResult>): number {
  let score = 0;
  for (const [registry, r] of Object.entries(results)) {
    if (r.status === "found") score += RISK_WEIGHT[registry] ?? 10;
  }
  return Math.min(100, score);
}
