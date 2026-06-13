-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 013: Seed (idempotentní)
--
-- CMS obsah, globální nastavení (ceny balíčků), ukázkové aktivní inzeráty.
-- Ukázkové listingy mají owner_id = NULL (nepatří žádnému auth účtu) —
-- objeví se ve veřejném listings_preview. registry_config je v 010.
-- Run AFTER 012.
-- ═══════════════════════════════════════════════════════

-- ── CMS bloky ──
insert into content (block_key, fields) values
  ('homepage', '{"hero_headline":"Marketplace distressed aktiv","hero_desc":"Pohledávky, nemovitosti v nouzovém prodeji a OTC cenné papíry na jednom místě."}'),
  ('pricing',  '{"intro":"Inzerce na měsíční předplatné. Ověření protistrany na kredity."}'),
  ('about',    '{"title":"O Debtora CZ"}')
on conflict (block_key) do nothing;

-- ── Globální nastavení ──
insert into settings (key, value) values
  ('contact', '{"email":"info@debtora.cz","phone":"+420 000 000 000"}'),
  ('credit_packages', '[{"product":"pack5","credits":5,"price_czk":575},{"product":"pack20","credits":20,"price_czk":1880},{"product":"pack50","credits":50,"price_czk":4250}]'),
  ('services', '{"inzerce_monthly_czk":490,"single_cee_czk":122}')
on conflict (key) do nothing;

-- ── Ukázkové aktivní inzeráty (owner_id NULL) ──
insert into listings (title, type, status, price, original_value, discount_pct, location, category, description)
select * from (values
  ('Portfolio spotřebitelských pohledávek 4,2 mil. Kč', 'debt',     'active', 1260000::numeric, 4200000::numeric, 70::numeric, 'Praha',  'consumer', 'Balík 312 pohledávek po splatnosti, s exekučními tituly.'),
  ('Bytový dům v nuceném prodeji — Ostrava',            'property', 'active', 8900000::numeric, 12500000::numeric, 29::numeric, 'Ostrava', 'residential', 'Dražba, 14 bytových jednotek, výnos ~6 %.'),
  ('OTC akcie regionální e-commerce s.r.o.',            'otc',      'active', 350000::numeric,  500000::numeric,  30::numeric, 'Brno',    'equity', 'Minoritní podíl, pink-sheet, bez veřejného trhu.')
) as v(title, type, status, price, original_value, discount_pct, location, category, description)
where not exists (select 1 from listings where title = v.title);
