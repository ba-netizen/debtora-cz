-- ============================================================
-- DEBTORA CZ — Row Level Security (RLS) Policies
-- Run AFTER 001_schema.sql
-- ============================================================

-- Enable RLS on all tables
ALTER TABLE content ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE listings ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;

-- ── PUBLIC READ policies (anon role) ──
-- Content and settings are publicly readable (CMS needs this)
CREATE POLICY "Content is publicly readable"
  ON content FOR SELECT TO anon USING (true);

CREATE POLICY "Settings are publicly readable"
  ON settings FOR SELECT TO anon USING (true);

-- Only active listings are publicly visible
CREATE POLICY "Active listings are publicly readable"
  ON listings FOR SELECT TO anon
  USING (status = 'active');

-- ── AUTHENTICATED user policies ──
-- Logged-in users can see all their own data
CREATE POLICY "Users can read own profile"
  ON users FOR SELECT TO authenticated
  USING (id = auth.uid());

CREATE POLICY "Users can update own profile"
  ON users FOR UPDATE TO authenticated
  USING (id = auth.uid());

-- Authenticated users can create listings
CREATE POLICY "Authenticated users can create listings"
  ON listings FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Users can edit their own listings
CREATE POLICY "Users can update own listings"
  ON listings FOR UPDATE TO authenticated
  USING (user_id = auth.uid());

-- Authenticated users can read all active listings
CREATE POLICY "Authenticated users read active listings"
  ON listings FOR SELECT TO authenticated
  USING (status = 'active' OR user_id = auth.uid());

-- Anyone can submit messages (contact form)
CREATE POLICY "Anyone can submit messages"
  ON messages FOR INSERT TO anon
  WITH CHECK (true);

-- ── SERVICE ROLE (admin) — full access ──
-- The service_role key bypasses RLS by default in Supabase.
-- Admin operations use the service_role key, so no extra policies needed.
-- But we add explicit policies for the authenticated admin pattern:

CREATE POLICY "Service role full access to content"
  ON content FOR ALL TO service_role USING (true);

CREATE POLICY "Service role full access to settings"
  ON settings FOR ALL TO service_role USING (true);

CREATE POLICY "Service role full access to listings"
  ON listings FOR ALL TO service_role USING (true);

CREATE POLICY "Service role full access to users"
  ON users FOR ALL TO service_role USING (true);

CREATE POLICY "Service role full access to messages"
  ON messages FOR ALL TO service_role USING (true);

CREATE POLICY "Service role full access to admin_users"
  ON admin_users FOR ALL TO service_role USING (true);
