/*
  # Create Jacob's auth.users entry

  Jacob has a profile record but no auth.users entry.
  This migration creates the auth.users record WITHOUT deleting anything.

  User ID: d4812070-f3c8-442d-b433-639ec6a41033
  Email: jacob@dunawayheating.com
  Password: demo1234!
*/

-- Insert Jacob into auth.users if not exists
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
)
SELECT
  'd4812070-f3c8-442d-b433-639ec6a41033'::uuid,
  '00000000-0000-0000-0000-000000000000'::uuid,
  'jacob@dunawayheating.com',
  crypt('demo1234!', gen_salt('bf')),
  now(),
  now(),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  'authenticated',
  'authenticated',
  '',
  '',
  '',
  ''
WHERE NOT EXISTS (
  SELECT 1 FROM auth.users WHERE id = 'd4812070-f3c8-442d-b433-639ec6a41033'::uuid
);

-- Verify the insert worked
DO $$
DECLARE
  v_exists boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM auth.users WHERE id = 'd4812070-f3c8-442d-b433-639ec6a41033'
  ) INTO v_exists;

  IF v_exists THEN
    RAISE NOTICE 'SUCCESS: Jacob auth.users record exists. Password: demo1234!';
  ELSE
    RAISE EXCEPTION 'FAILED: Could not create auth.users record for Jacob';
  END IF;
END;
$$;
