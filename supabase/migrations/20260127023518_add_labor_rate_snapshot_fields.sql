/*
  # Add Labor Rate Snapshot Fields

  ## Overview
  Add snapshot fields to time_logs and estimate_line_items to capture labor rate 
  resolution at the time of entry creation, ensuring stable billing regardless of 
  future rate changes. Supports service contract overrides and audit trail.

  ## 1. Time Logs Enhancements
  
  Add fields to time_logs:
  - rate_source - Where the rate came from ('settings'|'contract'|'customer'|'override')
  - contract_id_applied - Which service contract (if any) provided the rate
  - is_covered - Whether this work is covered by service contract
  - override_reason - Explanation if rate was manually overridden
  - overridden_by - User who performed override
  - overridden_at - When override occurred

  Note: rate_tier already exists (uses labor_rate_tier enum)
  Note: billing_rate_applied already exists

  ## 2. Estimate Line Items Enhancements
  
  Add fields to estimate_line_items for labor items:
  - rate_type - Type of rate applied (uses labor_rate_tier enum)
  - rate_source - Where the rate came from
  - bill_rate - Snapshot of the billing rate (same as existing unit_price for labor)
  - contract_id_applied - Which service contract (if any) provided the rate
  - is_covered - Whether this work would be covered by service contract
  - override_reason - Explanation if rate was manually overridden
  - overridden_by - User who performed override
  - overridden_at - When override occurred

  ## 3. Create rate_source enum
  
  Define rate source enum for clarity

  ## Security
  - No RLS changes needed (inherit from tables)
  - Existing policies remain in effect

  ## Notes
  - Additive only - no DROP/ALTER of existing columns
  - Backwards compatible - all new fields nullable
  - Snapshot fields prevent rate drift when settings change
*/

-- Create rate_source enum
DO $$ BEGIN
  CREATE TYPE rate_source AS ENUM ('settings', 'contract', 'customer', 'override');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- Add snapshot fields to time_logs
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'time_logs' AND column_name = 'rate_source'
  ) THEN
    ALTER TABLE time_logs ADD COLUMN rate_source rate_source;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'time_logs' AND column_name = 'contract_id_applied'
  ) THEN
    ALTER TABLE time_logs ADD COLUMN contract_id_applied uuid REFERENCES service_contracts(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'time_logs' AND column_name = 'is_covered'
  ) THEN
    ALTER TABLE time_logs ADD COLUMN is_covered boolean;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'time_logs' AND column_name = 'override_reason'
  ) THEN
    ALTER TABLE time_logs ADD COLUMN override_reason text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'time_logs' AND column_name = 'overridden_by'
  ) THEN
    ALTER TABLE time_logs ADD COLUMN overridden_by uuid REFERENCES profiles(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'time_logs' AND column_name = 'overridden_at'
  ) THEN
    ALTER TABLE time_logs ADD COLUMN overridden_at timestamptz;
  END IF;
END $$;

-- Add snapshot fields to estimate_line_items
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'estimate_line_items' AND column_name = 'rate_type'
  ) THEN
    ALTER TABLE estimate_line_items ADD COLUMN rate_type labor_rate_tier;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'estimate_line_items' AND column_name = 'rate_source'
  ) THEN
    ALTER TABLE estimate_line_items ADD COLUMN rate_source rate_source;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'estimate_line_items' AND column_name = 'bill_rate'
  ) THEN
    ALTER TABLE estimate_line_items ADD COLUMN bill_rate numeric(10,2);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'estimate_line_items' AND column_name = 'contract_id_applied'
  ) THEN
    ALTER TABLE estimate_line_items ADD COLUMN contract_id_applied uuid REFERENCES service_contracts(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'estimate_line_items' AND column_name = 'is_covered'
  ) THEN
    ALTER TABLE estimate_line_items ADD COLUMN is_covered boolean;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'estimate_line_items' AND column_name = 'override_reason'
  ) THEN
    ALTER TABLE estimate_line_items ADD COLUMN override_reason text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'estimate_line_items' AND column_name = 'overridden_by'
  ) THEN
    ALTER TABLE estimate_line_items ADD COLUMN overridden_by uuid REFERENCES profiles(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'estimate_line_items' AND column_name = 'overridden_at'
  ) THEN
    ALTER TABLE estimate_line_items ADD COLUMN overridden_at timestamptz;
  END IF;
END $$;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_time_logs_contract_applied ON time_logs(contract_id_applied) WHERE contract_id_applied IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_time_logs_rate_source ON time_logs(rate_source);
CREATE INDEX IF NOT EXISTS idx_estimate_line_items_contract_applied ON estimate_line_items(contract_id_applied) WHERE contract_id_applied IS NOT NULL;

-- Add comments
COMMENT ON COLUMN time_logs.rate_source IS 'Source of the billing rate: settings (global), contract (service contract), customer (custom rate), override (manual)';
COMMENT ON COLUMN time_logs.contract_id_applied IS 'Service contract that provided the billing rate, if applicable';
COMMENT ON COLUMN time_logs.is_covered IS 'Whether this work is covered under a service contract';
COMMENT ON COLUMN time_logs.override_reason IS 'Explanation for manual rate override';

COMMENT ON COLUMN estimate_line_items.rate_type IS 'Labor rate type: standard, after_hours, or emergency';
COMMENT ON COLUMN estimate_line_items.rate_source IS 'Source of the billing rate for labor items';
COMMENT ON COLUMN estimate_line_items.bill_rate IS 'Snapshot of billing rate per hour for labor items';
COMMENT ON COLUMN estimate_line_items.contract_id_applied IS 'Service contract that would provide this rate, if applicable';
COMMENT ON COLUMN estimate_line_items.is_covered IS 'Whether this labor would be covered under a service contract';
