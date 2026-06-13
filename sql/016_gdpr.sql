-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 016: GDPR (mazání účtu vs. účetní audit) + pg_cron
--   D3: delete_account() anonymizuje osobní údaje, ZACHOVÁ payments a
--       credit_transactions (zákonná retence) odvázané od identity.
--       Skutečné smazání auth.users dělá edge funkce `delete-account`.
--   D3/C2: aktivace denního pg_cron (cleanup výsledků + sync storefrontů).
-- Idempotentní.
-- ═══════════════════════════════════════════════════════

-- Aby účetní záznamy přežily smazání auth.users, odvážeme je (SET NULL)
-- místo dosavadního CASCADE.
alter table credit_transactions alter column user_id drop not null;
alter table credit_transactions drop constraint if exists credit_transactions_user_id_fkey;
alter table credit_transactions add constraint credit_transactions_user_id_fkey
  foreign key (user_id) references auth.users on delete set null;

-- payments.user_id už je ON DELETE SET NULL (005) → platby zůstanou.
-- seller_identity / user_credits / subscriptions / storefronts: CASCADE (nejsou účetní).

-- ── delete_account: anonymizace v rámci aplikační DB ──
-- Volá přihlášený uživatel na svůj účet; edge funkce poté smaže auth.users.
create or replace function delete_account()
returns json language plpgsql security definer set search_path = public as $$
declare
  v_user  uuid := auth.uid();
  v_email text;
begin
  if v_user is null then
    return json_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  select email into v_email from users where id = v_user;

  -- anonymizace profilu (retence účetnictví se řeší odvázáním, ne mazáním)
  update users set
    name = null, company = null, ico = null, phone = null,
    email = 'deleted+' || v_user || '@debtora.invalid',
    kyc_status = 'unverified', kyc_notes = null, updated_at = now()
  where id = v_user;

  -- anonymizace zpráv odeslaných pod e-mailem uživatele
  if v_email is not null then
    update messages set name = '—', email = 'deleted@debtora.invalid',
                        phone = null, company = null
    where email = v_email;
  end if;

  -- odvázat účetní doklady od identity (zůstávají kvůli retenci)
  update payments set user_id = null where user_id = v_user;
  update credit_transactions set user_id = null where user_id = v_user;

  return json_build_object('ok', true);
end $$;
grant execute on function delete_account() to authenticated;

-- ── pg_cron: denní úklid + sync storefrontů (bezpečně, jen je-li rozšíření) ──
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'cleanup-verifications') then
      perform cron.unschedule('cleanup-verifications');
    end if;
    perform cron.schedule('cleanup-verifications', '15 3 * * *',
                          'select cleanup_expired_verifications()');

    if exists (select 1 from cron.job where jobname = 'sync-storefronts') then
      perform cron.unschedule('sync-storefronts');
    end if;
    perform cron.schedule('sync-storefronts', '30 3 * * *',
                          'select sync_storefront_status()');
  end if;
end $$;
