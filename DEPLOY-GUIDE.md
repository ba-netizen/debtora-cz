# DEBTORA CZ — Podrobný návod na nasazení

## Kompletní postup: Supabase + GitHub + Vercel

Tento návod tě provede od rozbalení ZIP souboru až po fungující web na vlastní doméně.

---

## ČÁST 1: Příprava počítače

### 1.1 — Nainstaluj Git

**Windows:**
- Stáhni z https://git-scm.com/download/win
- Spusť instalátor, proklikej s výchozím nastavením
- Po instalaci otevři "Git Bash" (najdeš v Start menu)

**Mac:**
- Otevři Terminal a napiš: `xcode-select --install`

**Ověření:**
```bash
git --version
```
Mělo by vypsat něco jako `git version 2.43.0`.

### 1.2 — Nainstaluj Node.js

- Stáhni LTS verzi z https://nodejs.org (zelené tlačítko)
- Spusť instalátor

**Ověření:**
```bash
node --version
npm --version
```

### 1.3 — Rozbal ZIP soubor

```bash
# Na ploše nebo kam chceš
unzip debtora-cz-github.zip -d debtora-cz
cd debtora-cz
```

Nebo prostě rozbal ZIP soubor přes průzkumníka a otevři složku v terminálu.

**Obsah složky by měl vypadat takto:**
```
debtora-cz/
├── index.html
├── trziste.html
├── kontakt.html
├── registrace.html
├── vlozit-inzerat.html
├── sluzby-dluhy.html
├── sluzby-otc.html
├── sluzby-nemovitosti.html
├── jak-to-funguje.html
├── o-nas.html
├── cenik.html
├── podminky.html
├── ochrana-soukromi.html
├── css/style.css
├── js/supabase-config.js    ← SEM DOPLNÍŠ CREDENTIALS
├── js/api.js
├── js/cms.js
├── js/main.js
├── sql/001_schema.sql
├── sql/002_rls_policies.sql
├── sql/003_seed_data.sql
├── sql/004_functions.sql
├── vercel.json
├── .gitignore
├── .env.example
└── README.md
```

---

## ČÁST 2: Nastavení Supabase (databáze)

### 2.1 — Vytvoř Supabase účet

1. Jdi na https://supabase.com
2. Klikni **Start your project** (vpravo nahoře)
3. Přihlas se přes GitHub účet (nejrychlejší) nebo e-mailem

### 2.2 — Vytvoř nový projekt

1. Na dashboardu klikni **New Project**
2. Vyplň:
   - **Organization** → tvoje organizace (nebo vytvoř novou)
   - **Name** → `debtora-cz`
   - **Database Password** → vygeneruj silné heslo a **ZAPIŠ SI HO** (budeš ho potřebovat)
   - **Region** → `Central EU (Frankfurt)` — nejbližší k ČR
   - **Pricing Plan** → Free (stačí)
3. Klikni **Create new project**
4. Počkej 2–3 minuty než se projekt vytvoří (uvidíš loading bar)

### 2.3 — Zkopíruj API klíče

1. V levém menu klikni na **ikonu ozubeného kolečka** (Settings) dole
2. Klikni **API** (v podmenu)
3. Uvidíš tři důležité hodnoty:

**Project URL:**
```
https://abcdefghijklm.supabase.co
```
Zkopíruj celou URL.

**anon public key:**
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJz...
```
Zkopíruj celý řetězec (je velmi dlouhý, to je OK).

**service_role key (secret):**
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJz...
```
Zkopíruj a **ULOŽ NA BEZPEČNÉ MÍSTO**. Tento klíč nikdy nesdílej veřejně!

### 2.4 — Vlož credentials do konfigurace

Otevři soubor `js/supabase-config.js` v textovém editoru (VS Code, Notepad++, nebo i Poznámkový blok):

**Před úpravou:**
```javascript
window.DEBTORA_CONFIG = {
  SUPABASE_URL: 'https://YOUR_PROJECT_ID.supabase.co',
  SUPABASE_ANON_KEY: 'YOUR_ANON_KEY_HERE'
};
```

**Po úpravě (příklad):**
```javascript
window.DEBTORA_CONFIG = {
  SUPABASE_URL: 'https://abcdefghijklm.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJz...'
};
```

**Ulož soubor** (Ctrl+S).

### 2.5 — Spusť SQL skripty (vytvoř databázi)

Teď vytvoříš tabulky v databázi. V Supabase dashboardu:

1. V levém menu klikni na **SQL Editor** (ikona `<>`)
2. Klikni **New query** (vpravo nahoře)

**Skript 1 — Schema (tabulky):**
1. Otevři soubor `sql/001_schema.sql` v editoru
2. Označ veškerý text (Ctrl+A) a zkopíruj (Ctrl+C)
3. Vlož do SQL Editoru v Supabase (Ctrl+V)
4. Klikni **Run** (zelené tlačítko vpravo dole, nebo Ctrl+Enter)
5. Mělo by se zobrazit: `Success. No rows returned`

**Skript 2 — RLS Policies:**
1. Klikni **New query** (nový dotaz — nemaž starý, vytvoř nový)
2. Otevři `sql/002_rls_policies.sql`, zkopíruj celý obsah
3. Vlož do nového dotazu → **Run**
4. Očekávaný výstup: `Success. No rows returned`

**Skript 3 — Seed Data (výchozí obsah):**
1. Nový dotaz → obsah `sql/003_seed_data.sql` → **Run**
2. Očekávaný výstup: `Success. No rows returned`

**Skript 4 — Functions:**
1. Nový dotaz → obsah `sql/004_functions.sql` → **Run**
2. Očekávaný výstup: `Success. No rows returned`

### 2.6 — Ověř, že databáze funguje

1. V levém menu klikni na **Table Editor** (ikona tabulky)
2. Měl bys vidět 6 tabulek:
   - `admin_users` → 1 řádek (admin účet)
   - `content` → 11 řádků (CMS obsah pro každou stránku)
   - `listings` → 6 řádků (ukázkové inzeráty)
   - `messages` → prázdná
   - `settings` → 2 řádky (company, contact)
   - `users` → prázdná

Pokud vidíš tabulky s daty, **databáze je hotová**.

---

## ČÁST 3: GitHub (verzování kódu)

### 3.1 — Vytvoř GitHub účet

Pokud nemáš, zaregistruj se na https://github.com (zdarma).

### 3.2 — Vytvoř nový repozitář

**Varianta A — Přes web (jednodušší):**

1. Na GitHubu klikni **+** (vpravo nahoře) → **New repository**
2. Vyplň:
   - **Repository name** → `debtora-cz`
   - **Description** → `Czech distressed asset marketplace`
   - **Visibility** → Private (doporučeno) nebo Public
   - **NEZAŠKRTÁVEJ** "Add a README file" (už máš svůj)
3. Klikni **Create repository**
4. GitHub ti ukáže příkazy pro propojení — **NEKLIKEJ** na nic, jdi k dalšímu kroku

### 3.3 — Nahraj soubory na GitHub

Otevři terminál (Git Bash na Windows, Terminal na Mac) a přejdi do složky projektu:

```bash
cd /cesta/k/debtora-cz
```

Na Windows třeba: `cd C:/Users/Jiri/Desktop/debtora-cz`
Na Mac třeba: `cd ~/Desktop/debtora-cz`

Spusť tyto příkazy **postupně** (každý řádek zvlášť):

```bash
# 1. Inicializuj Git repozitář
git init

# 2. Přidej všechny soubory
git add .

# 3. Vytvoř první commit
git commit -m "Initial commit: DEBTORA CZ with Supabase"

# 4. Nastav hlavní větev
git branch -M main

# 5. Propoj s GitHubem (nahraď YOUR_USERNAME svým GitHub jménem)
git remote add origin https://github.com/YOUR_USERNAME/debtora-cz.git

# 6. Nahraj na GitHub
git push -u origin main
```

Při prvním push tě GitHub požádá o přihlášení:
- **Username** → tvoje GitHub jméno
- **Password** → GitHub Personal Access Token (ne heslo!)

**Jak získat Personal Access Token:**
1. Na GitHubu: **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)**
2. **Generate new token (classic)**
3. Note: `debtora-deploy`
4. Expiration: 90 days
5. Zaškrtni: `repo` (celá sekce)
6. **Generate token** → zkopíruj token a použij místo hesla

### 3.4 — Ověř nahrání

Jdi na `https://github.com/YOUR_USERNAME/debtora-cz` — měl bys vidět všechny soubory.

---

## ČÁST 4: Vercel (hosting webu)

### 4.1 — Vytvoř Vercel účet

1. Jdi na https://vercel.com
2. Klikni **Sign Up**
3. Zvol **Continue with GitHub** (propojí se s tvým GitHubem)
4. Autorizuj přístup

### 4.2 — Importuj projekt

1. Na Vercel dashboardu klikni **Add New...** → **Project**
2. Uvidíš seznam tvých GitHub repozitářů
3. Najdi **debtora-cz** a klikni **Import**

### 4.3 — Konfigurace projektu

Na stránce konfigurace:

- **Project Name** → `debtora-cz` (nebo jiné jméno, bude v URL)
- **Framework Preset** → `Other` (Vercel by měl detekovat automaticky)
- **Root Directory** → `./` (ponech výchozí)
- **Build Command** → **ponech prázdné** (není potřeba build)
- **Output Directory** → `./` (ponech výchozí)
- **Install Command** → **ponech prázdné**

**NEKLIKEJ** ještě na Deploy. Nejdřív přidej environment variables (volitelné, ale doporučeno):

### 4.4 — Environment Variables (volitelné)

Rozklikni **Environment Variables** a přidej:

| Key | Value |
|-----|-------|
| `VITE_SUPABASE_URL` | `https://abcdefghijklm.supabase.co` |
| `VITE_SUPABASE_ANON_KEY` | `eyJhbGciOiJIUzI1NiIs...` |

Toto je jen pro referenci — skutečné credentials už jsou v `js/supabase-config.js`.

### 4.5 — Deploy!

Klikni **Deploy**.

Vercel začne deployment:
- Nahraje soubory
- Aplikuje `vercel.json` konfiguraci
- Přidělí URL

**Počkej 20–40 sekund.** Uvidíš:

```
✅ Production Deployment
🔗 https://debtora-cz.vercel.app
```

**Tvůj web je živý!**

### 4.6 — Ověř fungování

Otevři v prohlížeči tyto URL:

| URL | Co zkontrolovat |
|-----|----------------|
| `https://debtora-cz.vercel.app` | Homepage se načte, vidíš hero sekci, služby, nabídky |
| `https://debtora-cz.vercel.app/trziste` | Tržiště s 9 inzeráty, filtry fungují |
| `https://debtora-cz.vercel.app/kontakt` | Kontaktní formulář se zobrazí |
| `https://debtora-cz.vercel.app/registrace` | Registrační formulář funguje |
| `https://debtora-cz.vercel.app/cenik` | Ceník se 3 plány |

**Pokud vidíš stránky ale bez dynamického obsahu** (CMS texty se nezobrazí), zkontroluj:
1. Otevři Developer Tools (F12) → Console
2. Hledej chyby typu `Failed to fetch` nebo `401`
3. Pokud ano → špatné credentials v `js/supabase-config.js`

---

## ČÁST 5: Automatické deploye

Od teď se web automaticky aktualizuje při každém push na GitHub:

```bash
# Udělej změny v souborech (např. uprav text v index.html)

# Nahraj na GitHub
git add .
git commit -m "Úprava textu na homepage"
git push

# → Vercel automaticky detekuje push a deployne novou verzi (~20 sekund)
```

Vercel ti taky dává **Preview deployments** — každý pull request dostane vlastní URL pro testování.

---

## ČÁST 6: Vlastní doména (volitelné)

### 6.1 — Přidej doménu ve Vercel

1. Ve Vercel dashboardu → tvůj projekt → **Settings** → **Domains**
2. Klikni **Add**
3. Zadej doménu: `debtora.cz`
4. Klikni **Add**

Vercel ti ukáže DNS záznamy, které musíš nastavit.

### 6.2 — Nastav DNS záznamy

U svého doménového registrátora (Wedos, Forpsi, Active24...):

**Pro hlavní doménu (debtora.cz):**

| Typ | Název | Hodnota |
|-----|-------|---------|
| A | @ | `76.76.21.21` |

**Pro www subdoménu (www.debtora.cz):**

| Typ | Název | Hodnota |
|-----|-------|---------|
| CNAME | www | `cname.vercel-dns.com` |

### 6.3 — Počkej na propagaci

DNS změny se projeví za 5 minut až 48 hodin (typicky do 1 hodiny). SSL certifikát (HTTPS) se nastaví automaticky.

---

## ČÁST 7: Správa obsahu (CMS)

### 7.1 — Editace přes Supabase Studio

Nejjednodušší způsob editace obsahu:

1. Jdi na https://supabase.com/dashboard
2. Vyber projekt `debtora-cz`
3. Klikni **Table Editor** v levém menu

**Editace textu na stránkách:**
1. Klikni na tabulku `content`
2. Najdi řádek s příslušnou stránkou (např. `homepage`)
3. Klikni na buňku ve sloupci `fields`
4. Uprav JSON — např. změň `hero_headline`
5. Klikni mimo buňku (auto-save)
6. Refreshni web — změny se projeví okamžitě

**Příklad — změna nadpisu homepage:**
```json
{
  "hero_tag": "Česká platforma pro distressed assets",
  "hero_headline": "Investujte do <em>podhodnocených aktiv</em> s důvěrou",
  "hero_desc": "Nový popis stránky..."
}
```

**Správa inzerátů:**
1. Tabulka `listings`
2. Změň `status` z `pending` na `active` pro schválení
3. Přidej nový řádek pro nový inzerát

**Čtení zpráv:**
1. Tabulka `messages`
2. Změň `is_read` na `true` po přečtení

**Správa uživatelů:**
1. Tabulka `users`
2. Změň `kyc_status` na `verified` pro ověření

### 7.2 — Změna admin hesla

V SQL Editoru spusť:

```sql
UPDATE admin_users
SET password_hash = encode(digest('TVOJE_NOVE_HESLO', 'sha256'), 'hex')
WHERE username = 'admin';
```

Nahraď `TVOJE_NOVE_HESLO` svým heslem.

---

## ČÁST 8: Řešení problémů

### Web se nezobrazí

1. Zkontroluj Vercel dashboard — je deployment "Ready"?
2. Podívej se do Vercel logů: **Deployments** → klikni na poslední → **Build Logs**

### CMS obsah se nenačítá

1. Otevři DevTools (F12) → **Console** — hledej červené chyby
2. Otevři DevTools → **Network** → refreshni stránku → hledej požadavky na `supabase.co`
3. Pokud vidíš `401 Unauthorized` → špatný anon key v `supabase-config.js`
4. Pokud vidíš `404` → špatná Project URL

### Formuláře nefungují

1. Ověř, že RLS policies proběhly (`002_rls_policies.sql`)
2. V Supabase: **Authentication** → **Policies** — měl bys vidět politiky na všech tabulkách

### Git push nefunguje

```bash
# Pokud dostaneš "Authentication failed":
# Potřebuješ Personal Access Token místo hesla
# Viz sekce 3.3

# Pokud dostaneš "remote origin already exists":
git remote remove origin
git remote add origin https://github.com/YOUR_USERNAME/debtora-cz.git
git push -u origin main
```

### Chci vrátit změny

```bash
# Vrátit poslední commit (zachová soubory)
git reset --soft HEAD~1

# Vrátit soubor do posledního uloženého stavu
git checkout -- index.html

# Vrátit všechno na poslední commit
git checkout -- .
```

---

## Rychlý přehled příkazů

| Co chci udělat | Příkaz |
|---------------|--------|
| Nahrát změny na web | `git add . && git commit -m "popis" && git push` |
| Lokální náhled | `npx serve . -l 3000` pak http://localhost:3000 |
| Stáhnout aktuální verzi | `git pull` |
| Zobrazit stav souborů | `git status` |
| Historie změn | `git log --oneline` |
| Záloha databáze | Supabase Dashboard → Settings → Database → Backups |

---

## Kontakty na support

- **Supabase docs:** https://supabase.com/docs
- **Vercel docs:** https://vercel.com/docs
- **Git příručka:** https://git-scm.com/book/cs/v2
