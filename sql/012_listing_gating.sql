-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 012: Gating inzerátů + tvorba přes RPC
--
-- D4/D5:
--   • Plný detail (base listings) čte jen předplatitel Inzerce NEBO vlastník/admin.
--     Bez předplatného vrátí dotaz 0 řádků → frontend ukáže CTA „Aktivovat Inzerci".
--   • Tvorba VÝHRADNĚ přes create_listing() — přímý INSERT do listings je odepřen
--     (neexistuje žádná INSERT policy pro anon/authenticated).
-- Run AFTER 011.
-- ═══════════════════════════════════════════════════════

-- ── 1. Subscriber-gated SELECT na plný detail ──
-- Nahrazuje vlastnické SELECT z 004 širší politikou (vlastník/admin + předplatitel).
drop policy if exists listings_owner_select on listings;
drop policy if exists listings_detail_subscribers on listings;
create policy listings_detail_subscribers on listings for select to authenticated
  using (
    owner_id = auth.uid()
    or is_admin(auth.uid())
    or (status = 'active' and has_active_subscription(auth.uid(), 'inzerce'))
  );

-- Pojistka: žádná INSERT policy pro anon/authenticated (z dřívějších migrací).
drop policy if exists "Authenticated users can create listings" on listings;
drop policy if exists listings_subscribers_insert on listings;
drop policy if exists listings_owner_insert on listings;

-- ═══════════════════════════════════════════════════════
-- 2. create_listing — JEDINÁ cesta tvorby inzerátu (SECURITY DEFINER).
--   1) zjisti rok,
--   2) první inzerát v roce → strhni 1 kredit (reason 'identity_first_listing')
--      a zapiš seller_identity; bez kreditu → {ok:false, error:'no_credit'},
--   3) vlož listing se status='pending' (čeká na admin moderaci),
--   4) vrať {ok, listing_id, charged, error}.
--   Další inzeráty v témže roce kredit NEstrhávají.
-- ═══════════════════════════════════════════════════════
create or replace function create_listing(p_listing jsonb)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_user    uuid := auth.uid();
  v_year    int  := extract(year from now())::int;
  v_charged boolean := false;
  v_sf      uuid := nullif(p_listing->>'storefront_id','')::uuid;
  v_id      uuid;
begin
  if v_user is null then
    return json_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  -- zadaný storefront musí patřit uživateli
  if v_sf is not null and not exists (
       select 1 from storefronts s where s.id = v_sf and s.owner_id = v_user) then
    return json_build_object('ok', false, 'error', 'storefront_not_owned');
  end if;

  -- první inzerát v roce → strhni kredit + ověř totožnost (atomicky)
  if not is_identity_verified(v_user, v_year) then
    if not spend_credits(v_user, 1, 'identity_first_listing') then
      return json_build_object('ok', false, 'error', 'no_credit');
    end if;
    insert into seller_identity (user_id, verified_year)
      values (v_user, v_year)
      on conflict (user_id, verified_year) do nothing;
    v_charged := true;
  end if;

  insert into listings (
    owner_id, storefront_id, title, type, status, price, original_value,
    discount_pct, location, category, description, contact_email, contact_phone, details
  ) values (
    v_user, v_sf,
    p_listing->>'title',
    p_listing->>'type',
    'pending',                                  -- čeká na moderaci
    nullif(p_listing->>'price','')::numeric,
    nullif(p_listing->>'original_value','')::numeric,
    nullif(p_listing->>'discount_pct','')::numeric,
    p_listing->>'location',
    p_listing->>'category',
    p_listing->>'description',
    p_listing->>'contact_email',
    p_listing->>'contact_phone',
    coalesce(p_listing->'details', '{}'::jsonb)
  ) returning id into v_id;

  return json_build_object('ok', true, 'listing_id', v_id, 'charged', v_charged);
end $$;

grant execute on function create_listing(jsonb) to authenticated;
revoke execute on function create_listing(jsonb) from anon, public;

-- ═══════════════════════════════════════════════════════
-- 3. Admin moderace (autorizace is_admin)
-- ═══════════════════════════════════════════════════════
create or replace function admin_set_listing_status(p_listing uuid, p_status text)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not is_admin(auth.uid()) then
    return json_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_status not in ('draft','pending','active','rejected','sold') then
    return json_build_object('ok', false, 'error', 'bad_status');
  end if;
  update listings set status = p_status, updated_at = now() where id = p_listing;
  return json_build_object('ok', found);
end $$;
grant execute on function admin_set_listing_status(uuid, text) to authenticated;
