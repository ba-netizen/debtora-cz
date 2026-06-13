-- ═══════════════════════════════════════════════════════
-- 007 — Modul "Ověření nájemce"
-- Tabulky pro audit dotazů, výsledky (TTL 30 dní) a kredity
-- ═══════════════════════════════════════════════════════

create table if not exists verification_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete set null,
  subject_type text not null check (subject_type in ('fo','po')),
  subject_name text,
  subject_birthdate date,
  subject_ico text,
  created_at timestamptz not null default now()
);

create table if not exists verification_results (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references verification_requests on delete cascade,
  registry text not null check (registry in ('isir','ares','dph','cee')),
  status text not null check (status in ('clear','found','locked','error','unavailable')),
  payload jsonb,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create table if not exists user_credits (
  user_id uuid primary key references auth.users on delete cascade,
  balance int not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);

create index if not exists idx_verification_requests_user on verification_requests (user_id, created_at desc);
create index if not exists idx_verification_results_request on verification_results (request_id);
create index if not exists idx_verification_results_expires on verification_results (expires_at);

-- ── RLS ──
alter table verification_requests enable row level security;
alter table verification_results enable row level security;
alter table user_credits enable row level security;

-- Zápis provádí výhradně Edge Function přes service role (RLS obchází).
-- Uživatel vidí jen svou historii.
create policy "verification_requests_select_own"
  on verification_requests for select
  using (auth.uid() = user_id);

create policy "verification_results_select_own"
  on verification_results for select
  using (exists (
    select 1 from verification_requests r
    where r.id = request_id and r.user_id = auth.uid()
  ) and expires_at > now());

create policy "user_credits_select_own"
  on user_credits for select
  using (auth.uid() = user_id);

-- ── Úklid expirovaných výsledků (volat denně, např. pg_cron) ──
create or replace function cleanup_expired_verifications() returns void
language sql security definer as $$
  delete from verification_results where expires_at < now();
  delete from verification_requests r
  where created_at < now() - interval '30 days'
    and not exists (select 1 from verification_results v where v.request_id = r.id);
$$;

-- Volitelně (vyžaduje rozšíření pg_cron):
-- select cron.schedule('cleanup-verifications', '15 3 * * *', 'select cleanup_expired_verifications()');
