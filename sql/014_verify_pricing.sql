-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 014: Idempotence ověření + FOC rate limiting
--   A1: request_id (klientský idempotenční klíč) na verification_requests.
--   D4: počítadlo bezplatných (FOC) kontrol per IP/den + per subjekt/den.
-- Navazuje na 009 (verification) a 003 (settings). Idempotentní.
-- ═══════════════════════════════════════════════════════

-- ── A1: idempotenční klíč ──
alter table verification_requests add column if not exists request_id uuid;
create unique index if not exists uq_vr_request_id
  on verification_requests (request_id) where request_id is not null;

-- ── D4: rate-limit počítadlo FOC kontrol ──
create table if not exists foc_rate_limit (
  ip           inet not null,
  day          date not null,
  subject_hash text not null default '',     -- '' = řádek pro celkový denní součet IP
  count        int  not null default 0,
  updated_at   timestamptz not null default now(),
  primary key (ip, day, subject_hash)
);
create index if not exists idx_foc_rate_ip_day on foc_rate_limit (ip, day);

alter table foc_rate_limit enable row level security;
-- Čte/píše jen service role (edge `verify`); běžní uživatelé nemají přístup.
drop policy if exists foc_rate_service_all on foc_rate_limit;
create policy foc_rate_service_all on foc_rate_limit for all to service_role using (true);

-- Konfigurovatelné limity v adminu (settings). Default 5/IP/den, 2/subjekt/den.
insert into settings (key, value) values
  ('foc_limits', '{"per_ip_day":5,"per_subject_day":2}')
on conflict (key) do nothing;

-- ── Atomická kontrola + inkrement FOC limitu ──
-- Vrací true = povoleno (a započítá), false = překročen limit.
create or replace function foc_check_and_count(p_ip inet, p_subject_hash text)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_cfg          jsonb;
  v_ip_limit     int;
  v_subj_limit   int;
  v_ip_count     int;
  v_subj_count   int;
  v_today        date := current_date;
begin
  if p_ip is null then return true; end if;   -- bez IP nelze limitovat → propustit

  select value into v_cfg from settings where key = 'foc_limits';
  v_ip_limit   := coalesce((v_cfg->>'per_ip_day')::int, 5);
  v_subj_limit := coalesce((v_cfg->>'per_subject_day')::int, 2);

  -- aktuální denní součet pro IP (přes všechny subjekty, řádek subject_hash='')
  select coalesce(sum(count), 0) into v_ip_count
    from foc_rate_limit where ip = p_ip and day = v_today and subject_hash <> '';
  -- aktuální počet pro konkrétní subjekt
  select coalesce(count, 0) into v_subj_count
    from foc_rate_limit where ip = p_ip and day = v_today and subject_hash = p_subject_hash;

  if v_ip_count >= v_ip_limit then return false; end if;
  if v_subj_count >= v_subj_limit then return false; end if;

  insert into foc_rate_limit (ip, day, subject_hash, count)
  values (p_ip, v_today, p_subject_hash, 1)
  on conflict (ip, day, subject_hash)
    do update set count = foc_rate_limit.count + 1, updated_at = now();

  return true;
end $$;
revoke execute on function foc_check_and_count(inet, text) from public, anon, authenticated;
