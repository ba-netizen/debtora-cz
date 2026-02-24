-- ╔══════════════════════════════════════════════════════════════╗
-- ║  DEBTORA CZ — KOMPLETNÍ DATABÁZE                          ║
-- ║  Spusť celý tento soubor najednou v Supabase SQL Editoru   ║
-- ╚══════════════════════════════════════════════════════════════╝

-- ============================================================
-- ČÁST 1: SCHEMA — Tabulky, indexy, triggery
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── CONTENT (CMS editovatelné bloky) ──
CREATE TABLE IF NOT EXISTS content (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  block_key TEXT UNIQUE NOT NULL,
  fields JSONB NOT NULL DEFAULT '{}',
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── SETTINGS (nastavení webu) ──
CREATE TABLE IF NOT EXISTS settings (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  key TEXT UNIQUE NOT NULL,
  value JSONB NOT NULL DEFAULT '{}',
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── USERS (registrovaní uživatelé) ──
CREATE TABLE IF NOT EXISTS users (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  name TEXT,
  company TEXT,
  ico TEXT,
  phone TEXT,
  account_type TEXT DEFAULT 'buyer' CHECK (account_type IN ('buyer', 'seller', 'both', 'broker')),
  kyc_status TEXT DEFAULT 'unverified' CHECK (kyc_status IN ('unverified', 'pending', 'verified', 'rejected')),
  kyc_notes TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── LISTINGS (inzeráty na tržišti) ──
CREATE TABLE IF NOT EXISTS listings (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  title TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('debt', 'property', 'otc')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('active', 'pending', 'sold', 'hidden', 'expired')),
  description TEXT,
  price NUMERIC(15,2),
  original_value NUMERIC(15,2),
  discount_pct NUMERIC(5,2),
  location TEXT,
  category TEXT,
  details JSONB DEFAULT '{}',
  contact_email TEXT,
  contact_phone TEXT,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  featured BOOLEAN DEFAULT FALSE,
  views INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── MESSAGES (kontaktní formuláře) ──
CREATE TABLE IF NOT EXISTS messages (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT,
  company TEXT,
  type TEXT DEFAULT 'general',
  message TEXT NOT NULL,
  is_read BOOLEAN DEFAULT FALSE,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── ADMIN USERS (přístupy do admin panelu) ──
CREATE TABLE IF NOT EXISTS admin_users (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  role TEXT DEFAULT 'admin' CHECK (role IN ('admin', 'editor')),
  last_login TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── INDEXY ──
CREATE INDEX IF NOT EXISTS idx_listings_type ON listings(type);
CREATE INDEX IF NOT EXISTS idx_listings_status ON listings(status);
CREATE INDEX IF NOT EXISTS idx_listings_created ON listings(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_listings_featured ON listings(featured) WHERE featured = TRUE;
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_kyc ON users(kyc_status);
CREATE INDEX IF NOT EXISTS idx_messages_read ON messages(is_read);
CREATE INDEX IF NOT EXISTS idx_messages_created ON messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_content_block ON content(block_key);

-- ── AUTO-UPDATE TIMESTAMPS ──
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_content_updated ON content;
CREATE TRIGGER trg_content_updated BEFORE UPDATE ON content
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS trg_settings_updated ON settings;
CREATE TRIGGER trg_settings_updated BEFORE UPDATE ON settings
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS trg_listings_updated ON listings;
CREATE TRIGGER trg_listings_updated BEFORE UPDATE ON listings
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS trg_users_updated ON users;
CREATE TRIGGER trg_users_updated BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── ADMIN STATS VIEW ──
CREATE OR REPLACE VIEW admin_stats AS
SELECT
  (SELECT COUNT(*) FROM listings) AS total_listings,
  (SELECT COUNT(*) FROM listings WHERE status = 'active') AS active_listings,
  (SELECT COUNT(*) FROM listings WHERE status = 'pending') AS pending_listings,
  (SELECT COUNT(*) FROM users) AS total_users,
  (SELECT COUNT(*) FROM users WHERE kyc_status = 'verified') AS verified_users,
  (SELECT COUNT(*) FROM messages) AS total_messages,
  (SELECT COUNT(*) FROM messages WHERE is_read = FALSE) AS unread_messages;


-- ============================================================
-- ČÁST 2: ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE content ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE listings ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;

-- Veřejné čtení: CMS obsah, nastavení
CREATE POLICY "content_public_read" ON content FOR SELECT TO anon USING (true);
CREATE POLICY "settings_public_read" ON settings FOR SELECT TO anon USING (true);

-- Veřejné čtení: pouze aktivní inzeráty
CREATE POLICY "listings_public_read" ON listings FOR SELECT TO anon USING (status = 'active');

-- Kdokoliv může odeslat zprávu (kontaktní formulář)
CREATE POLICY "messages_public_insert" ON messages FOR INSERT TO anon WITH CHECK (true);

-- Kdokoliv může vytvořit uživatelský účet (registrace)
CREATE POLICY "users_public_register" ON users FOR INSERT TO anon WITH CHECK (true);

-- Anon může číst uživatele (pro login RPC)
CREATE POLICY "users_anon_read" ON users FOR SELECT TO anon USING (true);

-- Anon může číst všechny inzeráty přes RPC
CREATE POLICY "listings_anon_all" ON listings FOR SELECT TO anon USING (true);

-- Service role (admin): plný přístup
CREATE POLICY "content_service_all" ON content FOR ALL TO service_role USING (true);
CREATE POLICY "settings_service_all" ON settings FOR ALL TO service_role USING (true);
CREATE POLICY "listings_service_all" ON listings FOR ALL TO service_role USING (true);
CREATE POLICY "users_service_all" ON users FOR ALL TO service_role USING (true);
CREATE POLICY "messages_service_all" ON messages FOR ALL TO service_role USING (true);
CREATE POLICY "admin_users_service_all" ON admin_users FOR ALL TO service_role USING (true);

-- Anon může číst admin_users (pro login RPC)
CREATE POLICY "admin_users_anon_read" ON admin_users FOR SELECT TO anon USING (true);

-- Anon delete/update pro admin operace přes dashboard
CREATE POLICY "listings_anon_update" ON listings FOR UPDATE TO anon USING (true);
CREATE POLICY "listings_anon_delete" ON listings FOR DELETE TO anon USING (true);
CREATE POLICY "users_anon_update" ON users FOR UPDATE TO anon USING (true);
CREATE POLICY "users_anon_delete" ON users FOR DELETE TO anon USING (true);
CREATE POLICY "messages_anon_read" ON messages FOR SELECT TO anon USING (true);
CREATE POLICY "messages_anon_update" ON messages FOR UPDATE TO anon USING (true);
CREATE POLICY "messages_anon_delete" ON messages FOR DELETE TO anon USING (true);
CREATE POLICY "content_anon_update" ON content FOR UPDATE TO anon USING (true);
CREATE POLICY "settings_anon_update" ON settings FOR UPDATE TO anon USING (true);


-- ============================================================
-- ČÁST 3: VÝCHOZÍ DATA (CMS obsah, inzeráty, admin)
-- ============================================================

-- ── CMS OBSAH ──
INSERT INTO content (block_key, fields) VALUES
('homepage', '{
  "hero_tag": "Česká platforma pro distressed assets",
  "hero_headline": "Investujte do <em>podhodnocených aktiv</em> s důvěrou",
  "hero_desc": "DEBTORA CZ propojuje kupující a prodávající na trhu pohledávek, nemovitostí ve fire sale a OTC cenných papírů.",
  "hero_cta": "Prohlédnout nabídky →",
  "services_tag": "Naše specializace",
  "services_headline": "Tři pilíře <em>distressed</em> investování",
  "cta_headline": "Připraveni vstoupit na trh distressed assets?",
  "cta_desc": "Zaregistrujte se a získejte přístup k exkluzivním nabídkám."
}'),
('about', '{
  "hero_tag": "O společnosti",
  "hero_headline": "Budujeme <em>transparentní trh</em> distressed assets",
  "hero_desc": "Od roku 2019 propojujeme investory s příležitostmi na českém trhu.",
  "mission_headline": "Naše mise",
  "mission_desc": "Demokratizovat přístup k distressed assets a vytvořit důvěryhodné tržní prostředí."
}'),
('pricing', '{
  "hero_tag": "Ceník",
  "hero_headline": "Transparentní <em>cenový model</em>",
  "hero_desc": "Platíte pouze za úspěšné transakce. Žádné skryté poplatky."
}'),
('contact', '{
  "hero_tag": "Kontakt",
  "hero_headline": "Spojte se <em>s námi</em>",
  "hero_desc": "Máte dotaz k nabídkám? Napište nám."
}'),
('howItWorks', '{
  "hero_tag": "Jak to funguje",
  "hero_headline": "Od registrace po <em>úspěšnou transakci</em>",
  "hero_desc": "Transparentní proces ve 4 krocích."
}'),
('services_debt', '{
  "hero_tag": "Obchodování s dluhy",
  "hero_headline": "Investice do <em>pohledávek</em> s vysokým výnosem",
  "hero_desc": "Nakupujte a prodávejte pohledávky na našem tržišti."
}'),
('services_property', '{
  "hero_tag": "Nemovitosti ve fire sale",
  "hero_headline": "Nemovitosti pod <em>tržní cenou</em>",
  "hero_desc": "Exekuční a insolvenční nemovitosti se slevou 30–70 %."
}'),
('services_otc', '{
  "hero_tag": "OTC & Pink Sheet",
  "hero_headline": "Mimoburzovní <em>cenné papíry</em>",
  "hero_desc": "Přístup k OTC, Pink Sheet a delisted akciím."
}'),
('terms', '{
  "hero_tag": "Obchodní podmínky",
  "hero_headline": "Obchodní <em>podmínky</em>",
  "hero_desc": "Podmínky užívání platformy DEBTORA CZ."
}'),
('privacy', '{
  "hero_tag": "Ochrana soukromí",
  "hero_headline": "Zásady ochrany <em>osobních údajů</em>",
  "hero_desc": "Zpracování osobních údajů dle GDPR."
}'),
('global', '{
  "disclaimer": "Investování do distressed assets nese riziko ztráty. DEBTORA CZ není investiční poradce.",
  "footer_desc": "Česká platforma pro obchodování s distressed assets.",
  "footer_copy": "© 2024 DEBTORA CZ s.r.o. Všechna práva vyhrazena."
}'),
('marketplace', '{
  "hero_tag": "Tržiště",
  "hero_headline": "Aktuální nabídky <em>distressed assets</em>",
  "hero_desc": "Procházejte pohledávky, nemovitosti a OTC cenné papíry."
}');

-- ── NASTAVENÍ ──
INSERT INTO settings (key, value) VALUES
('company', '{
  "name": "DEBTORA CZ s.r.o.",
  "ico": "XXX XX XXX",
  "dic": "CZ XXXXXXXX",
  "address": "Václavské náměstí 1, 110 00 Praha 1",
  "court": "Městský soud v Praze"
}'),
('contact', '{
  "email": "info@debtora.cz",
  "phone": "+420 XXX XXX XXX",
  "privacy_email": "privacy@debtora.cz"
}');

-- ── UKÁZKOVÉ INZERÁTY ──
INSERT INTO listings (title, type, status, description, price, original_value, discount_pct, location, category, contact_email, details) VALUES
('Balík spotřebitelských pohledávek', 'debt', 'active',
 '45 nezajištěných spotřebitelských pohledávek po splatnosti 12–24 měsíců. Průměrná nominální hodnota 85 000 Kč. Dlužníci z celé ČR.',
 1250000, 3825000, 67.3, 'Praha', 'consumer', 'prodej@debtora.cz',
 '{"count": 45, "avg_age_months": 18, "secured": false}'),

('Administrativní budova — exekuce', 'property', 'active',
 'Administrativní budova 1 200 m² v průmyslové zóně Brno-Slatina. Exekuční prodej. Odhadní cena 18.5M Kč. Budova je plně funkční s vlastním parkovištěm.',
 12500000, 18500000, 32.4, 'Brno', 'commercial', 'nemovitosti@debtora.cz',
 '{"area_sqm": 1200, "type": "office", "sale_type": "execution"}'),

('Bankovní NPL portfolio', 'debt', 'active',
 'Non-performing loans od české banky. 120 úvěrů, mix zajištěných (40%) a nezajištěných (60%). Průměrné stáří 24 měsíců.',
 8500000, 42000000, 79.8, 'Česká republika', 'bank_npl', 'npl@debtora.cz',
 '{"count": 120, "mix": "secured+unsecured", "bank_origin": true}'),

('Byt 3+kk — insolvence', 'property', 'active',
 'Byt 78 m² v Praze 5 — Smíchov. Prodej v rámci insolvenčního řízení. Cihlový dům, 3. patro s výtahem, balkón.',
 3200000, 5800000, 44.8, 'Praha 5', 'residential', 'nemovitosti@debtora.cz',
 '{"area_sqm": 78, "rooms": "3+kk", "sale_type": "insolvency"}'),

('Delisted akcie TechCorp a.s.', 'otc', 'active',
 '50 000 ks akcií vyřazených z BCPP. Společnost TechCorp a.s. je stále aktivní s ročním obratem 120M Kč. Dividendový výnos 4.2%.',
 750000, 2500000, 70.0, 'Praha', 'delisted', 'otc@debtora.cz',
 '{"shares": 50000, "company_revenue": 120000000, "exchange": "BCPP"}'),

('Zdravotnické pohledávky', 'debt', 'active',
 '28 pohledávek za zdravotnickými zařízeními po splatnosti 90+ dnů. Dlužníci jsou nemocnice a polikliniky.',
 2100000, 6300000, 66.7, 'Morava', 'healthcare', 'prodej@debtora.cz',
 '{"count": 28, "sector": "healthcare", "avg_days_overdue": 120}'),

('Skladový areál — dražba', 'property', 'active',
 '2 500 m² skladových prostor s kancelářemi a parkovištěm v Ostravě. Prodej formou dobrovolné dražby.',
 5800000, 9800000, 40.8, 'Ostrava', 'industrial', 'nemovitosti@debtora.cz',
 '{"area_sqm": 2500, "type": "warehouse", "sale_type": "auction"}'),

('Pink Sheet — BioNova Inc.', 'otc', 'active',
 'Nano-cap biotech společnost ve fázi 2 klinických studií. Ticker BVNA na OTC Markets. Potenciální partner pro reverse merger.',
 420000, 1000000, 58.0, 'USA / OTC Markets', 'pink_sheet', 'otc@debtora.cz',
 '{"ticker": "BVNA", "market_cap": "nano-cap", "phase": "clinical_2"}'),

('Firemní pohledávky — stavebnictví', 'debt', 'active',
 '12 pohledávek za stavebními firmami. Celková nominální hodnota 8.2M Kč. Mix zajištěných bankovními zárukami a nezajištěných.',
 3400000, 8200000, 58.5, 'Středočeský kraj', 'b2b', 'prodej@debtora.cz',
 '{"count": 12, "sector": "construction", "total_nominal": 8200000}');

-- ── ADMIN ÚČET ──
-- Heslo: debtora2024
-- ZMĚŇ IHNED PO PRVNÍM PŘIHLÁŠENÍ!
INSERT INTO admin_users (username, password_hash, role) VALUES
('admin', '275655e6c91a4b36f50a75a110b00f4de359c7a64ecfe304c7ca3a03a20ca4ec', 'admin');


-- ============================================================
-- ČÁST 4: SQL FUNKCE (RPC)
-- ============================================================

-- ── Zvýšení počtu zhlédnutí ──
CREATE OR REPLACE FUNCTION increment_views(listing_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE listings SET views = views + 1 WHERE id = listing_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Admin přihlášení ──
CREATE OR REPLACE FUNCTION admin_login(pw_hash TEXT)
RETURNS JSON AS $$
DECLARE
  admin_record RECORD;
BEGIN
  SELECT * INTO admin_record FROM admin_users
  WHERE password_hash = pw_hash LIMIT 1;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Nesprávné heslo');
  END IF;

  UPDATE admin_users SET last_login = NOW() WHERE id = admin_record.id;

  RETURN json_build_object(
    'success', true,
    'username', admin_record.username,
    'role', admin_record.role
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Dashboard statistiky ──
CREATE OR REPLACE FUNCTION get_admin_stats()
RETURNS JSON AS $$
BEGIN
  RETURN json_build_object(
    'total_listings', (SELECT COUNT(*) FROM listings),
    'active_listings', (SELECT COUNT(*) FROM listings WHERE status = 'active'),
    'pending_listings', (SELECT COUNT(*) FROM listings WHERE status = 'pending'),
    'total_users', (SELECT COUNT(*) FROM users),
    'verified_users', (SELECT COUNT(*) FROM users WHERE kyc_status = 'verified'),
    'total_messages', (SELECT COUNT(*) FROM messages),
    'unread_messages', (SELECT COUNT(*) FROM messages WHERE is_read = FALSE),
    'total_value', (SELECT COALESCE(SUM(price), 0) FROM listings WHERE status = 'active')
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Uživatelské přihlášení ──
CREATE OR REPLACE FUNCTION user_login(user_email TEXT, pw_hash TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  found_user RECORD;
BEGIN
  SELECT id, email, name, company, phone, ico, account_type, kyc_status, created_at
  INTO found_user
  FROM users
  WHERE email = user_email AND password_hash = pw_hash;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Nesprávný e-mail nebo heslo.');
  END IF;

  RETURN json_build_object(
    'success', true,
    'user', json_build_object(
      'id', found_user.id,
      'email', found_user.email,
      'name', found_user.name,
      'company', found_user.company,
      'phone', found_user.phone,
      'ico', found_user.ico,
      'account_type', found_user.account_type,
      'kyc_status', found_user.kyc_status,
      'created_at', found_user.created_at
    )
  );
END;
$$;

-- ── Detail inzerátu (se zvýšením views) ──
CREATE OR REPLACE FUNCTION get_listing_detail(listing_uuid UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  found RECORD;
BEGIN
  UPDATE listings SET views = COALESCE(views, 0) + 1 WHERE id = listing_uuid;
  SELECT * INTO found FROM listings WHERE id = listing_uuid;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Inzerát nenalezen.');
  END IF;

  RETURN json_build_object('success', true, 'listing', row_to_json(found));
END;
$$;

-- ── OPRÁVNĚNÍ ──
GRANT EXECUTE ON FUNCTION increment_views TO anon;
GRANT EXECUTE ON FUNCTION admin_login TO anon;
GRANT EXECUTE ON FUNCTION get_admin_stats TO anon;
GRANT EXECUTE ON FUNCTION user_login TO anon;
GRANT EXECUTE ON FUNCTION get_listing_detail TO anon;


-- ============================================================
-- ✅ HOTOVO!
-- Měl bys vidět v Table Editoru:
--   content    → 12 řádků
--   listings   → 9 řádků
--   settings   → 2 řádky
--   admin_users → 1 řádek
--   users      → prázdná
--   messages   → prázdná
-- ============================================================
