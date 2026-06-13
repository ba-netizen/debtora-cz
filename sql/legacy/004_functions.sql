-- ============================================================
-- DEBTORA CZ — SQL Functions (RPC)
-- Run AFTER 001_schema.sql
-- ============================================================

-- ── Increment listing view count ──
CREATE OR REPLACE FUNCTION increment_views(listing_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE listings SET views = views + 1 WHERE id = listing_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Admin login verification ──
-- Returns a simple success indicator if password hash matches
-- NOTE: In production, use Supabase Auth + custom claims for admin access.
-- This is a simplified approach for the initial migration.
CREATE OR REPLACE FUNCTION admin_login(pw_hash TEXT)
RETURNS JSON AS $$
DECLARE
  admin_record RECORD;
BEGIN
  SELECT * INTO admin_record FROM admin_users
  WHERE password_hash = pw_hash
  LIMIT 1;
  
  IF admin_record IS NULL THEN
    RETURN NULL;
  END IF;
  
  -- Update last login
  UPDATE admin_users SET last_login = NOW() WHERE id = admin_record.id;
  
  RETURN json_build_object(
    'success', true,
    'username', admin_record.username,
    'role', admin_record.role
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Get dashboard stats ──
CREATE OR REPLACE FUNCTION get_admin_stats()
RETURNS JSON AS $$
BEGIN
  RETURN json_build_object(
    'total_listings', (SELECT COUNT(*) FROM listings),
    'active_listings', (SELECT COUNT(*) FROM listings WHERE status = 'active'),
    'pending_listings', (SELECT COUNT(*) FROM listings WHERE status = 'pending'),
    'total_users', (SELECT COUNT(*) FROM users),
    'verified_users', (SELECT COUNT(*) FROM users WHERE kyc_status = 'verified'),
    'total_messages', (SELECT COUNT(*) FROM messages),
    'unread_messages', (SELECT COUNT(*) FROM messages WHERE is_read = FALSE),
    'total_value', (SELECT COALESCE(SUM(price), 0) FROM listings WHERE status = 'active')
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION increment_views TO anon;
GRANT EXECUTE ON FUNCTION admin_login TO anon;
GRANT EXECUTE ON FUNCTION get_admin_stats TO authenticated;
