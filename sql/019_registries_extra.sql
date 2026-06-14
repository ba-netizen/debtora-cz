-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 019: Další rejstříky do ověřovače
--   Bezplatné/veřejné: VIES (EU DIČ), RŽP (živnost), CEÚ (úpadci),
--   Sbírka listin (link). Auth/příprava: ISDS, sankční/PEP seznamy.
--   Přiřazení úrovní + ceny se spravuje v adminu (admin_update_registry_config).
--   Výchozí úrovně jsou jen rozumný odhad — admin je přepíše.
-- Run AFTER 010. Idempotentní.
-- ═══════════════════════════════════════════════════════

insert into registry_config
  (registry, label, enabled, price_credits,
   lvl_foc_nologin, lvl_foc_login, lvl_basic, lvl_medium, lvl_full, sort) values
  ('vies',    'Ověření DIČ v EU (VIES)',           true, 0, false, false, true,  true,  true,  35),
  ('zivnost', 'Živnostenský rejstřík (RŽP)',       true, 0, false, false, true,  true,  true,  45),
  ('upadci',  'Evidence úpadců (CEÚ)',             true, 0, false, false, true,  true,  true,  55),
  ('sbirka',  'Sbírka listin / účetní závěrky',    true, 0, false, false, false, true,  true,  65),
  ('isds',    'Datová schránka (ISDS)',            true, 0, false, false, false, false, true,  75),
  ('sankce',  'Sankční a PEP seznamy',             true, 0, false, false, false, false, true,  85)
on conflict (registry) do nothing;
