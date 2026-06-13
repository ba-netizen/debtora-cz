-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 001: Rozšíření + sdílené helpery
-- Idempotentní. Spouštět jako první.
-- ═══════════════════════════════════════════════════════

create extension if not exists "pgcrypto";   -- gen_random_uuid()

-- Sdílený trigger pro automatické updated_at.
create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;
