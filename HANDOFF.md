# HANDOFF — Debtora CZ

> Předávací dokument pro pokračování práce / po kompakci kontextu.
> **Na startu nové session přečti tento soubor jako první.**
> Naposledy aktualizováno: 2026-06-14.

## Projekt & git
- **Projekt:** Debtora CZ — marketplace distressed aktiv (pohledávky / nemovitosti / OTC)
  + modul **ověření protistrany** (lustrace v rejstřících) s kreditním a platebním systémem.
- **Repo:** `/Users/jirihochman/debtora-cz` · remote `github.com/ba-netizen/debtora-cz`
- **Větev:** `feat/core-rebuild` (**29 commitů před `main`, NEMERGOVÁNO**). `main` má starý kód.
- **Poslední commit:** `fbb65b1` — *verify: VIES unavailable variant + result legend/risk label*
- **Produkce:** https://debtora-cz.vercel.app (Vercel, team „ba-netizen's projects", projekt `debtora-cz`).
  Deploy = `npx vercel --prod` z lokální složky (git **není** napojen → nasazuje pracovní strom
  větve `feat/core-rebuild`, ne `main`).
- **Supabase:** projekt `Debtora-cz`, ref **`wefucmmkbspyaodofdki`** (eu-central-1).

## Co je v této session hotové
- **Kompletní přestavba jádra na `auth.users`** (sjednocení identity; legacy custom-login odložen do `sql/legacy/`).
- **DB:** čistá idempotentní série `sql/001–019` — **všechny aplikované na živou DB** (přes Supabase MCP), public schéma resetováno, CMS obsah + firemní settings zachovány.
- **5 edge funkcí** nasazeno (ACTIVE): `verify` (v6), `payment-create`, `payment-callback` (verify_jwt=false), `admin-moderate-listing`, `delete-account`.
- **Frontend přepsán** na Supabase Auth + nové API, **moderní světlý design** (sjednocený s `/demo`), nasazen na produkci.
- **Ověřovač protistrany** v hero landing page: 14 rejstříků, **reálná data** (ARES/ISIR/DPH/VIES/RŽP/CEÚ/sbírka listin), FO i PO, nepovinné RČ, rizikové skóre, legenda výsledků.
- **Admin** přepsán na Supabase Auth + `is_admin` (žádný service-role klíč ve frontendu).
  **Sjednocená sekce „Ověřování"** (3 sub-taby): *Rozsah služeb* (matice rejstřík×úroveň + cena v kr.),
  *Cena kreditů* (základní cena/kredit + override balíčků + ceny služeb), *Uživatelé* (KYC, ruční ± kreditů,
  historie transakcí + ověření, správa předplatného inzerce). Staré sidebar položky Rejstříky a Uživatelé sloučeny sem.
- Admin účet: **info@debtora.cz** (řádek v `admin_users`, role admin).

## Klíčové soubory (jen finální stav)
| Soubor | Účel | Stav |
|---|---|---|
| `sql/001–020` | Migrační série na `auth.users` (schéma+RLS+RPC) | finální, **applied** |
| `sql/020_admin_verification.sql` | Admin RPC: `admin_adjust_credits`, `admin_set_subscription`, `admin_get_user_overview` + settings `credit_base_price_czk` | finální, **applied** |
| `sql/legacy/` | Původní custom-login schéma | reference, **nespouštět** |
| `supabase/functions/verify/index.ts` | Ověření v rejstřících (14), mock\|live, cenový engine, idempotence, rate-limit | finální, **deployed v6** |
| `supabase/functions/_shared/cee.ts` | Typy `Subject`/`RegistryResult`, `validateSubject`, CEE adapter | finální |
| `supabase/functions/_shared/registries.ts` | Matice úroveň×rejstřík, mock adaptery, risk weights, verdikt glyph | finální |
| `supabase/functions/_shared/email.ts` | Resend e-maily (fail-soft) | finální |
| `supabase/functions/payment-create/index.ts` | Comgate objednávka (single/pack5/20/50/sub) | finální, deployed |
| `supabase/functions/payment-callback/index.ts` | Webhook, idempotentní add_credits/activate_subscription | finální, deployed |
| `supabase/functions/admin-moderate-listing/index.ts` | Moderace inzerátu + e-mail majiteli | finální, deployed |
| `supabase/functions/delete-account/index.ts` | GDPR anonymizace + smazání auth.users | finální, deployed |
| `js/api.js` | API klient (preview vs detail, create_listing, verify, platby, kredity) | finální |
| `js/auth.js` | Supabase Auth (signUp/signIn/session/profil) | finální |
| `js/cms.js`, `js/main.js`, `js/supabase-config.js` | CMS, nav, config (URL+anon) | finální |
| `index.html` | Landing + hero **ověřovač** (IČO / FO se jménem+datem+RČ) | finální |
| `trziste.html` / `inzerat.html` / `vlozit-inzerat.html` | Tržiště (preview+filtr) / detail (gated) / tvorba (RPC) | finální |
| `prihlaseni.html` / `registrace.html` / `ucet.html` | Auth stránky (async Auth) | finální |
| `admin.html` | Admin panel (Auth+is_admin, moderace, rejstříky+úrovně) | finální |
| `css/style.css` | Moderní světlý theme (modrý akcent, sans, karty) | finální |
| `demo/index.html` | Samostatné in-browser demo jádra | finální |
| `docs/CORE-PLAN.md`, `CORE-README.md`, `FINALIZATION.md` | Návrh, run/deploy, otevřené body | finální |
| `vercel.json` | cleanUrls + revalidace cache pro css/js | finální |
| `js/overeni.js`, `overeni-najemce.html` | **Legacy** stránková logika ověření (untracked) | **NEnapojeno na nové API** |

## Architektonická rozhodnutí (proč)
- **Identita výhradně na `auth.users`** — sjednocení; legacy `password_hash` login zrušen (bezpečnost, jeden zdroj pravdy).
- **Admin = příznakovaný auth účet** (`admin_users` + `is_admin(auth.uid())`), **NIKDY service-role klíč ve frontendu** (původní `AdminAPI` vracel service-role klíč do prohlížeče → díra; opraveno).
- **Marketing × citlivé sloupce** odděleny projekcí: veřejný `listings_preview` (view, obchází RLS) vs. gated base `listings`.
- **Tvorba inzerátu jen přes RPC `create_listing`** (1. v roce strhne kredit + ověří totožnost); přímý INSERT odepřen.
- **`verify` mock|live** přepínač; **default `live`** (v kódu — Supabase MCP nemá nástroj na secrets). Reálné ARES/ISIR/DPH/VIES.
- **Edge regexy MUSÍ být char-class** (`[0-9]`, ne `\d`) — **přes Supabase MCP deploy se `\d` rozbíjí** na literál (způsobilo FO „Neplatné vstupní údaje" a ISIR chyby).
- **Matice úroveň×rejstřík v DB** (`registry_config.lvl_*`), admin přiřazuje úrovně/ceny → flexibilní bez nasazení.
- **Idempotence:** kredity (unique index na payment_id), platby (status guard), `verify` (request_id).
- **Cache:** css/js revalidace místo ročního immutable (web se iteruje editací souborů in-place).

## Supabase — schéma, RLS, migrace
- **Migrace `sql/001–020`: VŠECHNY APPLIED** na `wefucmmkbspyaodofdki` (přes MCP). Žádné pending.
  Public schéma bylo resetováno před aplikací; legacy testovací data smazána, CMS/settings zachovány.
- **Tabulky (public):** `users` (profil 1:1 auth.users), `admin_users`, `content`, `settings`,
  `listings`, `listing_files`, `messages`, `storefronts`, `subscriptions`, `seller_identity`,
  `user_credits`, `credit_transactions`, `payments`, `verification_requests`, `verification_results`,
  `registry_config` (14 rejstříků), `foc_rate_limit`.
- **RLS:** vlastník vidí/edituje jen své; citlivé zápisy (kredity/platby/výsledky) jen service role / SECURITY DEFINER;
  `listings_preview` veřejné, base `listings` gated předplatným; admin přes `is_admin`.
- **Storage:** buckety `listing-files` (private) + `storefront-logos` (public) + RLS (migrace 017).
- **pg_cron:** `cleanup_expired_verifications` + `sync_storefronts` — joby v migraci 016 (běží jen je-li rozšíření pg_cron).
- **registry_config (14):** ares, isir, dph, vies, katastr, zivnost, vozidla, upadci, cee, sbirka, atp, isds, bankid, sankce.

## TODO (prioritizovaně)
**P1 — blokuje plný ostrý provoz**
- Merge `feat/core-rebuild` → `main` + napojit Vercel na git (auto-deploy na push).
- Supabase **Auth Site URL** + Redirect URLs na `https://debtora-cz.vercel.app` (jinak potvrzovací e-mail míří na localhost). Nebo vypnout „Confirm email" pro rychlý launch (Authentication → Providers → Email).
- **CEE (exekuce)** — doplnit secrets `CEE_API_URL`/`CEE_API_KEY` (Smart Collectors) + mapovat odpověď v `_shared/cee.ts`.

**P2 — funkční mezery**
- Napojit legacy `overeni-najemce.html` + `js/overeni.js` na nové `verify`.
- `ucet.html` doplnit: zůstatek kreditů, předplatné, historie ověření, smazání účtu (`API.deleteAccount`).
- **ISDS** (datová schránka) a **sankce/PEP** — adaptery jsou sloty (`unavailable`), doplnit zdroj/přístup.
- Comgate produkční merchant/secret + ověřená callback URL; `COMGATE_TEST=false`.
- Resend `RESEND_API_KEY` (transakční e-maily — teď fail-soft, neodesílá).

**P3 — fáze 2**
- Fakturoid (faktury), monitoring/opakované kontroly, PDF report. iOS app (samostatný workstream).

## Ověřovací příkazy
```bash
# Frontend — bez build stepu; lokální náhled:
python3 -m http.server 8787 --directory /Users/jirihochman/debtora-cz   # → http://127.0.0.1:8787/
# Kontrola inline JS (žádný bundler):
node --check <(python3 - <<'PY'
import re;print(re.findall(r'<script>(.*?)</script>',open('index.html').read(),re.S)[-1])
PY
)
# Nasazení frontendu (potřebuje přihlášený Vercel CLI uživatele):
cd /Users/jirihochman/debtora-cz && npx vercel --prod
# Migrace na prázdnou DB (v pořadí): for f in sql/0*.sql; do psql "$DATABASE_URL" -f "$f"; done
#   (v této session aplikováno přes Supabase MCP apply_migration)
# Edge funkce: supabase functions deploy <name>  (nebo přes Supabase MCP deploy_edge_function)
# Test verify (live): POST .../functions/v1/verify  {subject:{type:'po',ico:'45272956'},level:'foc_nologin'}  s anon klíčem
```

## Enrichment ověřovače (2026-06-14) — `verify` v7
Adaptery rozšířeny o „maximum detailu" z reálných zdrojů (ověřeno živě na IČO 45272956 Generali a 25083325 Sberbank):
- **ARES** (`checkAres`): jméno · právní forma (kód→zkratka) · sídlo · datum vzniku/zániku · **sp. zn. (aktuální z VR)** · statutární orgán (jména z VR) · DIČ · NACE. Příznak ⚠ „v likvidaci"/zánik. Nový `ARES_VR_ENDPOINT`, helper `aresVr` + `pravniFormaLabel`.
- **ISIR** (`checkIsir`): u nálezu vrací sp. zn. `INS bcVec/rocnik` · `druhStavKonkursu` · soud (`nazevOrganizace`) · datum zahájení úpadku + `cases[]` v payloadu.
- **RŽP** (`checkZivnost`): stav `stavZdrojeRzp` (AKTIVNI/HISTORICKY/ZANIKLY/—) + obory (NACE).
- **CEÚ** (`checkUpadci`): příznak `stavZdrojeCeu` + odkaz na ISIR detail.
- Výkon: `aresBase` má **cache na instanci** → ARES base jen 1 volání na IČO napříč adaptery (+1 VR v checkAres).
- Drobnosti k doladění (P3): ISIR :8443 občas spadne na cold-callu (přechodné → ✕, u placených refund) — zvážit 1 retry; `datumPmZahajeniUpadku` vrací hodnotu s koncovým „Z" (kosmetika).

## Deploy audit + redeploy (2026-06-14) — disk ✔ = produkce ✔
Audit „disk vs. nasazeno" potvrdil, že **veškerý kód session je na disku** (SQL i frontend plně in-sync;
17 tabulek / 21 funkcí / view / 43 RLS policies mají CREATE na disku; 19 frontend markerů přítomno).
Disk je kanonický. Drobné opravy + redeploy provedeny:
- `verify` v6: nasazení mělo navíc konstantu `VIES_ENDPOINT` → **doplněno na disk**. Disk = nasazeno. Neredeployováno (už správné).
- `payment-create` → **redeploy v2**: email regex ztvrzen na char-class `/^[^@ ]+@[^@ ]+[.][^@ ]{2,}$/` (byl `\s`/`\.`),
  bundlovaný `cee.ts` opraven na char-class (byl MCP-zkomolený `\D`); disk bug `status:"error"` → **`"failed"`** (CHECK `payments.status`).
  Ověřeno invokací: špatný e-mail→400, `test@debtora.cz`→502 Comgate (projde regexem+`validateSubject`), neznámá akce→400.
- `payment-callback` → **redeploy v2** (`verify_jwt=false`): čistý `cee.ts`+`email.ts`. Ověřeno: prázdný body→400 „Missing transId".
- `admin-moderate-listing` → **redeploy v2**: čistý `email.ts`. Ověřeno: bez polí→400, jako neadmin→403.
- `delete-account` v1: NEredeployováno — rozdíl jen v komentářích, funkčně identické.
**Stav:** produkce běží na opravené disk verzi. Žádný DB objekt ani frontend kód nechybí na disku.

### MCP deploy edge funkcí — funkční recept (zjištěno 2026-06-14)
Supabase MCP `deploy_edge_function` (a) **komolí zpětná lomítka** v regexech (`\d`→`\\d`) → v edge kódu používat
char-class `[0-9]` apod.; (b) **obaluje předané soubory do `source/`**. Aby import `../_shared/x.ts` resolvoval:
předávej `files` se jmény `source/index.ts` + `_shared/x.ts` a `entrypoint_path: "source/index.ts"`.
(Výsledný entrypoint je `source/source/index.ts` — kosmeticky, ale funguje; import `../_shared` z něj míří na `source/_shared`.)
Alternativa bez komolení: `supabase functions deploy <fn>` přes CLI (čte soubor doslova).

## Otevřené otázky / blokery
- **`VERIFY_MODE` default je v kódu `live`** (Supabase MCP nemá nástroj na secrets). Zpět na mock: nastavit secret `VERIFY_MODE=mock` v dashboardu, nebo redeploy.
- **FOC rate limit 2/subjekt/den** je pro veřejný ověřovač nízký → zvednout v Admin → Nastavení `foc_limits` (např. `{"per_ip_day":50,"per_subject_day":10}`); reset počítadla: `delete from foc_rate_limit;`.
- **Edge deploy přes MCP komolí `\d` regexy** → v edge kódu používat výhradně třídy znaků `[0-9]`/`[^0-9]`/`[^]`.
- **VIES** může u skupinového DIČ vracet „neplatné" (reálný stav), výpadek → „nedostupné".
- **Email confirmation je ZAP** → registrace vyžaduje potvrzení + správné Site URL (viz P1).

## Odkazy
- **Produkce:** https://debtora-cz.vercel.app · demo: https://debtora-cz.vercel.app/demo
- **Supabase dashboard:** https://supabase.com/dashboard/project/wefucmmkbspyaodofdki
  - Auth URL config: `.../auth/url-configuration` · Edge secrets: `.../settings/functions`
- **Vercel:** projekt `ba-netizen's projects/debtora-cz`
- **Dokumentace v repu:** `docs/CORE-PLAN.md`, `docs/CORE-README.md`, `docs/FINALIZATION.md`
- Jira/Confluence: —
