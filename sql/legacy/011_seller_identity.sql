-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 011: Ověření totožnosti přes první inzerát v roce
--
-- Pravidlo (tato verze):
--   • PRVNÍ inzerát v kalendářním roce se založí až po zaplacení
--     1 kreditu. Tato úhrada zároveň slouží jako OVĚŘENÍ TOTOŽNOSTI
--     majitele účtu (lehké KYC přes zaplacenou transakci).
--   • Další inzeráty v témže roce už kredit nestrhávají.
--   • Příští kalendářní rok se ověření (a strh kreditu) opakuje.
--
-- Run AFTER 010_storefronts_subscriptions.sql
-- ═══════════════════════════════════════════════════════

-- ── 1. Záznam ověření totožnosti (1 řádek na uživatele a rok) ──
create table if not exists seller_identity (
  user_id      uuid not null references auth.users on delete cascade,
  verified_year int  not null,
  verified_at  timestamptz not null default now(),
  payment_ref  uuid references payments,          -- volitelná vazba na úhradu
  primary key (user_id, verified_year)
);

alter table seller_identity enable row level security;

create policy "seller_identity_select_own"
  on seller_identity for select to authenticated
  using (user_id = auth.uid());

create policy "seller_identity_service_all"
  on seller_identity for all to service_role using (true);

-- ── 2. Pomocná: je majitel účtu ověřený pro daný rok? ──
create or replace function is_identity_verified(p_user uuid, p_year int default null)
returns boolean language sql stable security definer as $$
  select exists (
    select 1 from seller_identity
    where user_id = p_user
      and verified_year = coalesce(p_year, extract(year from now())::int)
  );
$$;
grant execute on function is_identity_verified(uuid, int) to authenticated, anon;

-- ── 3. Založení inzerátu = atomická transakce ──
--   1) první v roce → strhne 1 kredit + zapíše ověření totožnosti,
--   2) vloží inzerát do vlastního (volitelného) storefrontu, status = 'pending'.
--   Vrací JSON: { ok, listing_id, charged, error }.
create or replace function create_listing(p_listing jsonb)
returns json language plpgsql security definer as $$
declare
  v_user uuid := auth.uid();
  v_year int  := extract(year from now())::int;
  v_charged boolean := false;
  v_ok boolean := false;
  v_sf uuid := nullif(p_listing->>'storefront_id','')::uuid;
  v_id uuid;
begin
  if v_user is null then
    return json_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  -- storefront (pokud zadán) musí patřit uživateli
  if v_sf is not null and not exists (
       select 1 from storefronts s where s.id = v_sf and s.owner_id = v_user) then
    return json_build_object('ok', false, 'error', 'storefront_not_owned');
  end if;

  -- první inzerát v roce → strhni kredit a ověř totožnost
  if not exists (select 1 from seller_identity
                 where user_id = v_user and verified_year = v_year) then
    update user_credits
      set balance = balance - 1, updated_at = now()
      where user_id = v_user and balance > 0
      returning true into v_ok;

    if not coalesce(v_ok, false) then
      return json_build_object('ok', false, 'error', 'no_credit');
    end if;

    insert into credit_transactions (user_id, change, reason)
      values (v_user, -1, 'identity_first_listing');
    insert into seller_identity (user_id, verified_year)
      values (v_user, v_year);
    v_charged := true;
  end if;

  insert into listings (
    title, type, status, description, price, original_value, discount_pct,
    location, category, details, contact_email, contact_phone,
    user_id, storefront_id
  ) values (
    p_listing->>'title',
    p_listing->>'type',
    'pending',                                   -- čeká na moderaci adminem
    p_listing->>'description',
    nullif(p_listing->>'price','')::numeric,
    nullif(p_listing->>'original_value','')::numeric,
    nullif(p_listing->>'discount_pct','')::numeric,
    p_listing->>'location',
    p_listing->>'category',
    coalesce(p_listing->'details', '{}'::jsonb),
    p_listing->>'contact_email',
    p_listing->>'contact_phone',
    v_user,
    v_sf
  ) returning id into v_id;

  return json_build_object('ok', true, 'listing_id', v_id, 'charged', v_charged);
end $$;

grant execute on function create_listing(jsonb) to authenticated;
revoke execute on function create_listing(jsonb) from anon, public;

-- ── 4. Zrušit přímý INSERT do listings z 010 ──
--   V této verzi jde tvorba VÝHRADNĚ přes create_listing() (kvůli strhu
--   kreditu a ověření totožnosti). Přímý INSERT už nepovolujeme.
drop policy if exists "listings_subscribers_insert" on listings;
drop policy if exists "Authenticated users can create listings" on listings;

-- credit_transactions.reason nově nabývá i 'identity_first_listing'
-- (sloupec je TEXT bez CHECK — bez migrace dat).

-- ── KONEC 011 ──
-- Frontend: formulář „Vložit inzerát" volá rpc create_listing(p_listing);
--   • error 'no_credit'  → nabídni nákup kreditu (Comgate),
--   • charged = true     → potvrď „Účet ověřen pro rok <rok>",
--   • úprava/smazání běží dál přes RLS policy z 002/010.
