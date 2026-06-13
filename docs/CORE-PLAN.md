# DEBTORA CZ — CORE PLAN

Plán sdíleného jádra. Stav repozitáře (legacy `sql/001–006`, WIP `007–011`, edge funkce,
`js/*`) byl prostudován a slouží jako reference. Jádro je přestavěno jako **ucelený celek
postavený na `auth.users`** — ne jako záplaty. Tento dokument je závazná mapa; detailní
postup spuštění je v [CORE-README.md](./CORE-README.md).

## Klíčová rozhodnutí (defaulty)

| # | Rozhodnutí | Důvod |
|---|-----------|-------|
| D1 | **Identita stojí výhradně na `auth.users`.** Nový profil `users` má `id = auth.users.id` (1:1), zakládá ho trigger `on auth.users insert`. | Sekce 7 spec. Legacy custom-login (`password_hash`) se ruší. |
| D2 | **Legacy custom-auth SQL přesunut do `sql/legacy/`** (001–006 původní). Nepoužívá se, slouží jako reference + případná datová migrace. | „Legacy nech stranou, gating na auth.users." |
| D3 | **Admin je příznakovaný `auth.users` účet** (`admin_users.user_id → auth.users`), autorizace přes `is_admin(auth.uid())` v SECURITY DEFINER. **Žádný service-role klíč ve frontendu.** | Původní `AdminAPI` vracel service-role klíč do prohlížeče — bezpečnostní díra; akceptační kritérium. |
| D4 | **Marketing × citlivé sloupce** odděleny projekcí: veřejný `listings_preview` (jen marketing, obchází RLS), base `listings` (plný detail) gated předplatným/vlastníkem. | Sekce 4. View = realizace oddělení. |
| D5 | **Tvorba inzerátu jen přes `create_listing()` RPC.** Přímý INSERT do `listings` odepřen (žádná INSERT policy). | Sekce 4 + 5. |
| D6 | **`registry_config` nese matici úroveň × rejstřík** (boolean per úroveň) + cenu v kreditech. Adaptery živě: ISIR/ARES/DPH; CEE přes env; Katastr/Vozidla/ATP/BankiD jsou zatím jen konfigurace (mock). | Sekce 6. |
| D7 | **`verify` má režim `mock` (default) / `live`** přes env `VERIFY_MODE`. Mock vrací deterministický verdikt per rejstřík + rizikové skóre a umí simulovat selhání (→ refund). | Sekce 5 + akceptační kritéria; živé rejstříky nesmí být nutné k testu. |
| D8 | **`add_credits` je idempotentní podle `payment_ref`** (duplicitní PAID callback nepřipíše 2×). Refund = `add_credits(reason='refund')`. | Akceptační kritérium. |
| D9 | Reason ledgeru sjednocen: `purchase` / `spend` / `refund` / `identity_first_listing` / `admin`. | Sekce 3. |
| D10 | Frontend bez build-stepu; `auth.js` přepsán na Supabase Auth. | Sekce 2 + 8. |

## Tabulky (cílový stav, vše na `auth.users`)

CMS: `content`, `settings`
Identita: `users` (profil 1:1 auth.users), `admin_users` (role admin/editor)
Marketplace: `listings` (owner_id→auth.users, storefront_id→storefronts), `listing_files`, `messages`
Storefronty/předplatné/identita prodejce: `storefronts`, `subscriptions`, `seller_identity`
Kredity: `user_credits`, `credit_transactions`
Ověření: `verification_requests`, `verification_results` (TTL 30 d), `registry_config`
Platby: `payments`

## RPC (SECURITY DEFINER)

`handle_new_user` (trigger), `is_admin(uid)`, `increment_views(id)`,
`add_credits(user,amount,reason,payment_ref)` *(idempotentní)*, `spend_credits(user,amount,reason)`,
`refund_credits(user,amount,reason,payment_ref)`, `has_active_subscription(user,service)`,
`activate_subscription(user,service,months,payment)`, `is_identity_verified(user,year)`,
`create_listing(jsonb)`, admin CRUD (`admin_*`, autorizace `is_admin`).

## Edge funkce (Deno/TS)

`verify` (mock|live, risk score, refund), `payment-create` (single/pack5/pack20/pack50/sub_inzerce_monthly),
`payment-callback` (webhook, idempotentní, add_credits | activate_subscription),
`_shared/` (`cee.ts` adapter, typy `Subject`/`RegistryResult`, `validateSubject`, `registries.ts` mock).

## JS moduly

`supabase-config.js` (URL+anon), `auth.js` (Supabase Auth), `api.js` (preview vs detail, create_listing, verify, platby, kredity, subscription),
`cms.js` (content/settings), `main.js` (nav/menu/filtry).

## Pořadí migrací (nová čistá série v `sql/`)

```
001_extensions.sql        rozšíření + updated_at() helper
002_identity.sql          users (auth.users 1:1) + trigger + admin_users + is_admin()
003_cms.sql               content, settings + RLS + admin write RPC
004_marketplace.sql       listings(owner_id) + listing_files + messages + RLS + listings_preview + increment_views
005_storefronts.sql       storefronts + RLS
006_subscriptions.sql     subscriptions + has_active_subscription + activate_subscription
007_credits.sql           user_credits + credit_transactions + add_credits(idemp)/spend_credits/refund_credits
008_verification.sql      verification_requests/results (TTL 30 d) + cleanup
009_registry_config.sql   registry_config (matice úroveň×rejstřík) + admin RPC
010_payments.sql          payments + produktové constrainty
011_seller_identity.sql   seller_identity + is_identity_verified
012_listing_gating.sql    create_listing() + gating policies na listings (zákaz přímého INSERT)
013_seed.sql              seed content/settings/registry; ukázkové listingy
```

Každá migrace je idempotentní (`create table if not exists`, `create or replace`, `drop policy if exists`).
Spouští se v pořadí na prázdné DB → viz akceptační kritéria v CORE-README.

## Mimo rozsah (fáze 2)

iOS app, produkční `live` CEE (jen adapter+env), Fakturoid, monitoring/PDF report.
