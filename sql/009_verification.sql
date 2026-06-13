-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 009: Ověření protistrany (lustrace)
--
-- verification_requests = audit dotazů; verification_results = výsledky
-- per rejstřík s TTL 30 dní (expires_at). Zápis jen service role (edge `verify`).
-- Run AFTER 008.
-- ═══════════════════════════════════════════════════════

create table if not exists verification_requests (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid references auth.users on delete set null,
  subject_type      text not null check (subject_type in ('fo','po')),
  subject_name      text,
  subject_birthdate date,
  subject_ico       text,
  level             text not null default 'basic'
                      check (level in ('foc_nologin','foc_login','basic','medium','full')),
  risk_score        int,                      -- 0–100 agregované skóre (počítá `verify`)
  created_at        timestamptz not null default now()
);

create table if not exists verification_results (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references verification_requests on delete cascade,
  registry    text not null,                  -- isir|ares|dph|cee|katastr|vozidla|atp|bankid
  status      text not null
                check (status in ('clear','found','locked','error','unavailable','skipped')),
  payload     jsonb,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null            -- TTL 30 dní
);

create index if not exists idx_vr_user on verification_requests (user_id, created_at desc);
create index if not exists idx_vres_request on verification_results (request_id);
create index if not exists idx_vres_expires on verification_results (expires_at);

-- Doplnit FK payments.request_id → verification_requests (sloupec vznikl v 005).
alter table payments drop constraint if exists payments_request_fk;
alter table payments add constraint payments_request_fk
  foreign key (request_id) references verification_requests on delete set null;

-- ── RLS: uživatel vidí jen svou (neexpirovanou) historii; zápis service role ──
alter table verification_requests enable row level security;
alter table verification_results enable row level security;

drop policy if exists vr_select_own on verification_requests;
create policy vr_select_own on verification_requests for select to authenticated
  using (user_id = auth.uid() or is_admin(auth.uid()));
drop policy if exists vr_service_all on verification_requests;
create policy vr_service_all on verification_requests for all to service_role using (true);

drop policy if exists vres_select_own on verification_results;
create policy vres_select_own on verification_results for select to authenticated
  using (expires_at > now() and exists (
    select 1 from verification_requests r
    where r.id = request_id and (r.user_id = auth.uid() or is_admin(auth.uid()))
  ));
drop policy if exists vres_service_all on verification_results;
create policy vres_service_all on verification_results for all to service_role using (true);

-- ── Úklid expirovaných výsledků (pg_cron, denně) ──
create or replace function cleanup_expired_verifications()
returns void language sql security definer set search_path = public as $$
  delete from verification_results where expires_at < now();
  delete from verification_requests r
  where created_at < now() - interval '30 days'
    and not exists (select 1 from verification_results v where v.request_id = r.id);
$$;
-- select cron.schedule('cleanup-verifications', '15 3 * * *', 'select cleanup_expired_verifications()');
