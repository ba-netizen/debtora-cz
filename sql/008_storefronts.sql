-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 008: Storefronty (mikrostránky /s/<slug>)
-- 1 storefront na uživatele. owner_id → auth.users (D1).
-- Insert policy používá has_active_subscription (007).
-- Run AFTER 007.
-- ═══════════════════════════════════════════════════════

create table if not exists storefronts (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null unique references auth.users on delete cascade,
  slug          text not null unique,        -- veřejná URL: /s/<slug>
  display_name  text not null,
  bio           text,
  logo_url      text,
  contact_email text,
  contact_phone text,
  status        text not null default 'draft'
                  check (status in ('draft','active','suspended')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- slug: malá písmena/číslice/pomlčka, 3–40 znaků, nezačíná/nekončí pomlčkou
alter table storefronts drop constraint if exists storefronts_slug_format;
alter table storefronts add constraint storefronts_slug_format
  check (slug ~ '^[a-z0-9](?:[a-z0-9-]{1,38}[a-z0-9])$');

create index if not exists idx_storefronts_status on storefronts (status);

drop trigger if exists trg_storefronts_updated on storefronts;
create trigger trg_storefronts_updated before update on storefronts
  for each row execute function set_updated_at();

-- Doplnit FK listings.storefront_id → storefronts (sloupec vznikl v 004).
alter table listings drop constraint if exists listings_storefront_fk;
alter table listings add constraint listings_storefront_fk
  foreign key (storefront_id) references storefronts on delete set null;

-- ── RLS ──
alter table storefronts enable row level security;

-- Aktivní storefront je veřejný; vlastník/admin vidí i svůj rozpracovaný.
drop policy if exists storefronts_public_read on storefronts;
create policy storefronts_public_read on storefronts for select to anon, authenticated
  using (status = 'active');

drop policy if exists storefronts_owner_read on storefronts;
create policy storefronts_owner_read on storefronts for select to authenticated
  using (owner_id = auth.uid() or is_admin(auth.uid()));

-- Založit smí jen vlastník s aktivním předplatným Inzerce (funkce z 006).
drop policy if exists storefronts_owner_insert on storefronts;
create policy storefronts_owner_insert on storefronts for insert to authenticated
  with check (owner_id = auth.uid() and has_active_subscription(auth.uid(), 'inzerce'));

drop policy if exists storefronts_owner_update on storefronts;
create policy storefronts_owner_update on storefronts for update to authenticated
  using (owner_id = auth.uid() or is_admin(auth.uid()))
  with check (owner_id = auth.uid() or is_admin(auth.uid()));

drop policy if exists storefronts_service_all on storefronts;
create policy storefronts_service_all on storefronts for all to service_role using (true);
