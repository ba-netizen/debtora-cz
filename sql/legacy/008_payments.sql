-- ═══════════════════════════════════════════════════════
-- 008 — Platby (Comgate) a kreditní systém
-- Jednorázová platba: bez účtu, povinný e-mail (faktura+report)
-- Balíček kreditů: vyžaduje účet
-- ═══════════════════════════════════════════════════════

create table if not exists payments (
  id uuid primary key default gen_random_uuid(),
  token text not null unique,                -- tajný token pro anonymní dotaz na stav
  user_id uuid references auth.users on delete set null,
  email text not null,                       -- vždy povinný (faktura, doručení reportu)
  product text not null check (product in ('single','pack5','pack20')),
  amount_haleru int not null,                -- částka v haléřích (formát Comgate)
  currency text not null default 'CZK',
  comgate_trans_id text,
  status text not null default 'pending'
    check (status in ('pending','paid','cancelled','error')),
  subject jsonb,                             -- u 'single': koho lustrovat po zaplacení
  request_id uuid references verification_requests,  -- výsledná CEE lustrace
  credits_granted int not null default 0,
  invoice_no text,                           -- doplní fakturace (Fakturoid – fáze 2)
  paid_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists credit_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  change int not null,                       -- + nákup / − čerpání
  reason text not null,                      -- purchase | spend_cee | refund_failed_cee | admin
  payment_id uuid references payments,
  created_at timestamptz not null default now()
);

create index if not exists idx_payments_token on payments (token);
create index if not exists idx_payments_user on payments (user_id, created_at desc);
create index if not exists idx_payments_transid on payments (comgate_trans_id);
create index if not exists idx_credit_tx_user on credit_transactions (user_id, created_at desc);

-- ── RLS ──
alter table payments enable row level security;
alter table credit_transactions enable row level security;

create policy "payments_select_own" on payments for select
  using (auth.uid() = user_id);
create policy "credit_tx_select_own" on credit_transactions for select
  using (auth.uid() = user_id);
-- Zápisy výhradně Edge Functions přes service role.

-- ── Kreditní funkce (volá jen service role) ──
create or replace function add_credits(p_user uuid, p_amount int, p_reason text, p_payment uuid default null)
returns void language plpgsql security definer as $$
begin
  insert into credit_transactions (user_id, change, reason, payment_id)
  values (p_user, p_amount, p_reason, p_payment);
  insert into user_credits (user_id, balance, updated_at)
  values (p_user, p_amount, now())
  on conflict (user_id)
  do update set balance = user_credits.balance + p_amount, updated_at = now();
end $$;

create or replace function spend_credit(p_user uuid)
returns boolean language plpgsql security definer as $$
declare ok boolean := false;
begin
  update user_credits
  set balance = balance - 1, updated_at = now()
  where user_id = p_user and balance > 0
  returning true into ok;
  if ok then
    insert into credit_transactions (user_id, change, reason)
    values (p_user, -1, 'spend_cee');
  end if;
  return coalesce(ok, false);
end $$;

revoke execute on function add_credits(uuid,int,text,uuid) from public, anon, authenticated;
revoke execute on function spend_credit(uuid) from public, anon, authenticated;
