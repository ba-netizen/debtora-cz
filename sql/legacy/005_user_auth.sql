-- ============================================================
-- DEBTORA CZ — Additional SQL Functions
-- Run AFTER 004_functions.sql
-- Adds: user_login, get_listing_detail
-- ============================================================

-- ── USER LOGIN ──
CREATE OR REPLACE FUNCTION user_login(user_email TEXT, pw_hash TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  found_user RECORD;
BEGIN
  SELECT id, email, name, company, phone, ico, account_type, kyc_status, created_at
  INTO found_user
  FROM users
  WHERE email = user_email AND password_hash = pw_hash;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Nesprávný e-mail nebo heslo.');
  END IF;

  RETURN json_build_object(
    'success', true,
    'user', json_build_object(
      'id', found_user.id,
      'email', found_user.email,
      'name', found_user.name,
      'company', found_user.company,
      'phone', found_user.phone,
      'ico', found_user.ico,
      'account_type', found_user.account_type,
      'kyc_status', found_user.kyc_status,
      'created_at', found_user.created_at
    )
  );
END;
$$;

-- ── GET FULL LISTING DETAIL (for authenticated users) ──
CREATE OR REPLACE FUNCTION get_listing_detail(listing_uuid UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  found RECORD;
BEGIN
  -- Increment views
  UPDATE listings SET views = COALESCE(views, 0) + 1 WHERE id = listing_uuid;

  SELECT * INTO found FROM listings WHERE id = listing_uuid;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Inzerát nenalezen.');
  END IF;

  RETURN json_build_object('success', true, 'listing', row_to_json(found));
END;
$$;
