-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 007: Předplatné služeb (zatím 'inzerce')
--
-- Aktivní = status='active' AND current_period_end > now().
-- has_active_subscription používá RLS (008, 012) i frontend (gating UI).
-- Run AFTER 006.
-- ═══════════════════════════════════════════════════════

create table if not exists subscriptions (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null references auth.users on delete cascade,
  service              text not null check (service in ('inzerce')),
  status               text not null default 'active'
                         check (status in ('active','past_due','cancelled','expired')),
  current_period_start timestamptz not null default now(),
  current_period_end   timestamptz not null,
  auto_renew           boolean not null default true,
  payment_id           uuid references payments on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  unique (user_id, service)                  -- 1 předplatné na službu a uživatele
);
create index if not exists idx_subscriptions_user on subscriptions (user_id);
create index if not exists idx_subscriptions_active
  on subscriptions (service, current_period_end) where status = 'active';

drop trigger if exists trg_subscriptions_updated on subscriptions;
create trigger trg_subscriptions_updated before update on subscriptions
  for each row execute function set_updated_at();

-- ── Má uživatel aktivní předplatné dané služby? ──
create or replace function has_active_subscription(p_user uuid, p_service text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from subscriptions s
    where s.user_id = p_user and s.service = p_service
      and s.status = 'active' and s.current_period_end > now()
  );
$$;
grant execute on function has_active_subscription(uuid, text) to authenticated, anon;

-- ── Aktivace / prodloužení (volá jen service role z payment-callback) ──
-- Prodlužuje od konce běžícího období, jinak od teď.
create or replace function activate_subscription(
  p_user uuid, p_service text, p_months int, p_payment uuid default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into subscriptions (user_id, service, status, current_period_start,
                             current_period_end, payment_id)
  values (p_user, p_service, 'active', now(),
          now() + make_interval(months => p_months), p_payment)
  on conflict (user_id, service) do update set
    status             = 'active',
    current_period_end = greatest(subscriptions.current_period_end, now())
                           + make_interval(months => p_months),
    payment_id         = excluded.payment_id,
    updated_at         = now();
end $$;
revoke execute on function activate_subscription(uuid, text, int, uuid)
  from public, anon, authenticated;

-- ── RLS ──
alter table subscriptions enable row level security;
drop policy if exists subscriptions_select_own on subscriptions;
create policy subscriptions_select_own on subscriptions for select to authenticated
  using (user_id = auth.uid() or is_admin(auth.uid()));
drop policy if exists subscriptions_service_all on subscriptions;
create policy subscriptions_service_all on subscriptions for all to service_role using (true);
