# DEBTORA CZ — Otevřené body k finalizaci

Stav produkce k 2026-06-13: web živý na **https://debtora-cz.vercel.app**, Supabase
`wefucmmkbspyaodofdki` zmigrovaný (sql/001–017), 5 edge funkcí ACTIVE, ověření v `mock`.
Tento soubor sleduje, co zbývá dotáhnout před plným ostrým provozem.

## Otevřené body

- [ ] **Auth: potvrzování e-mailu + Site URL** *(odloženo — rozhodnout při finalizaci).*
      Aktuálně `mailer_autoconfirm = false` → registrace vyžaduje potvrzovací e-mail,
      jehož odkaz míří na **Site URL**. Dvě varianty:
      (a) ponechat potvrzování ZAP → nastavit Site URL `https://debtora-cz.vercel.app`
          + Redirect URL `https://debtora-cz.vercel.app/**`
          (dashboard → Authentication → URL Configuration) a otestovat odkaz v e-mailu;
      (b) pro rychlý launch potvrzování VYP (Authentication → Providers → Email →
          *Confirm email* off) → registrace přihlásí rovnou, redirect přestane být kritický.
      Pozn.: hodnotu Site URL nelze přečíst přes API/MCP — ověřuje se reálnou registrací.

- [ ] **Redeploy frontendu** po napojení `inzerat.html` + `vlozit-inzerat.html`:
      `cd /Users/jirihochman/debtora-cz && npx vercel --prod` (commit 62edbe1 zatím
      nasazený není — poslední `--prod` byl před tímto napojením).

- [ ] **Napojit zbývající stránky na nové API** (pořád používají legacy volání):
      `admin.html` (moderace → edge `admin-moderate-listing`, admin login přes Supabase
      Auth + `admin_users`), `prihlaseni.html` / `registrace.html` (Supabase Auth
      přes `Auth.login`/`Auth.register`), `ucet.html` (profil, kredity, předplatné,
      historie ověření, smazání účtu přes `API.deleteAccount`).

- [ ] **Založit admin účet:** zaregistrovat reálný admin e-mail přes Auth, pak
      `insert into admin_users (user_id, role) values ('<auth.uid>', 'admin');`.

- [ ] **Edge secrets** (Supabase → Edge Functions → Secrets): `COMGATE_MERCHANT`,
      `COMGATE_SECRET`, `COMGATE_TEST=false` (platby); `RESEND_API_KEY`, `EMAIL_FROM`
      (e-maily); `CEE_API_URL`, `CEE_API_KEY` + `VERIFY_MODE=live` (ostré exekuce).
      Bez nich web jede, tyto funkce běží v mock/degradovaném režimu.

- [ ] **Storage ověřit:** buckety `listing-files` (private) a `storefront-logos` (public)
      + RLS jsou nasazené (017). Otestovat reálný upload z `vlozit-inzerat` a signed URL
      v `inzerat`.

- [ ] **pg_cron** (volitelné): povolit rozšíření → joby `cleanup-verifications` a
      `sync-storefronts` (migrace 016 je založí; bez rozšíření se přeskočí).

- [ ] **Git auto-deploy:** merge `feat/core-rebuild` → `main`, pak v Vercelu připojit
      repo (Settings → Git) → deploy na každý push. Do té doby deploy přes
      `npx vercel --prod` z lokální složky (branch `feat/core-rebuild`).

## Hotovo (reference)
DB migrace, RLS, 5 edge funkcí, `trziste`/`inzerat`/`vlozit-inzerat` napojeny na nové API,
CMS obsah + firemní settings zachovány, frontend live na Vercelu. Detaily v
[CORE-README.md](./CORE-README.md) a [CORE-PLAN.md](./CORE-PLAN.md).
