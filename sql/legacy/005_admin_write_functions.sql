-- ============================================================
-- DEBTORA CZ — Admin Write Functions (SECURITY DEFINER)
-- Run AFTER 004_functions.sql
--
-- Fixes: Admin panel uses anon key, but RLS blocks anon from
-- UPDATE/INSERT/DELETE on content, settings, listings, etc.
-- These functions verify admin credentials internally, then
-- perform writes with elevated (definer) permissions.
-- ============================================================

-- ── Helper: verify admin password hash ──
CREATE OR REPLACE FUNCTION _verify_admin(pw_hash TEXT)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM admin_users WHERE password_hash = pw_hash);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Admin: Update content block ──
CREATE OR REPLACE FUNCTION admin_update_content(
  pw_hash TEXT,
  p_block_key TEXT,
  p_fields JSONB
)
RETURNS JSON AS $$
BEGIN
  IF NOT _verify_admin(pw_hash) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  UPDATE content SET fields = p_fields, updated_at = NOW()
  WHERE block_key = p_block_key;

  IF NOT FOUND THEN
    INSERT INTO content (id, block_key, fields, updated_at)
    VALUES (gen_random_uuid(), p_block_key, p_fields, NOW());
  END IF;

  RETURN json_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Admin: Update settings ──
CREATE OR REPLACE FUNCTION admin_update_settings(
  pw_hash TEXT,
  p_key TEXT,
  p_value JSONB
)
RETURNS JSON AS $$
BEGIN
  IF NOT _verify_admin(pw_hash) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  UPDATE settings SET value = p_value, updated_at = NOW()
  WHERE key = p_key;

  IF NOT FOUND THEN
    INSERT INTO settings (id, key, value, updated_at)
    VALUES (gen_random_uuid(), p_key, p_value, NOW());
  END IF;

  RETURN json_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Admin: Update listing status ──
CREATE OR REPLACE FUNCTION admin_update_listing(
  pw_hash TEXT,
  p_listing_id UUID,
  p_status TEXT
)
RETURNS JSON AS $$
BEGIN
  IF NOT _verify_admin(pw_hash) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  UPDATE listings SET status = p_status, updated_at = NOW()
  WHERE id = p_listing_id;

  RETURN json_build_object('success', FOUND);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Admin: Delete listing ──
CREATE OR REPLACE FUNCTION admin_delete_listing(
  pw_hash TEXT,
  p_listing_id UUID
)
RETURNS JSON AS $$
BEGIN
  IF NOT _verify_admin(pw_hash) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  DELETE FROM listings WHERE id = p_listing_id;

  RETURN json_build_object('success', FOUND);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Admin: Update user (e.g. verify KYC) ──
CREATE OR REPLACE FUNCTION admin_update_user(
  pw_hash TEXT,
  p_user_id UUID,
  p_updates JSONB
)
RETURNS JSON AS $$
BEGIN
  IF NOT _verify_admin(pw_hash) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  -- Only allow specific field updates
  UPDATE users SET
    kyc_status = COALESCE(p_updates->>'kyc_status', kyc_status),
    account_type = COALESCE(p_updates->>'account_type', account_type)
  WHERE id = p_user_id;

  RETURN json_build_object('success', FOUND);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Admin: Delete user ──
CREATE OR REPLACE FUNCTION admin_delete_user(
  pw_hash TEXT,
  p_user_id UUID
)
RETURNS JSON AS $$
BEGIN
  IF NOT _verify_admin(pw_hash) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  DELETE FROM users WHERE id = p_user_id;

  RETURN json_build_object('success', FOUND);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Admin: Mark message as read ──
CREATE OR REPLACE FUNCTION admin_mark_message_read(
  pw_hash TEXT,
  p_message_id UUID
)
RETURNS JSON AS $$
BEGIN
  IF NOT _verify_admin(pw_hash) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  UPDATE messages SET is_read = true WHERE id = p_message_id;

  RETURN json_build_object('success', FOUND);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Admin: Delete message ──
CREATE OR REPLACE FUNCTION admin_delete_message(
  pw_hash TEXT,
  p_message_id UUID
)
RETURNS JSON AS $$
BEGIN
  IF NOT _verify_admin(pw_hash) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  DELETE FROM messages WHERE id = p_message_id;

  RETURN json_build_object('success', FOUND);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Admin: Read all listings (including non-active) ──
CREATE OR REPLACE FUNCTION admin_get_listings(pw_hash TEXT)
RETURNS JSON AS $$
BEGIN
  IF NOT _verify_admin(pw_hash) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  RETURN (
    SELECT json_build_object(
      'success', true,
      'data', COALESCE(json_agg(row_to_json(l) ORDER BY l.created_at DESC), '[]'::json)
    )
    FROM listings l
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Admin: Read all users ──
CREATE OR REPLACE FUNCTION admin_get_users(pw_hash TEXT)
RETURNS JSON AS $$
BEGIN
  IF NOT _verify_admin(pw_hash) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  RETURN (
    SELECT json_build_object(
      'success', true,
      'data', COALESCE(json_agg(row_to_json(u) ORDER BY u.created_at DESC), '[]'::json)
    )
    FROM users u
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Admin: Read all messages ──
CREATE OR REPLACE FUNCTION admin_get_messages(pw_hash TEXT)
RETURNS JSON AS $$
BEGIN
  IF NOT _verify_admin(pw_hash) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  RETURN (
    SELECT json_build_object(
      'success', true,
      'data', COALESCE(json_agg(row_to_json(m) ORDER BY m.created_at DESC), '[]'::json)
    )
    FROM messages m
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to anon (admin verifies internally via pw_hash)
GRANT EXECUTE ON FUNCTION _verify_admin TO anon;
GRANT EXECUTE ON FUNCTION admin_update_content TO anon;
GRANT EXECUTE ON FUNCTION admin_update_settings TO anon;
GRANT EXECUTE ON FUNCTION admin_update_listing TO anon;
GRANT EXECUTE ON FUNCTION admin_delete_listing TO anon;
GRANT EXECUTE ON FUNCTION admin_update_user TO anon;
GRANT EXECUTE ON FUNCTION admin_delete_user TO anon;
GRANT EXECUTE ON FUNCTION admin_mark_message_read TO anon;
GRANT EXECUTE ON FUNCTION admin_delete_message TO anon;
GRANT EXECUTE ON FUNCTION admin_get_listings TO anon;
GRANT EXECUTE ON FUNCTION admin_get_users TO anon;
GRANT EXECUTE ON FUNCTION admin_get_messages TO anon;
