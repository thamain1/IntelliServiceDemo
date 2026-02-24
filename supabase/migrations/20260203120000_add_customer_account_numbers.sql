/*
  # Add Customer Account Numbers

  Implements a structured account numbering system:
  - RES-0001 for Residential
  - COM-0001 for Commercial
  - GOV-0001 for Government/Municipal

  Also adds external_id for Payzer reference during transition.
*/

-- Add customer_type enum
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'customer_type') THEN
    CREATE TYPE customer_type AS ENUM ('residential', 'commercial', 'government');
  END IF;
END
$$;

-- Add new columns to customers table
ALTER TABLE customers
ADD COLUMN IF NOT EXISTS account_number text UNIQUE,
ADD COLUMN IF NOT EXISTS customer_type customer_type DEFAULT 'residential',
ADD COLUMN IF NOT EXISTS external_id text;

-- Create index on external_id for Payzer lookups
CREATE INDEX IF NOT EXISTS idx_customers_external_id ON customers(external_id);

-- Create sequence tables for each customer type
CREATE TABLE IF NOT EXISTS customer_account_sequences (
  customer_type customer_type PRIMARY KEY,
  last_number integer NOT NULL DEFAULT 0
);

-- Initialize sequences
INSERT INTO customer_account_sequences (customer_type, last_number) VALUES
  ('residential', 0),
  ('commercial', 0),
  ('government', 0)
ON CONFLICT (customer_type) DO NOTHING;

-- Function to generate next account number
CREATE OR REPLACE FUNCTION fn_generate_account_number(p_customer_type customer_type)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_prefix text;
  v_next_num integer;
  v_account_number text;
BEGIN
  -- Determine prefix based on type
  CASE p_customer_type
    WHEN 'residential' THEN v_prefix := 'RES';
    WHEN 'commercial' THEN v_prefix := 'COM';
    WHEN 'government' THEN v_prefix := 'GOV';
    ELSE v_prefix := 'RES';
  END CASE;

  -- Get and increment sequence
  UPDATE customer_account_sequences
  SET last_number = last_number + 1
  WHERE customer_type = p_customer_type
  RETURNING last_number INTO v_next_num;

  -- Format account number with leading zeros (4 digits)
  v_account_number := v_prefix || '-' || LPAD(v_next_num::text, 4, '0');

  RETURN v_account_number;
END;
$$;

-- Trigger function to auto-assign account number on insert
CREATE OR REPLACE FUNCTION fn_assign_account_number()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Only assign if account_number is not provided
  IF NEW.account_number IS NULL THEN
    NEW.account_number := fn_generate_account_number(COALESCE(NEW.customer_type, 'residential'));
  END IF;
  RETURN NEW;
END;
$$;

-- Create trigger
DROP TRIGGER IF EXISTS trg_assign_account_number ON customers;
CREATE TRIGGER trg_assign_account_number
  BEFORE INSERT ON customers
  FOR EACH ROW
  EXECUTE FUNCTION fn_assign_account_number();

-- Backfill existing customers with account numbers
-- Assuming all imported Payzer customers are residential for now
DO $$
DECLARE
  v_customer RECORD;
  v_account_num text;
BEGIN
  FOR v_customer IN
    SELECT id FROM customers
    WHERE account_number IS NULL
    ORDER BY created_at ASC
  LOOP
    v_account_num := fn_generate_account_number('residential');
    UPDATE customers SET account_number = v_account_num WHERE id = v_customer.id;
  END LOOP;

  RAISE NOTICE 'Assigned account numbers to existing customers';
END;
$$;

-- Add comment for documentation
COMMENT ON COLUMN customers.account_number IS 'Unique account number (RES-0001, COM-0001, GOV-0001)';
COMMENT ON COLUMN customers.customer_type IS 'Customer type: residential, commercial, or government';
COMMENT ON COLUMN customers.external_id IS 'External reference ID (e.g., Payzer customer number)';
