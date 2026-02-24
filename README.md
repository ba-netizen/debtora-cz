# DEBTORA CZ — Distressed Asset Marketplace

Czech marketplace for distressed assets: debt portfolios, fire-sale properties, and OTC securities.

**Stack:** Static HTML/CSS/JS + Supabase (PostgreSQL, Auth, REST API) + Vercel (hosting)

---

## Repository Structure

```
debtora-cz/
├── index.html                  # Homepage
├── trziste.html                # Marketplace with filters
├── kontakt.html                # Contact form
├── registrace.html             # User registration
├── vlozit-inzerat.html         # Submit listing
├── sluzby-dluhy.html           # Debt trading services
├── sluzby-otc.html             # OTC & Pink Sheet services
├── sluzby-nemovitosti.html     # Fire-sale property services
├── jak-to-funguje.html         # How it works
├── o-nas.html                  # About us
├── cenik.html                  # Pricing
├── podminky.html               # Terms & conditions
├── ochrana-soukromi.html       # Privacy policy (GDPR)
├── admin.html                  # Admin CMS panel (password-protected)
│
├── css/
│   └── style.css               # Shared stylesheet (all pages)
│
├── js/
│   ├── supabase-config.js      # ⚙️ YOUR Supabase credentials (edit this!)
│   ├── api.js                  # API client (Supabase queries)
│   ├── cms.js                  # CMS content loader
│   └── main.js                 # Nav, mobile menu, scroll effects, filters
│
├── sql/
│   ├── 001_schema.sql          # Database tables
│   ├── 002_rls_policies.sql    # Row Level Security
│   ├── 003_seed_data.sql       # Default content, sample listings
│   └── 004_functions.sql       # SQL functions (login, stats, views)
│
├── vercel.json                 # Vercel config (headers, clean URLs, rewrites)
├── .env.example                # Environment variables template
├── .gitignore                  # Git ignore rules
├── migrate-html.sh             # Script to update HTML script tags
└── README.md                   # This file
```

---

## Setup Guide (Step by Step)

### Step 1: Create Supabase Project

1. Go to [supabase.com](https://supabase.com) → Sign up (free)
2. Click **New Project**
3. Settings:
   - **Name:** `debtora-cz`
   - **Database Password:** choose a strong password (save it!)
   - **Region:** `Central EU (Frankfurt)` — closest to Czech Republic
4. Wait ~2 minutes for project creation

### Step 2: Get Your API Keys

1. In Supabase Dashboard → **Settings** → **API**
2. Copy these values:
   - **Project URL** → looks like `https://abcdefgh.supabase.co`
   - **anon public key** → long string starting with `eyJ...`
   - **service_role key** → SECRET key, never share publicly!

### Step 3: Configure Credentials

Edit `js/supabase-config.js`:

```javascript
window.DEBTORA_CONFIG = {
  SUPABASE_URL: 'https://abcdefgh.supabase.co',      // ← your URL
  SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIs...'       // ← your anon key
};
```

### Step 4: Run SQL Scripts

In Supabase Dashboard → **SQL Editor** → **New Query**

Run these in order (copy → paste → click Run):

| Order | File | What it does |
|-------|------|-------------|
| 1st | `sql/001_schema.sql` | Creates 6 tables with indexes and triggers |
| 2nd | `sql/002_rls_policies.sql` | Sets up Row Level Security policies |
| 3rd | `sql/003_seed_data.sql` | Loads default CMS content + sample listings |
| 4th | `sql/004_functions.sql` | Creates login, stats, and view-count functions |

**Verify:** Table Editor should show 6 tables. `content` should have 11 rows, `listings` 6 rows.

### Step 5: Migrate HTML Files (if upgrading from Netlify)

If you're upgrading from the Netlify version, run the migration script:

```bash
chmod +x migrate-html.sh
./migrate-html.sh
```

This automatically updates all `<script>` tags in your HTML files.

If starting fresh, your HTML pages should include these scripts before `</body>`:

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<script src="js/supabase-config.js"></script>
<script src="js/api.js"></script>
<script src="js/cms.js"></script>
<script src="js/main.js"></script>
</body>
```

### Step 6: Push to GitHub

```bash
# Initialize repo
git init
git add .
git commit -m "Initial commit: DEBTORA CZ with Supabase"

# Create repo on GitHub (or use GitHub CLI)
gh repo create debtora-cz --public --source=. --push

# Or manually:
git remote add origin https://github.com/YOUR_USERNAME/debtora-cz.git
git branch -M main
git push -u origin main
```

### Step 7: Deploy to Vercel

#### Option A: Vercel Dashboard (easiest)

1. Go to [vercel.com](https://vercel.com) → Sign up with GitHub
2. Click **Add New** → **Project**
3. Select your `debtora-cz` repository
4. Settings (should auto-detect):
   - **Framework Preset:** `Other`
   - **Root Directory:** `./` (leave default)
   - **Build Command:** leave empty (no build needed)
   - **Output Directory:** `./` (leave default)
5. Click **Deploy**
6. Wait ~30 seconds → Your site is live!

#### Option B: Vercel CLI

```bash
# Install Vercel CLI
npm i -g vercel

# Login
vercel login

# Deploy (first time — follow prompts)
vercel

# Deploy to production
vercel --prod
```

### Step 8: Verify

| URL | Check |
|-----|-------|
| `https://your-site.vercel.app` | Homepage loads, CMS content appears |
| `https://your-site.vercel.app/trziste` | Marketplace with listings from Supabase |
| `https://your-site.vercel.app/kontakt` | Contact form submits to Supabase |
| `https://your-site.vercel.app/admin` | Admin login works (password: `debtora2024`) |

---

## Automatic Deployments

Once connected to GitHub, **every push to `main` triggers a new deployment** on Vercel automatically. No manual deploy needed.

```bash
# Make changes → push → auto-deployed
git add .
git commit -m "Update pricing page"
git push
# → Vercel deploys automatically in ~20 seconds
```

---

## Custom Domain

### In Vercel Dashboard:
1. **Settings** → **Domains** → **Add**
2. Enter your domain: `debtora.cz`
3. Update DNS records as instructed:
   - **A Record:** `76.76.21.21`
   - **CNAME:** `cname.vercel-dns.com` (for www subdomain)
4. SSL certificate is automatic (Let's Encrypt)

---

## Admin Panel

**URL:** `https://your-site.vercel.app/admin`
**Default password:** `debtora2024`

### Change Admin Password:
In Supabase SQL Editor:
```sql
UPDATE admin_users
SET password_hash = encode(digest('YOUR_NEW_PASSWORD', 'sha256'), 'hex')
WHERE username = 'admin';
```

### Admin Features:
- Dashboard with statistics
- Listings management (approve, hide, delete)
- User management (KYC verification)
- Messages inbox
- CMS content editor (all pages)
- Site settings

---

## Managing Data via Supabase Studio

Supabase includes a built-in admin panel at your project dashboard:

| Table | What to manage |
|-------|---------------|
| `content` | Edit CMS text blocks for all pages |
| `listings` | Manage marketplace listings, change status |
| `users` | View registrations, update KYC status |
| `messages` | Read contact form submissions |
| `settings` | Update company info, contact details |
| `admin_users` | Manage admin access |

---

## Database Tables

| Table | Replaces (Netlify) | Purpose |
|-------|--------------------|---------|
| `content` | Blobs "content" | CMS editable text blocks per page |
| `settings` | Blobs "settings" | Site-wide configuration |
| `listings` | Blobs "listings" | Marketplace items with filters |
| `users` | Blobs "users" | Registered platform users |
| `messages` | Blobs "messages" | Contact form submissions |
| `admin_users` | Blobs "sessions" + env var | Admin authentication |

---

## Environment & Tools

| Component | Service | Free Tier |
|-----------|---------|-----------|
| Hosting | Vercel | 100GB bandwidth, unlimited deploys |
| Database | Supabase PostgreSQL | 500MB, unlimited API calls |
| Auth | Supabase Auth | 50,000 monthly active users |
| Storage | Supabase Storage | 1GB |
| CDN | Vercel Edge Network | Global, automatic |
| SSL | Vercel (Let's Encrypt) | Automatic |
| Domain | Any registrar | From ~$10/year |

---

## Local Development

```bash
# Serve locally
npx serve . -l 3000

# Or use Python
python3 -m http.server 3000

# Open http://localhost:3000
```

---

## License

Private project. All rights reserved.
