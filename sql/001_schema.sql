-- ============================================================
-- DEBTORA CZ — Supabase Database Schema
-- Replaces: Netlify Blobs (content, settings, listings, users, messages, sessions)
-- ============================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ── 1. CONTENT (CMS editable blocks) ──
-- Replaces: Netlify Blobs "content" store
-- Each row = one page's editable content fields (JSON)
CREATE TABLE content (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  block_key TEXT UNIQUE NOT NULL,          -- e.g. 'homepage', 'about', 'pricing'
  fields JSONB NOT NULL DEFAULT '{}',      -- e.g. {"hero_headline": "...", "hero_desc": "..."}
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── 2. SETTINGS (site-wide configuration) ──
-- Replaces: Netlify Blobs "settings" store
CREATE TABLE settings (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  key TEXT UNIQUE NOT NULL,                -- e.g. 'company', 'contact', 'social'
  value JSONB NOT NULL DEFAULT '{}',
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── 3. USERS (registered platform users) ──
-- Replaces: Netlify Blobs "users" store
CREATE TABLE users (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  name TEXT,
  company TEXT,
  ico TEXT,                                -- Czech company ID
  phone TEXT,
  account_type TEXT DEFAULT 'buyer' CHECK (account_type IN ('buyer', 'seller', 'both', 'broker')),
  kyc_status TEXT DEFAULT 'unverified' CHECK (kyc_status IN ('unverified', 'pending', 'verified', 'rejected')),
  kyc_notes TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── 4. LISTINGS (marketplace items) ──
-- Replaces: Netlify Blobs "listings" store
CREATE TABLE listings (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  title TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('debt', 'property', 'otc')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('active', 'pending', 'sold', 'hidden', 'expired')),
  description TEXT,
  price NUMERIC(15,2),
  original_value NUMERIC(15,2),
  discount_pct NUMERIC(5,2),
  location TEXT,
  category TEXT,
  details JSONB DEFAULT '{}',
  contact_email TEXT,
  contact_phone TEXT,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  featured BOOLEAN DEFAULT FALSE,
  views INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── 5. MESSAGES (contact form submissions) ──
-- Replaces: Netlify Blobs "messages" store
CREATE TABLE messages (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT,
  company TEXT,
  type TEXT DEFAULT 'general',             -- general, buy, sell, partnership
  message TEXT NOT NULL,
  is_read BOOLEAN DEFAULT FALSE,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── 6. ADMIN USERS (admin panel access) ──
-- Replaces: env var ADMIN_PASSWORD + Netlify Blobs "sessions"
CREATE TABLE admin_users (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  role TEXT DEFAULT 'admin' CHECK (role IN ('admin', 'editor')),
  last_login TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── INDEXES ──
CREATE INDEX idx_listings_type ON listings(type);
CREATE INDEX idx_listings_status ON listings(status);
CREATE INDEX idx_listings_created ON listings(created_at DESC);
CREATE INDEX idx_listings_featured ON listings(featured) WHERE featured = TRUE;
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_kyc ON users(kyc_status);
CREATE INDEX idx_messages_read ON messages(is_read);
CREATE INDEX idx_messages_created ON messages(created_at DESC);
CREATE INDEX idx_content_block ON content(block_key);

-- ── AUTO-UPDATE timestamps ──
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_content_updated BEFORE UPDATE ON content
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_settings_updated BEFORE UPDATE ON settings
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_listings_updated BEFORE UPDATE ON listings
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_users_updated BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── VIEWS for admin dashboard ──
CREATE VIEW admin_stats AS
SELECT
  (SELECT COUNT(*) FROM listings) AS total_listings,
  (SELECT COUNT(*) FROM listings WHERE status = 'active') AS active_listings,
  (SELECT COUNT(*) FROM listings WHERE status = 'pending') AS pending_listings,
  (SELECT COUNT(*) FROM users) AS total_users,
  (SELECT COUNT(*) FROM users WHERE kyc_status = 'verified') AS verified_users,
  (SELECT COUNT(*) FROM messages) AS total_messages,
  (SELECT COUNT(*) FROM messages WHERE is_read = FALSE) AS unread_messages;
