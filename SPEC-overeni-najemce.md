# SPEC — Modul „Ověření nájemce" (DEBTORA CZ)

Služba pro pronajímatele: kontrola potenciálního nájemce (FO i PO) ve veřejných a placených rejstřících. Cíl: snížit riziko pronájmu neplatiči.

---

## 1. Pokryté rejstříky

### Zdarma (veřejná API) — free tier

| Rejstřík | Co zjistí | API | Vstup |
|---|---|---|---|
| **ISIR** — Insolvenční rejstřík (justice.cz) | Probíhající/ukončená insolvence, oddlužení, konkurs | ✅ ověřeno: SOAP WS `https://isir.justice.cz:8443/isir_cuzk_ws/IsirWsCuzkService`, zdarma, bez registrace | FO: RČ **nebo** jméno + příjmení + datum narození; PO: IČO |
| **ARES** (ares.gov.cz) | Existence subjektu, likvidace, zánik; bonus: příznaky insolvence (`stavZdrojeIr`) a evidence úpadců | ✅ ověřeno živým dotazem: REST `https://ares.gov.cz/ekonomicke-subjekty-v-be/rest/ekonomicke-subjekty/{ico}`, zdarma | IČO |
| **Nespolehlivý plátce DPH** (MFČR) | Status nespolehlivého plátce | SOAP WS `adisrws.mfcr.cz` (rozhraniCRPDPH), zdarma | DIČ (=IČO s prefixem CZ) |

### Placené — per request

| Rejstřík | Co zjistí | Přístup | Cena (nákladová) |
|---|---|---|---|
| **CEE** — Centrální evidence exekucí (Exekutorská komora ČR) | Aktivní exekuce, počet, spisové značky | **Smart Collectors s.r.o.** — API agregátor (nabídka viz `Rejtřiky/SmartCollectors_CEE_API_obchodni_material.pdf`) | **17,50 Kč / dotaz** (17 Kč nad 2 000 dotazů/měs.) |
| **CEÚ / dražby, katastr** (volitelné, fáze 2) | Nařízené dražby, zástavy | ČÚZK API (placené WSDP) | dle sazebníku |

### Nedostupné pro web (jen zmínit v UI jako "nepokrýváme")
SOLUS, BRKI/NRKI — pouze pro členy sdružení, nelze integrovat.

## 2. Business model

- **Zdarma:** ISIR + ARES + DPH — lead magnet, vyžaduje registraci (sběr kontaktů).
- **Placené:** kontrola CEE — náklad 17,50 Kč/dotaz (Smart Collectors). Ceník pro klienty:
  - jednorázová kontrola **122 Kč** (bez účtu, povinný e-mail — faktura + report)
  - balíček **5 kontrol / 575 Kč** (115 Kč/ks), **20 kontrol / 1 880 Kč** (94 Kč/ks) — vyžaduje účet, kredity
  - Cenová strategie: **5 % pod trhem** (Bezrealitky a Rentivo prodávají komplexní prověření za 129 Kč, Rentivo s Bank iD za 199 Kč — průzkum červen 2026). Marže při nákladu 17,50 Kč: 81–86 %.
- Break-even: jednotky dotazů měsíčně; objemový tarif 17 Kč od 2 000 dotazů/měs.

### Platby — Comgate (✅ implementováno)

- **Brána:** Comgate, protokol v1.0 (`/v1.0/create` → redirect na bránu; server-to-server notifikace → vždy zpětně ověřeno přes `/v1.0/status`). Karty, Apple/Google Pay, bankovní tlačítka.
- **E-mail povinný u každé platby** — fakturace a doručení reportu; u balíčku navíc přihlášený účet.
- **Flow jednorázové platby:** zákazník u zamčené CEE karty klikne Odemknout → modal (produkt + e-mail) → `payment-create` založí platbu (uloží subjekt lustrace) → redirect na Comgate → notifikace do `payment-callback` → po PAID se automaticky provede CEE kontrola a uloží výsledek → frontend po návratu polluje stav přes token a zobrazí výsledek.
- **Flow balíčku:** po zaplacení `payment-callback` připíše kredity (`add_credits`). Přihlášený uživatel pak v modalu použije „1 kredit" → `verify` se `spendCredit:true` (při selhání kontroly se kredit vrací).
- **Bezpečnost:** notifikaci nevěříme — stav i částka se ověřují u Comgate; idempotence (opakovaná notifikace nic nepřipíše dvakrát); anonymní zákazník se na výsledek ptá jen tajným tokenem.
- **Nastavení v Comgate portálu:** povolit IP / nastavit notifikační URL na `https://<projekt>.supabase.co/functions/v1/payment-callback` a návratové URL `https://<doména>/overeni-najemce.html?refId=${refId}&status=PAID|CANCELLED|PENDING`.
- **Fakturace:** e-mail se ukládá k platbě (`payments.email`, sloupec `invoice_no` připraven) — vystavování faktur napojit na Fakturoid/iDoklad API (fáze 2), do té doby ručně z přehledu plateb.
- Env: `COMGATE_MERCHANT`, `COMGATE_SECRET`, `COMGATE_TEST=true|false`.

### Dodavatel CEE — Smart Collectors s.r.o. (obchodní nabídka, červen 2026)

- 17,50 Kč/úspěšný dotaz; 17,00 Kč při >2 000 dotazů/měs. (aplikuje se na celý objem); bez paušálu
- Online i dávkové dotazování (vhodné pro budoucí monitoring portfolia nájemců)
- Postup: smlouva (vč. zpracování os. údajů) → vystavení API → technická specifikace API bude dodána samostatně
- Nabízejí také insolvenční a ARES monitoring — zvážit jako alternativu k vlastním adaptérům ISIR/ARES

### Bank iD — ověřená identita nájemce (premium tier)

Bank iD **nenahrazuje rejstříky** (insolvence/exekuce nekontroluje), ale řeší dva klíčové problémy: přesnost vstupních dat a GDPR souhlas.

| Služba | Co vrátí | Cena (bez DPH) |
|---|---|---|
| CONNECT | jméno, příjmení, datum narození, telefon, e-mail | 10 Kč / uživatel / rok |
| **IDENTIFY** ← naše volba | + adresy, **rodné číslo**, bankovní účty | 20 Kč / uživatel / rok |
| IDENTIFY PLUS | + doklad totožnosti, místo narození, právní status | 60 Kč / uživatel / rok |
| SIGN | el. podpis až 10 dokumentů najednou (jen s CONNECT/IDENTIFY) | 5 Kč / podpis |

Přínosy: (a) nájemce se ověří sám bankovnictvím → **garantovaná identita, žádné překlepy ani lhaní o datu narození**; (b) získáme **RČ se souhlasem nositele** → stoprocentně přesný dotaz do ISIR i CEE; (c) prokazatelný souhlas s lustrací = čistý právní titul; (d) upsell SIGN — online podpis nájemní smlouvy hned po ověření.

Integrace: standardní **OIDC/OAuth2** (developer.bankid.cz). Vyžaduje smlouvu s Bank iD, a.s. a schválení aplikace. Ceník v10 účinný od 1. 1. 2026.

#### Flow „Ověřený nájemce" (pozvánkový model)

```
Pronajímatel                     Nájemce                       Debtora backend
────────────                     ───────                       ───────────────
1. vytvoří pozvánku ──────────►  2. otevře link /overeni/t/{token}
   (e-mail nájemce)                 souhlas s lustrací
                                 3. klik „Ověřit přes Bank iD"
                                    ── OIDC redirect ────────►  4. callback bankid-callback:
                                                                   výměna code→token, načtení
                                                                   profilu (jméno, dat. nar., RČ)
                                                                5. spustí verify (ISIR+CEE dle RČ)
6. notifikace + report  ◄──────  7. nájemce vidí svůj výsledek ◄─  uložení s vazbou na pozvánku
```

Obrazovky k doplnění do frontendu (fáze 3):
1. **Pozvánka nájemci** (v účtu pronajímatele) — e-mail nájemce + text pozvánky, stav pozvánek (čeká / ověřeno / expirováno, platnost 7 dní).
2. **Landing pro nájemce** `/overeni-najemce-pozvanka.html?t={token}` — kdo žádá, co se bude kontrolovat, souhlas, tlačítko Bank iD.
3. **Výsledek pro nájemce** — jeho vlastní report + možnost sdílet s dalšími pronajímateli (re-use 30 dní).
4. **Report pronajímatele** — badge „Identita ověřena Bank iD" + výsledky rejstříků.

Ekonomika premium kontroly: Bank iD IDENTIFY 20 Kč + CEE 17,50 Kč ≈ **37,50 Kč náklad** → prodejní cena **189 Kč** (5 % pod Rentivem s Bank iD za 199 Kč; marže ~80 %). Nájemcův report lze 30 dní sdílet opakovaně → druhý a další pronajímatel = čistá marže. Konkurence (Rentivo) model validovala — naše diferenciace: nižší cena, synergie s tržištěm Debtora (pronajímatel s neplatičem = potenciální prodejce pohledávky) a výhledově monitoring nájemce po dobu nájmu.

## 3. Právní rámec (GDPR)

- Právní titul: **oprávněný zájem** pronajímatele (posouzení bonity smluvního partnera). Doporučeno: checkbox potvrzení účelu + ideálně souhlas nájemce.
- **Rodné číslo**: zpracovávat jen se souhlasem nositele (z. 133/2000 Sb. §13c) — v UI volitelné pole s upozorněním; primárně jméno + datum narození.
- **Bank iD flow problém řeší elegantně:** nájemce uděluje souhlas sám v rámci OIDC autorizace (scope `birthnumber`) a na landing page pozvánky — souhlas je logovaný (kdy, jaký text, jaká IP). RČ uchováváme jen po dobu zpracování dotazu, do DB ukládáme pouze hash pro deduplikaci.
- Neukládat výsledky dotazů déle, než je nutné (TTL 30 dní), audit log dotazů (kdo, kdy, koho), uvést v ochraně soukromí.
- Výstup označit „informativní výpis, není úředním dokumentem".

## 4. Architektura

```
overeni-najemce.html ──────────────► Edge Function "verify"   ✅ hotovo
(samoobslužná kontrola)                ├─ adapter ISIR (SOAP → JSON)
                                       ├─ adapter ARES (REST)
                                       ├─ adapter DPH (WS)
                                       └─ adapter CEE (Smart Collectors, env flag)

overeni-najemce-pozvanka.html ─────► Edge Function "bankid-callback"   ← fáze 3
(pozvánkový flow s Bank iD)            ├─ OIDC: code → access_token → /profile
                                       ├─ uložení ověřené identity (RČ jen transientně)
                                       └─ interní volání verify s ověřeným RČ

tabulky: verification_requests, verification_results (TTL),
         user_credits, tenant_invitations (fáze 3)
```

- Všechna volání rejstříků **výhradně server-side** (CORS, API klíče, audit).
- Frontend volá jediný endpoint; `js/overeni.js` má adapter s **mock režimem** (`VERIFY_CONFIG.mode = 'mock' | 'live'`), takže UI je plně testovatelné už teď.

## 5. UI (tato fáze — hotovo v `overeni-najemce.html`)

1. Hero + důvěryhodnostní prvky (co kontrolujeme, zdroje).
2. Formulář: přepínač **Fyzická osoba / Firma (IČO)**; FO: jméno, příjmení, datum narození, volitelně RČ; PO: IČO. GDPR checkbox.
3. Výsledky: karta na každý rejstřík — stavy `✓ nenalezen` / `⚠ nalezen záznam` / `🔒 placená kontrola` (CTA odemknout za 122 Kč).
4. Souhrnné skóre rizika (nízké / střední / vysoké) — jen z dostupných kontrol.
5. CTA na registraci / dokoupení kompletního reportu.

## 6. DB schéma (fáze 2 — návrh)

```sql
create table verification_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users,
  subject_type text check (subject_type in ('fo','po')),
  subject_name text, subject_birthdate date, subject_ico text,
  created_at timestamptz default now()
);
create table verification_results (
  id uuid primary key default gen_random_uuid(),
  request_id uuid references verification_requests,
  registry text,           -- isir | ares | dph | cee
  status text,             -- clear | found | error
  payload jsonb,
  expires_at timestamptz   -- TTL 30 dní
);
create table user_credits (
  user_id uuid primary key references auth.users,
  balance int default 0
);

-- Fáze 3 — Bank iD pozvánkový flow
create table tenant_invitations (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null references auth.users,
  tenant_email text not null,
  token text not null unique,            -- náhodný, v URL pozvánky
  status text not null default 'pending' -- pending | verified | expired | declined
    check (status in ('pending','verified','expired','declined')),
  bankid_sub text,                        -- stabilní Bank iD identifikátor uživatele
  verified_name text,                     -- ověřené jméno z Bank iD
  verified_birthdate date,
  rc_hash text,                           -- hash RČ pro deduplikaci (RČ samotné neukládáme)
  consent_log jsonb,                      -- kdy, text souhlasu, IP
  request_id uuid references verification_requests,  -- výsledná lustrace
  expires_at timestamptz not null default now() + interval '7 days',
  created_at timestamptz not null default now()
);
```

## 7. Roadmap

1. ✅ Frontend (`overeni-najemce.html`, `js/overeni.js` mock)
2. ✅ Edge Function `supabase/functions/verify/index.ts` — živé adaptéry ISIR, ARES, DPH; CEE za env flagem (`CEE_API_URL`, `CEE_API_KEY`); volitelně `REQUIRE_AUTH=true`
3. ✅ Migrace `sql/007_verification.sql` — audit, výsledky s TTL, kredity, RLS
4. Podpis smlouvy Smart Collectors → doplnit mapování CEE adapteru dle jejich technické specifikace
5. **Bank iD (fáze 3):** smlouva s Bank iD a.s. + registrace aplikace na developer.bankid.cz → Edge Function `bankid-callback` (OIDC), migrace `tenant_invitations`, stránky pozvánkového flow, e-mail notifikace
6. Kreditní systém + platby (Stripe/GoPay), PDF export, historie v účtu, SIGN — podpis nájemní smlouvy

## 8. Nasazení

```bash
# 1. DB migrace (SQL editor nebo supabase db push)
#    sql/007_verification.sql, sql/008_payments.sql
# 2. Env proměnné (Dashboard → Edge Functions → Secrets)
#    COMGATE_MERCHANT, COMGATE_SECRET, COMGATE_TEST=true
#    (později CEE_API_URL, CEE_API_KEY)
# 3. Deploy funkcí
supabase functions deploy verify
supabase functions deploy payment-create
supabase functions deploy payment-callback --no-verify-jwt
# 4. Comgate portál: notifikační URL + návratové URL (viz sekce Platby)
# 5. frontend: js/overeni.js → VERIFY_CONFIG.mode = 'live'
```
