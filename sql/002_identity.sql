-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 002: Identita (na Supabase auth.users)
--
-- D1: Profil `users` je 1:1 s auth.users (PK = auth.users.id).
--     Zakládá ho trigger po vzniku auth uživatele.
-- D3: Admin je příznakovaný auth.users účet (admin_users.user_id).
--     Autorizace přes is_admin(auth.uid()) — NIKDY service-role klíč ve frontendu.
--
-- Run AFTER 001.
-- ═══════════════════════════════════════════════════════

-- ── 1. Profil uživatele (1:1 s auth.users) ──
create table if not exists users (
  id           uuid primary key references auth.users on delete cascade,
  email        text,
  name         text,
  company      text,
  ico          text,                         -- IČO (CZ)
  phone        text,
  account_type text not null default 'buyer'
                 check (account_type in ('buyer','seller','both','broker')),
  kyc_status   text not null default 'unverified'
                 check (kyc_status in ('unverified','pending','verified','rejected')),
  kyc_notes    text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

drop trigger if exists trg_users_updated on users;
create trigger trg_users_updated before update on users
  for each row execute function set_updated_at();

-- Profil vzniká automaticky při registraci přes Supabase Auth.
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.users (id, email, name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'name', null))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ── 2. Admin (oddělený přístup do admin panelu) ──
create table if not exists admin_users (
  user_id    uuid primary key references auth.users on delete cascade,
  role       text not null default 'admin' check (role in ('admin','editor')),
  created_at timestamptz not null default now()
);

-- Centrální kontrola adminských práv. Používají ji admin RPC i RLS policy.
create or replace function is_admin(p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from admin_users where user_id = p_user);
$$;
grant execute on function is_admin(uuid) to authenticated, anon;

-- ── 3. RLS ──
alter table users enable row level security;
alter table admin_users enable row level security;

-- Uživatel čte a edituje jen svůj profil; admin čte/edituje vše.
drop policy if exists users_select_own on users;
create policy users_select_own on users for select to authenticated
  using (id = auth.uid() or is_admin(auth.uid()));

drop policy if exists users_update_own on users;
create policy users_update_own on users for update to authenticated
  using (id = auth.uid() or is_admin(auth.uid()))
  with check (id = auth.uid() or is_admin(auth.uid()));

drop policy if exists users_service_all on users;
create policy users_service_all on users for all to service_role using (true);

-- admin_users smí číst jen admin / service role; zápis jen service role.
drop policy if exists admin_users_select on admin_users;
create policy admin_users_select on admin_users for select to authenticated
  using (is_admin(auth.uid()));

drop policy if exists admin_users_service_all on admin_users;
create policy admin_users_service_all on admin_users for all to service_role using (true);
