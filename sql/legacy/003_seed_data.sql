-- ============================================================
-- DEBTORA CZ — Seed Data
-- Run AFTER 001_schema.sql and 002_rls_policies.sql
-- ============================================================

-- ── DEFAULT CMS CONTENT ──
-- Each block corresponds to a page, fields match data-cms attributes
INSERT INTO content (block_key, fields) VALUES

('homepage', '{
  "hero_tag": "Česká platforma pro distressed assets",
  "hero_headline": "Investujte do <em>podhodnocených aktiv</em> s důvěrou",
  "hero_desc": "DEBTORA CZ propojuje kupující a prodávající na trhu pohledávek, nemovitostí ve fire sale a OTC cenných papírů. Bezpečně, transparentně, efektivně.",
  "hero_cta": "Prohlédnout nabídky →",
  "services_tag": "Naše specializace",
  "services_headline": "Tři pilíře <em>distressed</em> investování",
  "cta_headline": "Připraveni vstoupit na trh distressed assets?",
  "cta_desc": "Zaregistrujte se a získejte přístup k exkluzivním nabídkám pohledávek, nemovitostí a OTC cenných papírů."
}'),

('about', '{
  "hero_tag": "O společnosti",
  "hero_headline": "Budujeme <em>transparentní trh</em> distressed assets",
  "hero_desc": "Od roku 2019 propojujeme investory s příležitostmi na českém trhu problémových aktiv.",
  "mission_headline": "Naše mise",
  "mission_desc": "Demokratizovat přístup k distressed assets a vytvořit důvěryhodné tržní prostředí.",
  "values_headline": "Naše hodnoty"
}'),

('pricing', '{
  "hero_tag": "Ceník",
  "hero_headline": "Transparentní <em>cenový model</em>",
  "hero_desc": "Platíte pouze za úspěšné transakce. Žádné skryté poplatky.",
  "plans_headline": "Vyberte si plán"
}'),

('contact', '{
  "hero_tag": "Kontakt",
  "hero_headline": "Spojte se <em>s námi</em>",
  "hero_desc": "Máte dotaz k nabídkám, chcete prodat pohledávku nebo hledáte investiční příležitost? Napište nám.",
  "form_headline": "Napište nám"
}'),

('howItWorks', '{
  "hero_tag": "Jak to funguje",
  "hero_headline": "Od registrace po <em>úspěšnou transakci</em>",
  "hero_desc": "Transparentní proces ve 4 krocích. Bezpečně a efektivně.",
  "steps_headline": "4 jednoduché kroky"
}'),

('services_debt', '{
  "hero_tag": "Obchodování s dluhy",
  "hero_headline": "Investice do <em>pohledávek</em> s vysokým výnosem",
  "hero_desc": "Nakupujte a prodávejte zajištěné i nezajištěné pohledávky na našem tržišti."
}'),

('services_property', '{
  "hero_tag": "Nemovitosti ve fire sale",
  "hero_headline": "Nemovitosti pod <em>tržní cenou</em>",
  "hero_desc": "Exekuční, insolvenční a REO nemovitosti se slevou 30–70 % oproti tržní ceně."
}'),

('services_otc', '{
  "hero_tag": "OTC & Pink Sheet",
  "hero_headline": "Mimoburzovní <em>cenné papíry</em>",
  "hero_desc": "Přístup k OTC, Pink Sheet a delisted akciím s potenciálem nadprůměrného zhodnocení."
}'),

('terms', '{
  "hero_tag": "Obchodní podmínky",
  "hero_headline": "Obchodní <em>podmínky</em>",
  "hero_desc": "Podmínky užívání platformy DEBTORA CZ platné od 1. ledna 2024."
}'),

('privacy', '{
  "hero_tag": "Ochrana soukromí",
  "hero_headline": "Zásady ochrany <em>osobních údajů</em>",
  "hero_desc": "Informace o zpracování osobních údajů v souladu s GDPR."
}'),

('global', '{
  "disclaimer": "⚠ Investování do distressed assets nese riziko ztráty. Minulé výnosy nezaručují budoucí výsledky.",
  "footer_desc": "Česká platforma pro obchodování s distressed assets — pohledávky, nemovitosti, OTC cenné papíry.",
  "footer_copy": "© 2024 DEBTORA CZ s.r.o. Všechna práva vyhrazena."
}');

-- ── DEFAULT SETTINGS ──
INSERT INTO settings (key, value) VALUES
('company', '{
  "name": "DEBTORA CZ s.r.o.",
  "ico": "XXX XX XXX",
  "dic": "CZ XXXXXXXX",
  "address": "Václavské náměstí 1, 110 00 Praha 1",
  "court": "Městský soud v Praze, sp. zn. C XXXXX"
}'),
('contact', '{
  "email": "info@debtora.cz",
  "phone": "+420 XXX XXX XXX",
  "privacy_email": "privacy@debtora.cz"
}');

-- ── SAMPLE LISTINGS ──
INSERT INTO listings (title, type, status, description, price, original_value, discount_pct, location, category, details) VALUES
('Balík spotřebitelských pohledávek', 'debt', 'active',
 'Portfolio 45 nezajištěných spotřebitelských pohledávek po splatnosti 12–24 měsíců. Průměrná nominální hodnota 85 000 Kč.',
 1250000, 3825000, 67.3, 'Praha', 'consumer',
 '{"count": 45, "avg_age_months": 18, "secured": false}'),

('Komerční nemovitost — exekuce', 'property', 'active',
 'Administrativní budova 1 200 m² v průmyslové zóně. Exekuční prodej, odhadní cena 18.5M Kč.',
 12500000, 18500000, 32.4, 'Brno', 'commercial',
 '{"area_sqm": 1200, "type": "office", "sale_type": "execution"}'),

('Bankovní NPL portfolio', 'debt', 'active',
 'Non-performing loans od české banky. 120 úvěrů, mix zajištěných a nezajištěných.',
 8500000, 42000000, 79.8, 'Česká republika', 'bank_npl',
 '{"count": 120, "mix": "secured+unsecured", "bank_origin": true}'),

('Byt 3+kk — insolvence', 'property', 'active',
 'Byt 78 m² v Praze 5 — Smíchov. Prodej v rámci insolvenčního řízení.',
 3200000, 5800000, 44.8, 'Praha 5', 'residential',
 '{"area_sqm": 78, "rooms": "3+kk", "sale_type": "insolvency"}'),

('Delisted akcie TechCorp a.s.', 'otc', 'active',
 'Balík 50 000 ks akcií vyřazených z BCPP. Společnost stále aktivní, roční obrat 120M Kč.',
 750000, 2500000, 70.0, 'Praha', 'delisted',
 '{"shares": 50000, "company_revenue": 120000000, "exchange": "BCPP"}'),

('Zdravotnické pohledávky', 'debt', 'pending',
 'Pohledávky za zdravotnickými zařízeními, 90+ dnů po splatnosti.',
 2100000, 6300000, 66.7, 'Morava', 'healthcare',
 '{"count": 28, "sector": "healthcare", "avg_days_overdue": 120}');

-- ── DEFAULT ADMIN USER ──
-- Password: debtora2024 (SHA-256 hash)
-- IMPORTANT: Change this immediately after first login!
INSERT INTO admin_users (username, password_hash, role) VALUES
('admin', 'a0f3285b07c26c0dcd2191447f391170d06035e8d57e31a048ba87074f3a9a15', 'admin');
