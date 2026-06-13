-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 006: Kreditní systém
--
-- user_credits = aktuální zůstatek; credit_transactions = auditní ledger
-- (1 pohyb = 1 řádek). Zápis jen přes SECURITY DEFINER funkce / service role.
-- reason (D9): purchase | spend | refund | identity_first_listing | admin
-- Run AFTER 005.
-- ═══════════════════════════════════════════════════════

create table if not exists user_credits (
  user_id    uuid primary key references auth.users on delete cascade,
  balance    int not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists credit_transactions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users on delete cascade,
  change      int not null,                  -- + nákup/refund, − čerpání
  reason      text not null,                 -- viz D9
  payment_id  uuid references payments on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists idx_credit_tx_user on credit_transactions (user_id, created_at desc);
-- Idempotenční opěra (D8): nejvýše 1 'purchase' na danou platbu.
create unique index if not exists uq_credit_purchase_payment
  on credit_transactions (payment_id) where reason = 'purchase' and payment_id is not null;

alter table user_credits enable row level security;
alter table credit_transactions enable row level security;

drop policy if exists user_credits_select_own on user_credits;
create policy user_credits_select_own on user_credits for select to authenticated
  using (user_id = auth.uid() or is_admin(auth.uid()));
drop policy if exists user_credits_service_all on user_credits;
create policy user_credits_service_all on user_credits for all to service_role using (true);

drop policy if exists credit_tx_select_own on credit_transactions;
create policy credit_tx_select_own on credit_transactions for select to authenticated
  using (user_id = auth.uid() or is_admin(auth.uid()));
drop policy if exists credit_tx_service_all on credit_transactions;
create policy credit_tx_service_all on credit_transactions for all to service_role using (true);

-- ═══════════════════════════════════════════════════════
-- add_credits — IDEMPOTENTNÍ připsání podle payment_ref (D8).
-- Pokud už pro danou platbu existuje 'purchase' řádek, nic nedělá.
-- ═══════════════════════════════════════════════════════
create or replace function add_credits(
  p_user uuid, p_amount int, p_reason text default 'purchase', p_payment uuid default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  if p_amount <= 0 then return; end if;

  -- Idempotence: nákup vázaný na platbu připíšeme jen jednou.
  if p_reason = 'purchase' and p_payment is not null
     and exists (select 1 from credit_transactions
                 where payment_id = p_payment and reason = 'purchase') then
    return;
  end if;

  insert into credit_transactions (user_id, change, reason, payment_id)
  values (p_user, p_amount, p_reason, p_payment);

  insert into user_credits (user_id, balance, updated_at)
  values (p_user, p_amount, now())
  on conflict (user_id) do update
    set balance = user_credits.balance + p_amount, updated_at = now();
end $$;

-- ═══════════════════════════════════════════════════════
-- spend_credits — atomický odečet (jen pokud je dost), zápis do ledgeru.
-- Vrací true při úspěchu. p_amount<=0 → no-op true.
-- ═══════════════════════════════════════════════════════
create or replace function spend_credits(
  p_user uuid, p_amount int default 1, p_reason text default 'spend'
) returns boolean language plpgsql security definer set search_path = public as $$
declare ok boolean := false;
begin
  if p_amount <= 0 then return true; end if;
  update user_credits
    set balance = balance - p_amount, updated_at = now()
    where user_id = p_user and balance >= p_amount
    returning true into ok;
  if coalesce(ok, false) then
    insert into credit_transactions (user_id, change, reason)
    values (p_user, -p_amount, p_reason);
  end if;
  return coalesce(ok, false);
end $$;

-- ═══════════════════════════════════════════════════════
-- refund_credits — vrácení kreditů (např. selhání placené kontroly).
-- ═══════════════════════════════════════════════════════
create or replace function refund_credits(
  p_user uuid, p_amount int default 1, p_reason text default 'refund', p_payment uuid default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  if p_amount <= 0 then return; end if;
  insert into credit_transactions (user_id, change, reason, payment_id)
  values (p_user, p_amount, p_reason, p_payment);
  insert into user_credits (user_id, balance, updated_at)
  values (p_user, p_amount, now())
  on conflict (user_id) do update
    set balance = user_credits.balance + p_amount, updated_at = now();
end $$;

-- Citlivé zápisové funkce smí volat jen service role.
revoke execute on function add_credits(uuid,int,text,uuid) from public, anon, authenticated;
revoke execute on function spend_credits(uuid,int,text) from public, anon, authenticated;
revoke execute on function refund_credits(uuid,int,text,uuid) from public, anon, authenticated;
