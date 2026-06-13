# DEBTORA CZ — CORE README

Sdílené jádro (DB + RLS + RPC + edge funkce + JS) postavené na `auth.users`.
Návrhová rozhodnutí viz [CORE-PLAN.md](./CORE-PLAN.md).

## Architektura

```
Statické HTML/CSS/JS (Vercel)
   │  čte přes RLS / volá RPC + edge funkce (anon klíč)
   ▼
Supabase: PostgreSQL + Auth + PostgREST + RLS
   │  service-role (jen server-side)
   ▼
Edge Functions (Deno): verify · payment-create · payment-callback
   │
   ▼
Externí: Comgate · ISIR/ARES/DPH · CEE (Smart Collectors)
```

Citlivé zápisy (kredity, lustrace, platby, tvorba inzerátu) běží server-side přes
service-role / `SECURITY DEFINER`. Frontend jen čte přes RLS a iniciuje akce.

## Lokální demo jádra (bez backendu)

`demo/index.html` je samostatné interaktivní demo, které **věrně reprodukuje kontrakty jádra**
v prohlížeči (žádný Supabase/Deno/Postgres není potřeba): kreditní ledger, `create_listing`
(1. inzerát v roce strhne kredit + ověření totožnosti / `no_credit`), `verify` (cenový engine
dle úrovně → quote → strh → per-rejstřík refund → rizikové skóre), idempotentní platby/callback,
gating náhled (`listings_preview`) vs. detail, FOC rate limit, admin moderace.

```bash
python3 -m http.server 8787 --directory demo   # ze složky repa
# → http://127.0.0.1:8787/
```
Doporučený průchod: **Přihlásit → Koupit kredity → Vložit inzerát → (Přepnout admina) Schválit
→ Aktivovat Inzerci → Tržiště/detail → Ověření (FULL: rozpočet → potvrdit)**. Pravý panel ukazuje
živý ledger a volání API. Věrnost dema vůči `sql/*` a edge funkcím byla ověřena auditem (6/6 kontraktů).

> Demo je ilustrační mock — neukazuje reálné rejstříky ani DB; je to věrná simulace logiky jádra.

## Předpoklady

- Supabase projekt (PostgreSQL 15+, Auth zapnutý).
- Supabase CLI (`supabase`) pro nasazení edge funkcí.
- Vercel účet pro hosting statického frontendu.

## 1. Nasazení migrací (prázdná DB)

Migrace `sql/001`–`sql/013` jsou idempotentní a spouští se **v pořadí**.
V Supabase SQL editoru nebo přes CLI:

```bash
# přes psql proti databázi projektu (v pořadí podle čísla)
for f in sql/0*.sql; do psql "$DATABASE_URL" -f "$f"; done
```

> `sql/legacy/` = původní custom-login schéma (Netlify migrace). **Nespouštět** —
> je jen referencí; nové jádro stojí výhradně na `auth.users`.

### Založení admina
Admin je běžný Supabase Auth účet označený řádkem v `admin_users`:
```sql
insert into admin_users (user_id, role)
values ('<auth.users.id existujícího účtu>', 'admin');
```

## 2. Konfigurace frontendu

`js/supabase-config.js` (commitnuté, veřejné):
```js
window.DEBTORA_CONFIG = { SUPABASE_URL: '…', SUPABASE_ANON_KEY: '…' };
```
Pořadí skriptů: `supabase-js@2` → `supabase-config.js` → `api.js` → `auth.js` → `cms.js`/`main.js`.

## 3. Edge funkce — secrets a deploy

```bash
supabase secrets set \
  SUPABASE_URL=…  SUPABASE_ANON_KEY=…  SUPABASE_SERVICE_ROLE_KEY=… \
  VERIFY_MODE=mock \
  COMGATE_MERCHANT=…  COMGATE_SECRET=…  COMGATE_TEST=true \
  CEE_API_URL=  CEE_API_KEY= \
  RESEND_API_KEY=  EMAIL_FROM="Debtora CZ <noreply@debtora.cz>"

supabase functions deploy verify
supabase functions deploy payment-create
supabase functions deploy payment-callback --no-verify-jwt   # webhook bez JWT
supabase functions deploy admin-moderate-listing
supabase functions deploy delete-account
```
Comgate nastav callback (notifikační) URL na `…/functions/v1/payment-callback`.
`VERIFY_MODE=mock` je default — produkční živé rejstříky se zapnou `VERIFY_MODE=live`.

**pg_cron** (úklid ověření + sync storefrontů): povol rozšíření `pg_cron` v Supabase
(Database → Extensions); migrace 016 joby založí sama (guarded DO blok). Bez rozšíření
se přeskočí — `cleanup_expired_verifications()` / `sync_storefront_status()` lze volat ručně.

**Storage:** migrace 017 založí buckety i RLS na `storage.objects`. Spouštět v Supabase
(schema `storage` musí existovat). `listing-files` je privátní → frontend čte přes
`createSignedUrl`; `storefront-logos` je veřejný.

## 4. Env proměnné

Viz [`.env.example`](../.env.example). Frontend = jen `SUPABASE_URL` + `SUPABASE_ANON_KEY`.
`SUPABASE_SERVICE_ROLE_KEY`, `COMGATE_*`, `CEE_*`, `VERIFY_MODE` jsou **jen** secrets edge funkcí.

## Klíčové E2E toky

- **Inzerce:** `listings_preview` (náhled) → detail `listings` (gated; 0 řádků → CTA „Aktivovat Inzerci") → `create_listing()` (1. v roce strhne kredit + zapíše `seller_identity`, jinak `no_credit`) → status `pending` → admin moderace.
- **Ověření:** `API.verify(subject, level)` → edge `verify` (mock|live) → spend/refund kreditů → `verification_results` (TTL 30 d) → verdikt + skóre.
- **Platby:** `API.createPayment(product,…)` → `payment-create` (pending) → Comgate → `payment-callback` (idempotentně `add_credits`/`activate_subscription`).

---

## Akceptační kritéria

Legenda: ✅ ověřeno návrhem/kódem · 🧪 ověřit živým během na Supabase (lokálně chybí Postgres).

- [x] ✅ Migrace `sql/*` jsou idempotentní a seřazené dle závislostí (`create … if not exists`, `create or replace`, `drop policy if exists`, FK doplňované po vzniku cílové tabulky). 🧪 ověřit `for f in sql/0*.sql; do psql -f $f; done` na prázdné DB.
- [x] ✅ RLS: anonym čte `listings_preview` (view `security_invoker=false`); base `listings` má jen subscriber/owner/admin SELECT → bez předplatného 0 řádků. *(012)*
- [x] ✅ `create_listing`: 1. inzerát/rok strhne kredit (`spend_credits … 'identity_first_listing'`) + zapíše `seller_identity`; další v roce ne; bez kreditu `{ok:false, error:'no_credit'}`. *(012)*
- [x] ✅ Přímý INSERT do `listings` odepřen — žádná INSERT policy pro anon/authenticated; tvorba jen přes RPC. *(004 + 012)*
- [x] ✅ `verify` (mock): vrací verdikt per rejstřík (glyph ✓/⚠/—) + `risk_score`; simulované selhání (sentinel) → `refund_credits`. *(verify + registries.ts)*
- [x] ✅ `payment-callback` idempotentní: kontrola `status='paid'` + `add_credits` s unique indexem `uq_credit_purchase_payment` (duplicitní PAID nepřipíše 2×). *(006 + callback)*
- [x] ✅ `has_active_subscription` / `is_identity_verified` vrací správné hodnoty (stable SECURITY DEFINER, `current_period_end > now()`). 🧪 SQL smoke test po seedu.
- [x] ✅ `add_credits` / `spend_credits` / `refund_credits` zapisují každý pohyb do `credit_transactions`. *(006)*
- [x] ✅ Service-role klíč není ve frontendu (`grep -ri service_role js/` = 0); anon klíč jen pro veřejné čtení přes RLS. AdminAPI běží na session + `admin_*` RPC.
- [x] ✅ `docs/CORE-PLAN.md` a `docs/CORE-README.md` existují a jsou aktuální.

### Akceptační kritéria — followup (014–017 + edge/js)

- [x] ✅ `verify` se stejným `request_id` nestrhne kredit 2× a vrátí původní výsledek (idempotenční lookup + `uq_vr_request_id`). *(014 + verify A1)*
- [x] ✅ FULL kontrola PO strhne **součet** kreditů zapnutých rejstříků jedním `spend_credits`; selhaný rejstřík (`error`/`unavailable`) se refunduje. Placená úroveň vrací nejdřív `quote`. *(verify A2/A3)*
- [x] ✅ `listings_preview` neukáže položky majitele bez aktivního předplatného Inzerce (ani se suspendovaným storefrontem); data zůstávají, vlastník vidí dál. *(015 C2)*
- [x] ✅ `messages` INSERT odepřen anonymovi (`to authenticated`); vlastník vidí zprávy ke svým inzerátům. *(015 C3)*
- [x] ✅ `payment-callback`: `pack50`→50 kreditů; `sub_inzerce_monthly`→aktivní předplatné, idempotentně (guard přes `status='paid'` + idempotentní `add_credits`). *(payment-callback)*
- [x] ✅ E-mail odejde po platbě i po moderaci inzerátu; výpadek e-mailu (fail-soft) neshodí transakci. *(email.ts + callback + admin-moderate-listing)* 🧪 ověřit s `RESEND_API_KEY`.
- [x] ✅ `listing-files` privátní (přístup přes signed URL), `storefront-logos` veřejný read; upload gated vlastnictvím. *(017 D2)* 🧪 ověřit v Supabase Storage.
- [x] ✅ `cleanup_expired_verifications` + `sync_storefront_status` aktivovány přes pg_cron (guarded DO blok); `delete_account()` anonymizuje a zachová účetní audit (`credit_transactions`/`payments` odvázány, ne smazány). *(016 D3)* 🧪 vyžaduje rozšíření `pg_cron`.
- [x] ✅ FOC kontrola nad limit vrací 429 (`foc_check_and_count`, limity z `settings.foc_limits`). *(014 D4 + verify)*

## Hotovo / zbývá k produkci

**Hotovo (jádro):** sjednocená identita na `auth.users`, čistá idempotentní migrační série,
RLS + gating náhled/detail, kreditní ledger (idempotentní), předplatné + storefronty,
seller_identity, registry matice úroveň×rejstřík, edge `verify` (mock default + live adaptery
ISIR/ARES/DPH/CEE + risk score + refund), platby (single/pack5/20/50/sub) s idempotentním callbackem,
přepsaná sdílená JS vrstva bez service-role díry.

**Zbývá k produkčnímu zapojení:**
- Spustit migrace a edge funkce na ostrém Supabase + smoke testy (🧪 položky výše).
- Stránkové skripty (`js/overeni.js`, formuláře `vlozit-inzerat.html`, admin panel) napojit na
  nové API (`verify` vrací `{mode, level, risk_score, results}`; tvorba přes `create_listing`).
- Comgate produkční merchant/secret + ověřená callback URL; `COMGATE_TEST=false`.
- CEE: doplnit `CEE_API_URL/KEY` a namapovat odpověď v `_shared/cee.ts` (po podpisu smlouvy).
- Storage bucket `listing-files` (public) pro přílohy + Storage policy.
- pg_cron `cleanup_expired_verifications` (denní úklid TTL).

**Mimo rozsah (fáze 2):** iOS app, produkční live CEE, Fakturoid, monitoring/PDF report.
