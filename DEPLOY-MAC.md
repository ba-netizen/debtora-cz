# DEBTORA CZ — Návod na nasazení (macOS)

Kompletní postup od stažení ZIP souboru po fungující web. Psáno specificky pro Mac.

---

## KROK 1: Otevři Terminal

Stiskni `Cmd + mezerník`, napiš **Terminal**, stiskni Enter.

Terminal je tvůj hlavní nástroj — všechny příkazy budeš psát sem.

---

## KROK 2: Nainstaluj potřebné nástroje

### 2.1 — Git

Napiš do Terminálu:

```bash
git --version
```

Pokud se zobrazí verze (např. `git version 2.39.5`) → máš Git, přeskoč dál.

Pokud se zobrazí dialog "The xcode-select command requires..." → klikni **Install** a počkej.

Nebo ručně:

```bash
xcode-select --install
```

Klikni **Install** v dialogu → počkej 5–10 minut → hotovo.

### 2.2 — Node.js

Napiš do Terminálu:

```bash
node --version
```

Pokud se zobrazí verze (v18+) → máš Node, přeskoč.

Pokud ne:

1. Otevři Safari → https://nodejs.org
2. Stáhni **LTS** verzi (zelené tlačítko)
3. Otevři stažený `.pkg` soubor → proklikej instalátor
4. Ověř:

```bash
node --version
npm --version
```

---

## KROK 3: Rozbal a připrav projekt

### 3.1 — Přesuň ZIP do domácí složky

Otevři Finder → najdi stažený `debtora-cz-github.zip` (typicky ve složce Downloads).

### 3.2 — Rozbal a přejdi do složky

```bash
cd ~/Downloads
unzip debtora-cz-github.zip -d ~/debtora-cz
cd ~/debtora-cz
```

### 3.3 — Ověř obsah

```bash
ls -la
```

Měl bys vidět:

```
index.html
trziste.html
kontakt.html
registrace.html
vlozit-inzerat.html
sluzby-dluhy.html
sluzby-otc.html
sluzby-nemovitosti.html
jak-to-funguje.html
o-nas.html
cenik.html
podminky.html
ochrana-soukromi.html
css/
js/
sql/
vercel.json
README.md
DEPLOY-GUIDE.md
.gitignore
.env.example
```

Pokud vidíš tyto soubory → vše OK.

---

## KROK 4: Založ Supabase projekt (databáze)

### 4.1 — Registrace

1. Otevři Safari → https://supabase.com
2. Klikni **Start your project**
3. Přihlas se přes **GitHub** (nejrychlejší) nebo přes e-mail

### 4.2 — Nový projekt

1. Klikni **New Project**
2. Vyplň:

| Pole | Hodnota |
|------|---------|
| Organization | Tvoje org (nebo vytvoř novou) |
| Name | `debtora-cz` |
| Database Password | Klikni **Generate a password** a **ZKOPÍRUJ SI HO** do Poznámek |
| Region | **Central EU (Frankfurt)** |
| Plan | Free |

3. Klikni **Create new project**
4. Počkej 2–3 minuty (uvidíš progress bar)

### 4.3 — Zkopíruj API klíče

Jakmile je projekt vytvořen:

1. Vlevo dole klikni na **⚙️** (Settings)
2. Klikni **API**
3. Uvidíš 3 hodnoty — zkopíruj první dvě:

**Project URL** — klikni na ikonu kopírování vedle URL:
```
https://xyzabcdef.supabase.co
```

**anon public** — klikni **Reveal** a zkopíruj:
```
eyJhbGciOiJIUzI1NiIsInR5cCI6...
```

### 4.4 — Vlož credentials do projektu

V Terminálu (měl bys být v ~/debtora-cz):

```bash
open -a TextEdit js/supabase-config.js
```

Nebo pokud máš VS Code:

```bash
code js/supabase-config.js
```

Uprav soubor — nahraď `YOUR_PROJECT_ID` a `YOUR_ANON_KEY_HERE`:

```javascript
window.DEBTORA_CONFIG = {
  SUPABASE_URL: 'https://xyzabcdef.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6...'
};
```

Ulož: `Cmd + S`, zavři editor.

### 4.5 — Vytvoř tabulky v databázi

Vrať se do Supabase v prohlížeči:

1. Vlevo klikni na **SQL Editor** (ikona `<>`)
2. Klikni **New query**

Teď spustíš 4 SQL skripty. Pro každý:
- V Terminálu otevři soubor: `cat sql/001_schema.sql | pbcopy` (zkopíruje obsah do schránky)
- V Supabase SQL Editoru: `Cmd + V` (vloží)
- Klikni **Run** (nebo `Cmd + Enter`)
- Měl bys vidět: `Success. No rows returned`
- Klikni **New query** pro další

**Pořadí (důležité!):**

```bash
# Skript 1 — tabulky
cat sql/001_schema.sql | pbcopy
# → přepni do prohlížeče → Cmd+V → Run → New query

# Skript 2 — bezpečnostní pravidla
cat sql/002_rls_policies.sql | pbcopy
# → Cmd+V → Run → New query

# Skript 3 — výchozí obsah a ukázkové inzeráty
cat sql/003_seed_data.sql | pbcopy
# → Cmd+V → Run → New query

# Skript 4 — SQL funkce
cat sql/004_functions.sql | pbcopy
# → Cmd+V → Run
```

### 4.6 — Ověř databázi

1. Vlevo klikni na **Table Editor** (ikona tabulky)
2. Zkontroluj:

| Tabulka | Počet řádků |
|---------|-------------|
| `content` | 11 |
| `listings` | 6 |
| `settings` | 2 |
| `admin_users` | 1 |
| `users` | 0 (prázdná) |
| `messages` | 0 (prázdná) |

Pokud tohle sedí → **databáze je hotová**.

---

## KROK 5: Nahraj na GitHub

### 5.1 — Vytvoř GitHub účet (pokud nemáš)

Safari → https://github.com → Sign up

### 5.2 — Vytvoř Personal Access Token

Budeš ho potřebovat místo hesla při push:

1. Na GitHubu klikni na svůj avatar (vpravo nahoře) → **Settings**
2. Scrolluj dolů → **Developer settings** (úplně dole vlevo)
3. **Personal access tokens** → **Tokens (classic)**
4. **Generate new token** → **Generate new token (classic)**
5. Vyplň:
   - Note: `debtora`
   - Expiration: `90 days`
   - Zaškrtni celou sekci **repo**
6. Klikni **Generate token**
7. **ZKOPÍRUJ TOKEN HNED** (zobrazí se jen jednou!) — ulož si ho do Poznámek

### 5.3 — Vytvoř repozitář na GitHubu

1. Na GitHubu klikni **+** (vpravo nahoře) → **New repository**
2. Vyplň:
   - Repository name: `debtora-cz`
   - Visibility: **Private**
   - **NEZAŠKRTÁVEJ** "Add a README file"
3. Klikni **Create repository**

### 5.4 — Nastav Git identitu

V Terminálu (jednorázově):

```bash
git config --global user.name "Tvoje Jmeno"
git config --global user.email "tvuj@email.cz"
```

### 5.5 — Nahraj projekt

Ujisti se, že jsi ve správné složce:

```bash
cd ~/debtora-cz
```

Spusť příkazy jeden po druhém:

```bash
git init
```
Výstup: `Initialized empty Git repository in /Users/.../debtora-cz/.git/`

```bash
git add .
```
Žádný výstup = OK.

```bash
git commit -m "Initial commit: DEBTORA CZ"
```
Výstup: `13 files changed, ...`

```bash
git branch -M main
```
Žádný výstup = OK.

```bash
git remote add origin https://github.com/TVOJE_JMENO/debtora-cz.git
```
Nahraď `TVOJE_JMENO` svým GitHub username. Žádný výstup = OK.

```bash
git push -u origin main
```

Terminal se zeptá:
```
Username for 'https://github.com': TVOJE_JMENO
Password for 'https://TVOJE_JMENO@github.com':
```

**Do Username** napiš GitHub jméno.
**Do Password** vlož Personal Access Token z kroku 5.2 (`Cmd + V`). Kurzor se nebude hýbat — to je normální, heslo se nezobrazuje. Stiskni Enter.

Výstup:
```
Enumerating objects: 31, done.
...
Branch 'main' set up to track remote branch 'main' from 'origin'.
```

### 5.6 — Ověř

Otevři Safari → `https://github.com/TVOJE_JMENO/debtora-cz`

Měl bys vidět všechny soubory. Pokud ano → **GitHub hotovo**.

---

## KROK 6: Nasaď na Vercel (hosting)

### 6.1 — Registrace

1. Safari → https://vercel.com
2. Klikni **Sign Up**
3. Zvol **Continue with GitHub**
4. Autorizuj přístup ke svému GitHub účtu

### 6.2 — Import projektu

1. Na dashboardu klikni **Add New...** → **Project**
2. V seznamu repozitářů najdi **debtora-cz**
3. Klikni **Import**

### 6.3 — Nastavení (skoro nic měnit nemusíš)

| Pole | Hodnota |
|------|---------|
| Project Name | `debtora-cz` (ponech) |
| Framework Preset | `Other` |
| Root Directory | `./` (ponech) |
| Build Command | **ponech prázdné** |
| Output Directory | `./` (ponech) |

### 6.4 — Klikni Deploy

Počkej 20–30 sekund. Uvidíš konfety a:

```
✅ Congratulations! Your project has been deployed.
🔗 https://debtora-cz.vercel.app
```

### 6.5 — Otestuj web

Klikni na odkaz nebo otevři ručně. Zkontroluj:

| Stránka | URL | Co tam má být |
|---------|-----|---------------|
| Homepage | `/` | Hero sekce, 3 služby, nabídky, statistiky |
| Tržiště | `/trziste` | 9 inzerátů, filtrovací tlačítka fungují |
| Kontakt | `/kontakt` | Formulář + kontaktní údaje vpravo |
| Registrace | `/registrace` | Registrační formulář |
| Ceník | `/cenik` | 3 cenové plány |

---

## KROK 7: Vlastní doména (volitelné)

### 7.1 — Ve Vercel

1. Tvůj projekt → **Settings** → **Domains**
2. Napiš `debtora.cz` → klikni **Add**
3. Vercel ukáže DNS záznamy

### 7.2 — U registrátora domény

Přihlas se u svého registrátora (Wedos, Forpsi, Active24...) a nastav:

**A záznam:**

| Typ | Název | Hodnota | TTL |
|-----|-------|---------|-----|
| A | @ | `76.76.21.21` | 300 |

**CNAME záznam (pro www):**

| Typ | Název | Hodnota | TTL |
|-----|-------|---------|-----|
| CNAME | www | `cname.vercel-dns.com` | 300 |

### 7.3 — Počkej

DNS propagace: 5 minut – 1 hodina (max 48h). SSL certifikát se nastaví automaticky.

---

## KROK 8: Jak dělat změny

### Editace textu přímo v databázi (bez kódu)

1. https://supabase.com/dashboard → tvůj projekt → **Table Editor**
2. Tabulka `content` → najdi řádek (např. `homepage`) → klikni na `fields`
3. Uprav JSON text → klikni mimo → změna se projeví na webu po refreshi

### Editace HTML/CSS souborů

```bash
# Otevři projekt ve VS Code
cd ~/debtora-cz
code .

# Nebo v libovolném editoru
open -a TextEdit index.html
```

Po úpravě nahraj na web:

```bash
cd ~/debtora-cz
git add .
git commit -m "Popis co jsem změnil"
git push
```

Vercel automaticky deployne novou verzi za ~20 sekund.

### Sledování stavu

```bash
# Co se změnilo od posledního uložení?
git status

# Historie změn
git log --oneline

# Vrátit soubor do původního stavu
git checkout -- index.html
```

---

## KROK 9: Správa inzerátů a uživatelů

Vše se spravuje přes Supabase Table Editor:

### Schválení nového inzerátu

1. Table Editor → `listings`
2. Najdi řádek se `status` = `pending`
3. Klikni na buňku `status` → přepiš na `active`
4. Klikni mimo → inzerát se zobrazí na webu

### Přidání nového inzerátu ručně

1. Table Editor → `listings` → klikni **Insert row**
2. Vyplň pole (title, type, status, price, description...)
3. `status` nastav na `active` pokud chceš hned zobrazit

### Čtení kontaktních zpráv

1. Table Editor → `messages`
2. Po přečtení změň `is_read` na `true`

### Ověření uživatele (KYC)

1. Table Editor → `users`
2. Najdi uživatele → změň `kyc_status` na `verified`

### Změna admin hesla

SQL Editor → New query:

```sql
UPDATE admin_users
SET password_hash = encode(digest('NOVE_HESLO', 'sha256'), 'hex')
WHERE username = 'admin';
```

→ Run

---

## Řešení problémů

### "xcrun: error: invalid active developer path"

```bash
xcode-select --install
```

### "Permission denied" při npm

```bash
sudo chown -R $(whoami) ~/.npm
```

### "remote origin already exists"

```bash
git remote remove origin
git remote add origin https://github.com/TVOJE_JMENO/debtora-cz.git
```

### Stránka se načte ale bez CMS obsahu

Otevři DevTools (`Cmd + Option + I`) → záložka **Console**. Pokud vidíš chybu:

- `Failed to fetch` → špatná URL v `supabase-config.js`
- `401 Unauthorized` → špatný anon key
- `No rows returned` → SQL skripty neproběhly správně, spusť znovu `003_seed_data.sql`

### Chci lokální náhled

```bash
cd ~/debtora-cz
npx serve . -l 3000
```

Otevři Safari → http://localhost:3000

Zastav server: `Ctrl + C`

---

## Klávesové zkratky pro Mac

| Akce | Zkratka |
|------|---------|
| Otevřít Terminal | `Cmd + mezerník` → "Terminal" |
| Kopírovat | `Cmd + C` |
| Vložit | `Cmd + V` |
| Uložit soubor | `Cmd + S` |
| DevTools v Safari | `Cmd + Option + I` |
| Nový tab v Terminal | `Cmd + T` |
| Zrušit běžící příkaz | `Ctrl + C` |
| Vyčistit Terminal | `Cmd + K` |

---

## Celý postup v kostce

```bash
# 1. Rozbal
cd ~/Downloads
unzip debtora-cz-github.zip -d ~/debtora-cz
cd ~/debtora-cz

# 2. Nastav Supabase credentials
open -a TextEdit js/supabase-config.js
# → vlož URL a anon key → Cmd+S

# 3. Spusť SQL skripty v Supabase SQL Editoru
cat sql/001_schema.sql | pbcopy        # → vlož do SQL Editoru → Run
cat sql/002_rls_policies.sql | pbcopy  # → New query → vlož → Run
cat sql/003_seed_data.sql | pbcopy     # → New query → vlož → Run
cat sql/004_functions.sql | pbcopy     # → New query → vlož → Run

# 4. Nahraj na GitHub
git init
git add .
git commit -m "Initial commit: DEBTORA CZ"
git branch -M main
git remote add origin https://github.com/TVOJE_JMENO/debtora-cz.git
git push -u origin main

# 5. Na vercel.com → Import repo → Deploy
# → Web běží na https://debtora-cz.vercel.app

# 6. Budoucí změny
git add . && git commit -m "popis" && git push
```
