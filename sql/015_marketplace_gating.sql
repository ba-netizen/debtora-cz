-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 015: Gating tržiště podle předplatného + zprávy
--   C2: listings_preview ukáže jen položky majitele s aktivním
--       předplatným Inzerce a (pokud má storefront) aktivním storefrontem.
--       Data se NEMAŽOU — jen se skryjí; vlastník je dál vidí (policy z 012).
--   C3: zprávy smí zakládat jen přihlášený; vlastník vidí zprávy ke svým inzerátům.
-- Navazuje na 004, 007, 008, 012. Idempotentní.
-- ═══════════════════════════════════════════════════════

-- ── C2: přepočítaný veřejný náhled ──
-- Default (viz CORE-PLAN): vyžaduj aktivní předplatné majitele. Systémové
-- položky bez majitele (owner_id null, např. seed) zůstávají viditelné.
create or replace view listings_preview
with (security_invoker = false) as
  select l.id, l.owner_id, l.storefront_id, l.title, l.type, l.status,
         l.price, l.original_value, l.discount_pct, l.location, l.category,
         l.featured, l.views, l.created_at
  from listings l
  left join storefronts s on s.id = l.storefront_id
  where l.status = 'active'
    and (l.owner_id is null or has_active_subscription(l.owner_id, 'inzerce'))
    and (l.storefront_id is null or s.status = 'active');
grant select on listings_preview to anon, authenticated;

-- ── Pomocná: synchronizace storefronts.status dle předplatného (jen pro přehled) ──
-- Zdroj pravdy zůstává výpočet přes has_active_subscription; tohle jen zrcadlí stav.
create or replace function sync_storefront_status()
returns void language sql security definer set search_path = public as $$
  update storefronts s set status = 'suspended', updated_at = now()
    where s.status = 'active' and not has_active_subscription(s.owner_id, 'inzerce');
  update storefronts s set status = 'active', updated_at = now()
    where s.status = 'suspended' and has_active_subscription(s.owner_id, 'inzerce');
$$;
revoke execute on function sync_storefront_status() from public, anon, authenticated;

-- ═══════════════════════════════════════════════════════
-- C3: zprávy jen pro přihlášené + viditelnost pro vlastníka inzerátu
-- ═══════════════════════════════════════════════════════
-- Zrušit anonymní insert z 004.
drop policy if exists messages_anon_insert on messages;
drop policy if exists messages_auth_insert on messages;
create policy messages_auth_insert on messages for insert to authenticated with check (true);

-- Vlastník vidí zprávy ke svým inzerátům (vedle admin čtení z 004).
drop policy if exists messages_admin_read on messages;
drop policy if exists messages_owner_or_admin_read on messages;
create policy messages_owner_or_admin_read on messages for select to authenticated
  using (
    is_admin(auth.uid())
    or exists (select 1 from listings l where l.id = messages.listing_id and l.owner_id = auth.uid())
  );
