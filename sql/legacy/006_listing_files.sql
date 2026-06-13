-- ============================================================
-- DEBTORA CZ — File Uploads for Listings
-- Spusť v Supabase SQL Editoru
-- ============================================================

-- 1. Tabulka pro soubory k inzerátům
CREATE TABLE IF NOT EXISTS listing_files (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  listing_id UUID REFERENCES listings(id) ON DELETE CASCADE,
  file_name TEXT NOT NULL,
  file_url TEXT NOT NULL,
  file_type TEXT DEFAULT 'image',  -- image, document, other
  file_size INTEGER DEFAULT 0,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_listing_files_listing ON listing_files(listing_id);

-- 2. RLS
ALTER TABLE listing_files ENABLE ROW LEVEL SECURITY;

CREATE POLICY "listing_files_public_read" ON listing_files FOR SELECT TO anon USING (true);
CREATE POLICY "listing_files_anon_insert" ON listing_files FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "listing_files_anon_delete" ON listing_files FOR DELETE TO anon USING (true);
CREATE POLICY "listing_files_service_all" ON listing_files FOR ALL TO service_role USING (true);

-- ============================================================
-- DŮLEŽITÉ: Po spuštění tohoto SQL musíš ještě ručně vytvořit
-- Storage Bucket v Supabase dashboardu:
--
-- 1. Vlevo klikni na "Storage" (ikona kbelíku)
-- 2. Klikni "New bucket"
-- 3. Name: listing-files
-- 4. Public bucket: ZAŠKRTNI (zapni)
-- 5. File size limit: 10 MB
-- 6. Allowed MIME types: image/jpeg, image/png, image/webp, application/pdf
-- 7. Klikni "Create bucket"
--
-- Pak nastav polícy pro bucket:
-- 1. Klikni na bucket "listing-files"
-- 2. Záložka "Policies"
-- 3. Klikni "New policy" → "For full customization"
-- 4. Policy name: "Allow public uploads"
-- 5. Allowed operations: SELECT, INSERT
-- 6. Target roles: anon
-- 7. USING expression: true
-- 8. WITH CHECK expression: true
-- 9. Klikni "Review" → "Save policy"
-- ============================================================
