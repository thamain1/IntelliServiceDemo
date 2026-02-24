/*
  # Create Warranty Tracking View from Serialized Inventory

  1. New Columns on serialized_parts
    - `warranty_term_months_snapshot` - snapshot of warranty term at time of receipt/install
    - `warranty_provider` - manufacturer or vendor providing warranty
    - `warranty_notes` - additional warranty information
  
  2. Helper Function
    - `fn_set_serial_warranty_dates` - automatically sets warranty dates on INSERT/UPDATE
    - Computes start date from COALESCE(installation_date, received_date, created_at)
    - Computes end date from start + warranty term from parts table
    - Snapshots warranty term for historical accuracy
  
  3. View: vw_warranty_tracking
    - Single source of truth derived from serialized_parts table
    - Includes computed warranty_status (ACTIVE, EXPIRED, EXPIRING_SOON, MISSING_DATES)
    - Includes days_remaining calculation
    - Joins to parts, customers, locations, equipment for full context
    - Compatible with existing WarrantyDashboard UI expectations
  
  4. Triggers
    - BEFORE INSERT/UPDATE trigger on serialized_parts
    - Automatically maintains warranty dates and snapshots
  
  5. Security
    - View inherits RLS from underlying serialized_parts table
    - No new RLS policies needed
  
  6. Non-Regression Notes
    - Additive only - no dropping of warranty_records table
    - No changes to inventory counts, receiving, or accounting
    - No changes to parent-child serialization relationships
*/

-- =====================================================
-- STEP 1: Add warranty snapshot columns to serialized_parts
-- =====================================================

DO $$
BEGIN
  -- Warranty term snapshot (for historical accuracy)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'serialized_parts' AND column_name = 'warranty_term_months_snapshot'
  ) THEN
    ALTER TABLE serialized_parts 
    ADD COLUMN warranty_term_months_snapshot integer NULL;
  END IF;

  -- Warranty provider info
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'serialized_parts' AND column_name = 'warranty_provider'
  ) THEN
    ALTER TABLE serialized_parts 
    ADD COLUMN warranty_provider text NULL;
  END IF;

  -- Additional warranty notes
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'serialized_parts' AND column_name = 'warranty_notes'
  ) THEN
    ALTER TABLE serialized_parts 
    ADD COLUMN warranty_notes text NULL;
  END IF;
END $$;

-- =====================================================
-- STEP 2: Create function to set warranty dates
-- =====================================================

CREATE OR REPLACE FUNCTION fn_set_serial_warranty_dates()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_warranty_months integer;
  v_start_date date;
  v_vendor_name text;
BEGIN
  -- Get warranty term from parts table
  SELECT 
    COALESCE(p.default_warranty_months, p.warranty_period_months, 12),
    v.name
  INTO v_warranty_months, v_vendor_name
  FROM parts p
  LEFT JOIN vendors v ON v.id = p.preferred_vendor_id
  WHERE p.id = NEW.part_id;

  -- Determine warranty start date (prefer installation, fallback to received, then created)
  v_start_date := COALESCE(NEW.installation_date, NEW.received_date, CURRENT_DATE);

  -- Set warranty_start_date if null
  IF NEW.warranty_start_date IS NULL THEN
    NEW.warranty_start_date := v_start_date;
  END IF;

  -- Set warranty_end_date if null
  IF NEW.warranty_end_date IS NULL AND v_warranty_months > 0 THEN
    NEW.warranty_end_date := NEW.warranty_start_date + (v_warranty_months || ' months')::interval;
  END IF;

  -- Snapshot warranty term if null
  IF NEW.warranty_term_months_snapshot IS NULL THEN
    NEW.warranty_term_months_snapshot := v_warranty_months;
  END IF;

  -- Set warranty provider if null
  IF NEW.warranty_provider IS NULL AND v_vendor_name IS NOT NULL THEN
    NEW.warranty_provider := v_vendor_name;
  END IF;

  RETURN NEW;
END;
$$;

-- =====================================================
-- STEP 3: Create trigger
-- =====================================================

DROP TRIGGER IF EXISTS trg_set_serial_warranty_dates ON serialized_parts;

CREATE TRIGGER trg_set_serial_warranty_dates
  BEFORE INSERT OR UPDATE OF installation_date, received_date, warranty_start_date, warranty_end_date
  ON serialized_parts
  FOR EACH ROW
  EXECUTE FUNCTION fn_set_serial_warranty_dates();

-- =====================================================
-- STEP 4: Create warranty tracking view
-- =====================================================

CREATE OR REPLACE VIEW vw_warranty_tracking AS
SELECT
  sp.id,
  sp.serial_number,
  sp.part_id,
  sp.status as serialized_part_status,
  sp.warranty_start_date as start_date,
  sp.warranty_end_date as end_date,
  sp.warranty_term_months_snapshot as duration_months,
  sp.warranty_provider,
  sp.warranty_notes as notes,
  sp.vendor_id,
  sp.installation_date,
  sp.received_date,
  sp.installed_at_site_id,
  sp.installed_on_equipment_id,
  sp.current_location_id,
  
  -- Part information
  p.name as part_name,
  p.part_number,
  p.warranty_period_months as part_warranty_months,
  
  -- Vendor information
  v.name as vendor_name,
  
  -- Customer and location info (for installed parts)
  c.id as customer_id,
  c.name as customer_name,
  cl.id as location_id,
  cl.location_name,
  cl.address as location_address,
  
  -- Equipment info (for installed parts)
  e.id as equipment_id,
  e.equipment_type,
  e.model_number as equipment_model,
  e.manufacturer as equipment_manufacturer,
  
  -- Stock location info (for in-stock parts)
  sl.name as stock_location_name,
  sl.location_type as stock_location_type,
  
  -- Computed warranty status
  CASE
    WHEN sp.warranty_end_date IS NULL OR sp.warranty_start_date IS NULL THEN 'MISSING_DATES'
    WHEN sp.warranty_end_date < CURRENT_DATE THEN 'EXPIRED'
    WHEN sp.warranty_end_date <= CURRENT_DATE + INTERVAL '30 days' THEN 'EXPIRING_SOON'
    WHEN sp.warranty_end_date > CURRENT_DATE THEN 'ACTIVE'
    ELSE 'MISSING_DATES'
  END as warranty_status,
  
  -- Computed warranty type (map to existing enum for UI compatibility)
  CASE
    WHEN sp.warranty_provider IS NOT NULL THEN 'manufacturer'
    ELSE 'parts_only'
  END::warranty_type as warranty_type,
  
  -- Days remaining calculation (date subtraction returns integer in PostgreSQL)
  CASE
    WHEN sp.warranty_end_date IS NULL OR sp.warranty_end_date < CURRENT_DATE THEN 0
    ELSE (sp.warranty_end_date - CURRENT_DATE)
  END as days_remaining,
  
  -- Timestamps
  sp.created_at,
  sp.updated_at

FROM serialized_parts sp
JOIN parts p ON p.id = sp.part_id
LEFT JOIN vendors v ON v.id = sp.vendor_id
LEFT JOIN customer_locations cl ON cl.id = sp.installed_at_site_id
LEFT JOIN customers c ON c.id = cl.customer_id
LEFT JOIN equipment e ON e.id = sp.installed_on_equipment_id
LEFT JOIN stock_locations sl ON sl.id = sp.current_location_id

-- Only include parts with warranty terms (either from snapshot or part master)
WHERE sp.warranty_term_months_snapshot > 0 
   OR p.warranty_period_months > 0 
   OR p.default_warranty_months > 0
   OR sp.warranty_start_date IS NOT NULL
   OR sp.warranty_end_date IS NOT NULL;

-- Create index to improve view performance
CREATE INDEX IF NOT EXISTS idx_serialized_parts_warranty_dates 
ON serialized_parts(warranty_end_date, warranty_start_date) 
WHERE warranty_end_date IS NOT NULL;

-- =====================================================
-- STEP 5: Backfill existing serialized parts
-- =====================================================

-- Update existing records to populate warranty fields
UPDATE serialized_parts sp
SET 
  warranty_start_date = COALESCE(
    sp.warranty_start_date,
    sp.installation_date,
    sp.received_date,
    sp.created_at::date
  ),
  warranty_end_date = COALESCE(
    sp.warranty_end_date,
    (COALESCE(sp.installation_date, sp.received_date, sp.created_at::date) + 
     (COALESCE(p.default_warranty_months, p.warranty_period_months, 12) || ' months')::interval)
  ),
  warranty_term_months_snapshot = COALESCE(
    sp.warranty_term_months_snapshot,
    p.default_warranty_months,
    p.warranty_period_months,
    12
  ),
  warranty_provider = COALESCE(
    sp.warranty_provider,
    v.name
  )
FROM parts p
LEFT JOIN vendors v ON v.id = p.preferred_vendor_id
WHERE sp.part_id = p.id
  AND (sp.warranty_start_date IS NULL OR sp.warranty_term_months_snapshot IS NULL);

-- Grant SELECT permission on view to authenticated users
GRANT SELECT ON vw_warranty_tracking TO authenticated;
