-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 004: Marketplace (listings, soubory, zprávy)
--
-- D4: marketingové sloupce × citlivé sloupce jsou v jedné tabulce,
--     ale ODDĚLENÍ se realizuje projekcí: veřejný `listings_preview`
--     (jen marketing) vs. base `listings` (plný detail, gated v 012).
-- owner_id → auth.users (D1). storefront_id se doplní v 005.
-- Run AFTER 003.
-- ═══════════════════════════════════════════════════════

create table if not exists listings (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid references auth.users on delete set null,
  -- FK na storefronts se doplní v 005 (storefronts vzniká později).
  storefront_id  uuid,
  -- ── MARKETINGOVÉ sloupce (veřejný náhled) ──
  title          text not null,
  type           text not null check (type in ('debt','property','otc')),
  status         text not null default 'draft'
                   check (status in ('draft','pending','active','rejected','sold')),
  price          numeric(15,2),
  original_value numeric(15,2),
  discount_pct   numeric(5,2),
  location       text,
  category       text,
  featured       boolean not null default false,
  views          integer not null default 0,
  -- ── CITLIVÉ sloupce (jen detail pro předplatitele/vlastníka) ──
  description    text,
  contact_email  text,
  contact_phone  text,
  details        jsonb not null default '{}',
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists idx_listings_type on listings (type);
create index if not exists idx_listings_status on listings (status);
create index if not exists idx_listings_created on listings (created_at desc);
create index if not exists idx_listings_owner on listings (owner_id);
create index if not exists idx_listings_storefront on listings (storefront_id);
create index if not exists idx_listings_featured on listings (featured) where featured = true;

drop trigger if exists trg_listings_updated on listings;
create trigger trg_listings_updated before update on listings
  for each row execute function set_updated_at();

-- ── Přílohy k inzerátu (storage reference) ──
create table if not exists listing_files (
  id          uuid primary key default gen_random_uuid(),
  listing_id  uuid not null references listings on delete cascade,
  file_name   text not null,
  file_url    text not null,                 -- public URL ve Storage bucketu 'listing-files'
  file_type   text not null default 'image' check (file_type in ('image','document','other')),
  file_size   integer not null default 0,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now()
);
create index if not exists idx_listing_files_listing on listing_files (listing_id);

-- ── Zprávy / poptávky k inzerátu (i obecný kontakt) ──
create table if not exists messages (
  id          uuid primary key default gen_random_uuid(),
  listing_id  uuid references listings on delete set null,
  name        text not null,
  email       text not null,
  phone       text,
  company     text,
  type        text not null default 'general'
                check (type in ('general','buy','sell','partnership')),
  message     text not null,
  is_read     boolean not null default false,
  notes       text,
  created_at  timestamptz not null default now()
);
create index if not exists idx_messages_read on messages (is_read);
create index if not exists idx_messages_created on messages (created_at desc);

-- ── Inkrementace zhlédnutí (volá frontend i create-flow) ──
create or replace function increment_views(p_listing uuid)
returns void language sql security definer set search_path = public as $$
  update listings set views = views + 1 where id = p_listing;
$$;
grant execute on function increment_views(uuid) to anon, authenticated;

-- ═══════════════════════════════════════════════════════
-- RLS
-- POZN.: subscriber-gated SELECT na plný detail + zákaz přímého
-- INSERT (create_listing) jsou v 012 (závisí na 006 subscriptions).
-- ═══════════════════════════════════════════════════════
alter table listings enable row level security;
alter table listing_files enable row level security;
alter table messages enable row level security;

-- Vlastník čte/edituje/maže svoje; admin vše; service role vše.
drop policy if exists listings_owner_select on listings;
create policy listings_owner_select on listings for select to authenticated
  using (owner_id = auth.uid() or is_admin(auth.uid()));

drop policy if exists listings_owner_update on listings;
create policy listings_owner_update on listings for update to authenticated
  using (owner_id = auth.uid() or is_admin(auth.uid()))
  with check (owner_id = auth.uid() or is_admin(auth.uid()));

drop policy if exists listings_owner_delete on listings;
create policy listings_owner_delete on listings for delete to authenticated
  using (owner_id = auth.uid() or is_admin(auth.uid()));

drop policy if exists listings_service_all on listings;
create policy listings_service_all on listings for all to service_role using (true);

-- Přílohy: veřejné čtení (k aktivním náhledům), správa jen vlastník/admin/service.
drop policy if exists listing_files_public_read on listing_files;
create policy listing_files_public_read on listing_files for select to anon, authenticated using (true);

drop policy if exists listing_files_owner_write on listing_files;
create policy listing_files_owner_write on listing_files for all to authenticated
  using (exists (select 1 from listings l where l.id = listing_id
                 and (l.owner_id = auth.uid() or is_admin(auth.uid()))))
  with check (exists (select 1 from listings l where l.id = listing_id
                 and (l.owner_id = auth.uid() or is_admin(auth.uid()))));

drop policy if exists listing_files_service_all on listing_files;
create policy listing_files_service_all on listing_files for all to service_role using (true);

-- Zprávy: kdokoliv odešle; čte jen admin / service role.
drop policy if exists messages_anon_insert on messages;
create policy messages_anon_insert on messages for insert to anon, authenticated with check (true);
drop policy if exists messages_admin_read on messages;
create policy messages_admin_read on messages for select to authenticated using (is_admin(auth.uid()));
drop policy if exists messages_service_all on messages;
create policy messages_service_all on messages for all to service_role using (true);

-- ═══════════════════════════════════════════════════════
-- listings_preview — veřejný NÁHLED (jen marketingové sloupce).
-- security_invoker = false → view běží s právy vlastníka (obchází RLS
-- base tabulky) → čte ho i anonym bez předplatného. ŽÁDNÉ citlivé sloupce.
-- ═══════════════════════════════════════════════════════
create or replace view listings_preview
with (security_invoker = false) as
  select id, owner_id, storefront_id, title, type, status,
         price, original_value, discount_pct, location, category,
         featured, views, created_at
  from listings
  where status = 'active';
grant select on listings_preview to anon, authenticated;
