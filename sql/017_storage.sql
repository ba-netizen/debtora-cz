-- ═══════════════════════════════════════════════════════
-- DEBTORA CZ — 017: Storage buckety + RLS
--   D2: listing-files = PRIVÁTNÍ (čtení přes signed URL; upload jen vlastník
--       listingu). storefront-logos = VEŘEJNÝ read; upload jen vlastník storefrontu.
--   Konvence cest:
--     listing-files:     <listing_id>/<filename>
--     storefront-logos:  <storefront_id>/<filename>
--   Spouštět v Supabase (schema storage musí existovat). Idempotentní.
-- ═══════════════════════════════════════════════════════

-- file_url v listing_files drž jako PATH v bucketu (ne public URL) — viz D2.
comment on column listing_files.file_url is
  'Path objektu v bucketu listing-files (<listing_id>/<filename>); veřejně se servíruje přes signed URL.';

-- Bezpečný cast textu na uuid (folder v cestě nemusí být uuid).
create or replace function try_uuid(t text)
returns uuid language plpgsql immutable as $$
begin
  return t::uuid;
exception when others then
  return null;
end $$;

-- ── Buckety (limit 10 MB / 2 MB; povolené MIME) ──
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('listing-files', 'listing-files', false, 10485760,
     array['image/jpeg','image/png','image/webp','application/pdf']),
  ('storefront-logos', 'storefront-logos', true, 2097152,
     array['image/jpeg','image/png','image/webp','image/svg+xml'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- ═══════════════════════════════════════════════════════
-- RLS na storage.objects
-- ═══════════════════════════════════════════════════════

-- ── listing-files (PRIVÁTNÍ) ──
-- Čtení: vlastník listingu nebo admin (anonym čte jen přes signed URL,
-- které generuje autorizovaný klient/edge — RLS na to neplatí).
drop policy if exists "listing_files_read" on storage.objects;
create policy "listing_files_read" on storage.objects for select to authenticated
  using (
    bucket_id = 'listing-files' and (
      is_admin(auth.uid())
      or exists (select 1 from listings l
                 where l.id = try_uuid((storage.foldername(name))[1])
                   and l.owner_id = auth.uid())
    )
  );

-- Upload/úprava/mazání: jen vlastník daného listingu (nebo admin).
drop policy if exists "listing_files_write" on storage.objects;
create policy "listing_files_write" on storage.objects for all to authenticated
  using (
    bucket_id = 'listing-files' and (
      is_admin(auth.uid())
      or exists (select 1 from listings l
                 where l.id = try_uuid((storage.foldername(name))[1])
                   and l.owner_id = auth.uid())
    )
  )
  with check (
    bucket_id = 'listing-files' and (
      is_admin(auth.uid())
      or exists (select 1 from listings l
                 where l.id = try_uuid((storage.foldername(name))[1])
                   and l.owner_id = auth.uid())
    )
  );

-- ── storefront-logos (VEŘEJNÝ read) ──
-- Veřejné čtení zajišťuje public bucket (/object/public/...). Upload jen vlastník.
drop policy if exists "storefront_logos_write" on storage.objects;
create policy "storefront_logos_write" on storage.objects for all to authenticated
  using (
    bucket_id = 'storefront-logos' and (
      is_admin(auth.uid())
      or exists (select 1 from storefronts s
                 where s.id = try_uuid((storage.foldername(name))[1])
                   and s.owner_id = auth.uid())
    )
  )
  with check (
    bucket_id = 'storefront-logos' and (
      is_admin(auth.uid())
      or exists (select 1 from storefronts s
                 where s.id = try_uuid((storage.foldername(name))[1])
                   and s.owner_id = auth.uid())
    )
  );
