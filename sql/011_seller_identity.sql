-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 011: Ověření totožnosti prodejce (per rok)
--
-- Důkaz, že účet byl v daném kalendářním roce ověřen (lehké KYC přes
-- zaplacený 1. inzerát roku — viz create_listing v 012). 1 řádek / rok.
-- Run AFTER 010.
-- ═══════════════════════════════════════════════════════

create table if not exists seller_identity (
  user_id       uuid not null references auth.users on delete cascade,
  verified_year int  not null,
  verified_at   timestamptz not null default now(),
  payment_ref   uuid references payments on delete set null,
  primary key (user_id, verified_year)
);

alter table seller_identity enable row level security;
drop policy if exists seller_identity_select_own on seller_identity;
create policy seller_identity_select_own on seller_identity for select to authenticated
  using (user_id = auth.uid() or is_admin(auth.uid()));
drop policy if exists seller_identity_service_all on seller_identity;
create policy seller_identity_service_all on seller_identity for all to service_role using (true);

-- Je účet ověřený pro daný rok? (default = letošní). Používá RLS i UI.
create or replace function is_identity_verified(p_user uuid, p_year int default null)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from seller_identity
    where user_id = p_user
      and verified_year = coalesce(p_year, extract(year from now())::int)
  );
$$;
grant execute on function is_identity_verified(uuid, int) to authenticated, anon;
