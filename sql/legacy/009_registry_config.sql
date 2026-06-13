-- ============================================================
-- DEBTORA CZ — 009: Konfigurace rejstříků prověrek
-- Admin může zapnout/vypnout rejstřík a nastavit cenu v kreditech
-- (0 = zdarma). Čte ji Edge Function `verify`, spravuje admin panel.
-- Run AFTER 008_payments.sql
-- ============================================================

create table if not exists registry_config (
  registry text primary key,                 -- isir | ares | dph | cee
  label text not null,
  enabled boolean not null default true,
  price_credits int not null default 0 check (price_credits >= 0),
  sort int not null default 100,
  updated_at timestamptz not null default now()
);

insert into registry_config (registry, label, enabled, price_credits, sort) values
  ('isir', 'Insolvenční rejstřík (ISIR)',          true, 0, 10),
  ('cee',  'Centrální evidence exekucí (CEE)',     true, 1, 20),
  ('ares', 'ARES — existence subjektu',            true, 0, 30),
  ('dph',  'Nespolehlivý plátce DPH (MFČR)',       true, 0, 40)
on conflict (registry) do nothing;

-- RLS: číst smí každý (frontend zobrazuje ceny), zapisovat jen service role / admin RPC
alter table registry_config enable row level security;
create policy "Anyone can read registry config"
  on registry_config for select to anon, authenticated using (true);
create policy "Service role full access to registry_config"
  on registry_config for all to service_role using (true);

-- ── Čerpání více kreditů najednou (cena per rejstřík) ──
-- Doplněk k spend_credit(uuid) z 008; volá výhradně service role ve `verify`.
create or replace function spend_credits(p_user uuid, p_amount int)
returns boolean language plpgsql security definer as $$
declare ok boolean := false;
begin
  if p_amount <= 0 then return true; end if;
  update user_credits
  set balance = balance - p_amount, updated_at = now()
  where user_id = p_user and balance >= p_amount
  returning true into ok;
  if ok then
    insert into credit_transactions (user_id, change, reason)
    values (p_user, -p_amount, 'spend_cee');
  end if;
  return coalesce(ok, false);
end $$;

revoke execute on function spend_credits(uuid, int) from public, anon, authenticated;

-- ── Admin RPC (vzor 005_admin_write_functions.sql: ověření pw_hash) ──
create or replace function admin_get_registry_config(pw_hash text)
returns json as $$
begin
  if not _verify_admin(pw_hash) then
    return json_build_object('success', false, 'error', 'Unauthorized');
  end if;
  return (
    select coalesce(json_agg(row_to_json(r) order by r.sort), '[]'::json)
    from (select registry, label, enabled, price_credits, sort from registry_config) r
  );
end;
$$ language plpgsql security definer;

create or replace function admin_update_registry_config(
  pw_hash text,
  p_registry text,
  p_enabled boolean,
  p_price int
)
returns json as $$
begin
  if not _verify_admin(pw_hash) then
    return json_build_object('success', false, 'error', 'Unauthorized');
  end if;
  if p_price < 0 then
    return json_build_object('success', false, 'error', 'Cena nesmí být záporná');
  end if;

  update registry_config
  set enabled = p_enabled, price_credits = p_price, updated_at = now()
  where registry = p_registry;

  if not found then
    return json_build_object('success', false, 'error', 'Neznámý rejstřík');
  end if;
  return json_build_object('success', true);
end;
$$ language plpgsql security definer;
