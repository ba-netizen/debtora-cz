-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 003: CMS (content + settings)
-- Veřejně čitelné; zápis jen admin (is_admin) nebo service role.
-- Run AFTER 002.
-- ═══════════════════════════════════════════════════════

-- ── content: editovatelné bloky obsahu ──
create table if not exists content (
  id         uuid primary key default gen_random_uuid(),
  block_key  text unique not null,          -- 'homepage', 'about', 'pricing', …
  fields     jsonb not null default '{}',
  locale     text not null default 'cs',
  updated_at timestamptz not null default now()
);
create index if not exists idx_content_block on content (block_key);

-- ── settings: globální nastavení (ceny, přepínače, kontakt) ──
create table if not exists settings (
  id         uuid primary key default gen_random_uuid(),
  key        text unique not null,
  value      jsonb not null default '{}',
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_content_updated on content;
create trigger trg_content_updated before update on content
  for each row execute function set_updated_at();
drop trigger if exists trg_settings_updated on settings;
create trigger trg_settings_updated before update on settings
  for each row execute function set_updated_at();

-- ── RLS: čtení veřejné, zápis přes admin RPC / service role ──
alter table content enable row level security;
alter table settings enable row level security;

drop policy if exists content_public_read on content;
create policy content_public_read on content for select to anon, authenticated using (true);
drop policy if exists content_service_all on content;
create policy content_service_all on content for all to service_role using (true);

drop policy if exists settings_public_read on settings;
create policy settings_public_read on settings for select to anon, authenticated using (true);
drop policy if exists settings_service_all on settings;
create policy settings_service_all on settings for all to service_role using (true);

-- ── Admin write RPC (autorizace přes is_admin, ne přes service-role klíč) ──
create or replace function admin_update_content(p_block_key text, p_fields jsonb)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not is_admin(auth.uid()) then
    return json_build_object('ok', false, 'error', 'unauthorized');
  end if;
  insert into content (block_key, fields) values (p_block_key, p_fields)
  on conflict (block_key) do update set fields = excluded.fields, updated_at = now();
  return json_build_object('ok', true);
end $$;

create or replace function admin_update_settings(p_key text, p_value jsonb)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not is_admin(auth.uid()) then
    return json_build_object('ok', false, 'error', 'unauthorized');
  end if;
  insert into settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value, updated_at = now();
  return json_build_object('ok', true);
end $$;

grant execute on function admin_update_content(text, jsonb) to authenticated;
grant execute on function admin_update_settings(text, jsonb) to authenticated;
