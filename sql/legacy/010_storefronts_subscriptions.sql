-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 010: Storefronty + Předplatné služby Inzerce
-- Dynamický multi-tenant marketplace:
--   • každý uživatel s aktivním předplatným "inzerce" má vlastní
--     storefront (mikrostránku) a publikuje pod ní položky,
--   • detail cizích inzerátů je zamčený bez předplatného (jen náhled).
--
-- Run AFTER 009_registry_config.sql
--
-- ⚠ PREREKVIZITA / nesoulad identit:
--   listings.user_id (z 001) odkazuje na LEGACY tabulku `users`
--   (vlastní login z Netlify migrace). Ověření/kredity (007–009) i
--   tato migrace stojí na Supabase `auth.users` (auth.uid()).
--   Než půjde gating ostře nasadit, je třeba listings navázat na
--   auth.users — viz krok 6 (listings.owner_id) + datová migrace.
-- ═══════════════════════════════════════════════════════

-- ── 1. STOREFRONTY (mikrostránky uživatelů) ──
create table if not exists storefronts (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null unique references auth.users on delete cascade,
  slug          text not null unique,                    -- veřejná URL: /s/<slug>
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
-- slug: malá písmena, číslice, pomlčka, 3–40 znaků
alter table storefronts
  add constraint storefronts_slug_format
  check (slug ~ '^[a-z0-9](?:[a-z0-9-]{1,38}[a-z0-9])$');

create index if not exists idx_storefronts_status on storefronts (status);

-- ── 2. PŘEDPLATNÉ SLUŽEB (zatím jen 'inzerce', rozšiřitelné) ──
create table if not exists subscriptions (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null references auth.users on delete cascade,
  service              text not null check (service in ('inzerce')),
  status               text not null default 'active'
                         check (status in ('active','past_due','cancelled','expired')),
  current_period_start timestamptz not null default now(),
  current_period_end   timestamptz not null,             -- aktivní, dokud > now()
  auto_renew           boolean not null default true,
  payment_id           uuid references payments,         -- poslední úhrada období
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  unique (user_id, service)                              -- 1 aktivní předplatné / služba
);
create index if not exists idx_subscriptions_user on subscriptions (user_id);
create index if not exists idx_subscriptions_active
  on subscriptions (service, current_period_end) where status = 'active';

-- ── 3. Vazba položky na storefront ──
alter table listings
  add column if not exists storefront_id uuid references storefronts on delete set null;
create index if not exists idx_listings_storefront on listings (storefront_id);

-- ── 4. Rozšíření platebních produktů o předplatné ──
alter table payments drop constraint if exists payments_product_check;
alter table payments add constraint payments_product_check
  check (product in ('single','pack5','pack20','sub_inzerce_monthly'));

-- ── 5. Helper: má uživatel aktivní předplatné dané služby? ──
-- Používá se uvnitř RLS i ve frontendu (gating UI).
create or replace function has_active_subscription(p_user uuid, p_service text)
returns boolean language sql stable security definer as $$
  select exists (
    select 1 from subscriptions s
    where s.user_id = p_user
      and s.service = p_service
      and s.status  = 'active'
      and s.current_period_end > now()
  );
$$;
grant execute on function has_active_subscription(uuid, text) to authenticated, anon;

-- ── 6. Aktivace / prodloužení předplatného (volá jen service role z payment-callback) ──
create or replace function activate_subscription(
  p_user uuid, p_service text, p_months int, p_payment uuid default null
) returns void language plpgsql security definer as $$
declare v_base timestamptz;
begin
  -- prodlužuje od konce stávajícího období, pokud ještě běží, jinak od teď
  select greatest(now(), coalesce(current_period_end, now()))
    into v_base
  from subscriptions where user_id = p_user and service = p_service;

  insert into subscriptions (user_id, service, status, current_period_start,
                             current_period_end, payment_id)
  values (p_user, p_service, 'active', now(),
          coalesce(v_base, now()) + make_interval(months => p_months), p_payment)
  on conflict (user_id, service) do update
    set status              = 'active',
        current_period_end  = coalesce(subscriptions.current_period_end, now())
                                + make_interval(months => p_months),
        payment_id          = excluded.payment_id,
        updated_at          = now();
end $$;
revoke execute on function activate_subscription(uuid, text, int, uuid)
  from public, anon, authenticated;

-- ═══════════════════════════════════════════════════════
-- 7. RLS — storefronty
-- ═══════════════════════════════════════════════════════
alter table storefronts enable row level security;

create policy "storefronts_public_read_active"
  on storefronts for select to anon, authenticated
  using (status = 'active');

create policy "storefronts_owner_read"
  on storefronts for select to authenticated
  using (owner_id = auth.uid());

-- Založit storefront smí jen uživatel s aktivním předplatným Inzerce
create policy "storefronts_owner_insert"
  on storefronts for insert to authenticated
  with check (owner_id = auth.uid()
              and has_active_subscription(auth.uid(), 'inzerce'));

create policy "storefronts_owner_update"
  on storefronts for update to authenticated
  using (owner_id = auth.uid());

create policy "storefronts_service_all"
  on storefronts for all to service_role using (true);

-- ═══════════════════════════════════════════════════════
-- 8. RLS — subscriptions (čte vlastník; zapisuje jen service role)
-- ═══════════════════════════════════════════════════════
alter table subscriptions enable row level security;

create policy "subscriptions_select_own"
  on subscriptions for select to authenticated
  using (user_id = auth.uid());

create policy "subscriptions_service_all"
  on subscriptions for all to service_role using (true);

-- ═══════════════════════════════════════════════════════
-- 9. Gating DETAILU inzerátů
--   • Veřejný NÁHLED  → view listings_preview (omezené sloupce, bez RLS)
--   • Plný DETAIL     → base table listings, jen pro předplatitele/vlastníka
-- ═══════════════════════════════════════════════════════

-- 9a. Náhledový view — jen marketingové sloupce, žádné kontakty/popis/details.
--     View je vlastněný adminem (postgres) → obchází RLS (security_invoker = off),
--     proto vrací náhled i anonymům. Detailní sloupce zde NEJSOU.
create or replace view listings_preview
with (security_invoker = false) as
  select id, title, type, status, price, original_value, discount_pct,
         location, category, featured, views, storefront_id, created_at
  from listings
  where status = 'active';
grant select on listings_preview to anon, authenticated;

-- 9b. Zpřísnit přístup k base tabulce listings (nahradit šir
--     "vše aktivní čte kdokoliv" z 002).
drop policy if exists "Active listings are publicly readable" on listings;
drop policy if exists "Authenticated users read active listings" on listings;
drop policy if exists "Authenticated users can create listings" on listings;

-- Plný detail: aktivní inzerát smí číst jen předplatitel Inzerce,
-- nebo vlastník (legacy user_id; po migraci nahradit owner_id = auth.uid()),
-- service role má plný přístup z 002.
create policy "listings_full_detail_subscribers"
  on listings for select to authenticated
  using (
    (status = 'active' and has_active_subscription(auth.uid(), 'inzerce'))
    or user_id = auth.uid()
  );

-- Publikovat položku smí jen uživatel s aktivním předplatným Inzerce,
-- a jen do vlastního storefrontu.
create policy "listings_subscribers_insert"
  on listings for insert to authenticated
  with check (
    has_active_subscription(auth.uid(), 'inzerce')
    and user_id = auth.uid()
    and (storefront_id is null
         or exists (select 1 from storefronts s
                    where s.id = storefront_id and s.owner_id = auth.uid()))
  );

-- ── KONEC 010 ──
-- Navazující úkoly (mimo tuto migraci):
--   • payment-callback: po úhradě 'sub_inzerce_monthly' volat
--       select activate_subscription(user, 'inzerce', 1, payment_id);
--   • frontend: marketplace grid čte listings_preview; detail čte listings
--       (při 0 řádcích → zobrazit CTA „Aktivovat Inzerci");
--   • prerekvizita: navázat listings na auth.users (owner_id) + datová migrace.
