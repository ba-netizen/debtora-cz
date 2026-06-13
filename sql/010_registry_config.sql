-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 010: Konfigurace rejstříků + matice úroveň × rejstřík
--
-- Sekce 6: dostupnost rejstříku dle úrovně kontroly (foc_nologin /
-- foc_login / basic / medium / full) + cena v kreditech (0 = zdarma).
-- Čte ji edge `verify`; spravuje admin panel (autorizace is_admin).
-- Run AFTER 009.
-- ═══════════════════════════════════════════════════════

create table if not exists registry_config (
  registry        text primary key,          -- ares|katastr|vozidla|cee|atp|bankid|isir|dph
  label           text not null,
  enabled         boolean not null default true,
  price_credits   int not null default 0 check (price_credits >= 0),
  -- matice dostupnosti dle úrovně
  lvl_foc_nologin boolean not null default false,
  lvl_foc_login   boolean not null default false,
  lvl_basic       boolean not null default false,
  lvl_medium      boolean not null default false,
  lvl_full        boolean not null default false,
  sort            int not null default 100,
  updated_at      timestamptz not null default now()
);

-- Výchozí matice (dle sekce 6). ISIR/DPH (živé adaptery) doplněny jako veřejné.
insert into registry_config
  (registry, label, enabled, price_credits,
   lvl_foc_nologin, lvl_foc_login, lvl_basic, lvl_medium, lvl_full, sort) values
  ('ares',    'ARES — existence a stav subjektu',     true, 0, true,  true,  true,  true,  true,  10),
  ('isir',    'Insolvenční rejstřík (ISIR)',          true, 0, true,  true,  true,  true,  true,  20),
  ('dph',     'Nespolehlivý plátce DPH (MFČR)',       true, 0, true,  true,  true,  true,  true,  30),
  ('katastr', 'Katastr nemovitostí',                  true, 1, false, false, true,  true,  true,  40),
  ('vozidla', 'Registr vozidel',                      true, 1, false, false, false, true,  true,  50),
  ('cee',     'Centrální evidence exekucí (CEE)',     true, 1, false, false, false, false, true,  60),
  ('atp',     'Další rejstříky (ATP)',                true, 1, false, false, false, false, true,  70),
  ('bankid',  'Bank iD ověření totožnosti',           true, 2, false, false, false, false, true,  80)
on conflict (registry) do nothing;

-- ── RLS: čtení veřejné (frontend zobrazuje ceny/dostupnost), zápis service role ──
alter table registry_config enable row level security;
drop policy if exists registry_config_read on registry_config;
create policy registry_config_read on registry_config for select to anon, authenticated using (true);
drop policy if exists registry_config_service_all on registry_config;
create policy registry_config_service_all on registry_config for all to service_role using (true);

-- ── Admin RPC (autorizace is_admin) ──
create or replace function admin_get_registry_config()
returns json language plpgsql security definer set search_path = public as $$
begin
  if not is_admin(auth.uid()) then
    return json_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return (select coalesce(json_agg(row_to_json(r) order by r.sort), '[]'::json)
          from registry_config r);
end $$;

create or replace function admin_update_registry_config(
  p_registry text, p_enabled boolean, p_price int,
  p_levels jsonb default null              -- {"foc_nologin":true,"basic":true,…}
) returns json language plpgsql security definer set search_path = public as $$
begin
  if not is_admin(auth.uid()) then
    return json_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_price < 0 then
    return json_build_object('ok', false, 'error', 'negative_price');
  end if;

  update registry_config set
    enabled         = p_enabled,
    price_credits   = p_price,
    lvl_foc_nologin = coalesce((p_levels->>'foc_nologin')::boolean, lvl_foc_nologin),
    lvl_foc_login   = coalesce((p_levels->>'foc_login')::boolean,   lvl_foc_login),
    lvl_basic       = coalesce((p_levels->>'basic')::boolean,       lvl_basic),
    lvl_medium      = coalesce((p_levels->>'medium')::boolean,      lvl_medium),
    lvl_full        = coalesce((p_levels->>'full')::boolean,        lvl_full),
    updated_at      = now()
  where registry = p_registry;

  if not found then return json_build_object('ok', false, 'error', 'unknown_registry'); end if;
  return json_build_object('ok', true);
end $$;

grant execute on function admin_get_registry_config() to authenticated;
grant execute on function admin_update_registry_config(text, boolean, int, jsonb) to authenticated;
