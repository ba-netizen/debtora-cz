-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 005: Platby (Comgate)
--
-- Jedna objednávka = jeden řádek. `comgate_trans_id` + idempotence
-- v callbacku zajišťují, že duplicitní notifikace nepřipíše 2× (D8).
-- Vazba na user_id (přihlášený) NEBO jen e-mail (platba bez účtu).
-- Run AFTER 004.
-- ═══════════════════════════════════════════════════════

create table if not exists payments (
  id               uuid primary key default gen_random_uuid(),
  token            text not null unique,         -- tajný token pro anonymní polling stavu
  user_id          uuid references auth.users on delete set null,
  email            text not null,                -- vždy (faktura + doručení reportu)
  product          text not null check (product in
                     ('single','pack5','pack20','pack50','sub_inzerce_monthly')),
  amount_haleru    int not null,                 -- částka v haléřích (formát Comgate)
  currency         text not null default 'CZK',
  comgate_trans_id text,
  status           text not null default 'pending'
                     check (status in ('pending','paid','cancelled','failed')),
  subject          jsonb,                         -- u 'single': koho lustrovat po zaplacení
  request_id       uuid,                          -- FK na verification_requests doplní 009
  credits_granted  int not null default 0,
  invoice_no       text,                          -- doplní fakturace (fáze 2)
  paid_at          timestamptz,
  created_at       timestamptz not null default now()
);

create index if not exists idx_payments_token on payments (token);
create index if not exists idx_payments_user on payments (user_id, created_at desc);
create unique index if not exists uq_payments_transid on payments (comgate_trans_id)
  where comgate_trans_id is not null;

-- ── RLS: vlastník čte svoje; zápis výhradně service role (edge funkce) ──
alter table payments enable row level security;

drop policy if exists payments_select_own on payments;
create policy payments_select_own on payments for select to authenticated
  using (user_id = auth.uid() or is_admin(auth.uid()));

drop policy if exists payments_service_all on payments;
create policy payments_service_all on payments for all to service_role using (true);
