/*
  # Fix Jacob's auth.users entry

  The auth.users record was corrupted by direct SQL password updates.
  This migration recreates the auth.users entry properly.
*/

-- First, check if the user exists and delete if corrupted
DO $$
DECLARE
  v_user_id uuid := 'd4812070-f3c8-442d-b433-639ec6a41033';
  v_exists boolean;
BEGIN
  -- Check if user exists in auth.users
  SELECT EXISTS (
    SELECT 1 FROM auth.users WHERE id = v_user_id
  ) INTO v_exists;

  IF v_exists THEN
    -- Delete the corrupted user
    DELETE FROM auth.users WHERE id = v_user_id;
    RAISE NOTICE 'Deleted corrupted auth.users record for Jacob';
  ELSE
    RAISE NOTICE 'No existing auth.users record found for Jacob';
  END IF;

  -- Now create a fresh auth.users entry
  INSERT INTO auth.users (
    id,
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    created_at,
    updated_at,
    raw_app_meta_data,
    raw_user_meta_data,
    aud,
    role,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change
  ) VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'jacob@dunawayheating.com',
    crypt('demo1234!', gen_salt('bf')),
    now(),
    now(),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{}',
    'authenticated',
    'authenticated',
    '',
    '',
    '',
    ''
  );

  RAISE NOTICE 'Created fresh auth.users record for Jacob with password demo1234!';
END;
$$;
