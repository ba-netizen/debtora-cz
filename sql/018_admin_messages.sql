-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 018: Admin správa zpráv (mark read / delete)
-- 015 dal adminovi jen SELECT na messages; admin panel potřebuje i
-- UPDATE (is_read) a DELETE. Autorizace přes is_admin(auth.uid()).
-- Idempotentní.
-- ═══════════════════════════════════════════════════════

drop policy if exists messages_admin_update on messages;
create policy messages_admin_update on messages for update to authenticated
  using (is_admin(auth.uid())) with check (is_admin(auth.uid()));

drop policy if exists messages_admin_delete on messages;
create policy messages_admin_delete on messages for delete to authenticated
  using (is_admin(auth.uid()));
