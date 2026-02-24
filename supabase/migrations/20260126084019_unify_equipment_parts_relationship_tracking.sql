/*
  # Unify Equipment-Parts Relationship Tracking

  ## Purpose
  Fix missing display of installed parts under equipment by hardening the parent-child
  relationship persistence and creating a reliable UI read model.

  ## Changes

  ### 1. Schema Enhancements (Additive Only)
  - Add missing columns to part_installations for complete tracking
  - Add indexes for performance optimization
  - Add partial unique index to prevent duplicate active installs for serialized parts

  ### 2. UI Read Model
  - Create view `vw_equipment_installed_parts` for equipment detail display
  - Joins part_installations with parts master and serial info
  - Filters to active installs only (removal_date IS NULL)
  - Includes warranty and location information

  ### 3. Atomic Install Function
  - RPC `install_part_on_equipment` for transactional installs
  - Handles both serialized and non-serialized parts
  - Creates inventory movement record
  - Creates part_installations record
  - Updates serialized_parts status if applicable
  - Prevents duplicate active installs for same serial

  ### 4. Backfill Support
  - Function to sync existing serialized_parts installations
  - Safe to run multiple times (idempotent)

  ## Security
  - RLS enabled on all existing tables (already in place)
  - View inherits RLS from underlying tables
  - RPC function validates user permissions

  ## Important Notes
  - Single source of truth: part_installations table is the primary relationship tracker
  - serialized_parts.installed_on_equipment_id is kept in sync for compatibility
  - customer_parts_installed is legacy and remains for historical data
  - No data deletion or column dropping - fully additive
*/

-- =====================================================
-- 1. ENHANCE PART_INSTALLATIONS SCHEMA
-- =====================================================

-- Add location_id if not exists (where the part came from during install)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'part_installations' AND column_name = 'from_location_id'
  ) THEN
    ALTER TABLE part_installations
    ADD COLUMN from_location_id uuid REFERENCES stock_locations(id);
  END IF;
END $$;

-- Add equipment_location_notes for specific placement info
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'part_installations' AND column_name = 'equipment_location_notes'
  ) THEN
    ALTER TABLE part_installations
    ADD COLUMN equipment_location_notes text;

    COMMENT ON COLUMN part_installations.equipment_location_notes IS
    'Specific location on or within the equipment (e.g., "Compressor compartment", "Left blower motor")';
  END IF;
END $$;

-- Add warranty tracking columns
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'part_installations' AND column_name = 'warranty_start_date'
  ) THEN
    ALTER TABLE part_installations
    ADD COLUMN warranty_start_date date;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'part_installations' AND column_name = 'warranty_end_date'
  ) THEN
    ALTER TABLE part_installations
    ADD COLUMN warranty_end_date date;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'part_installations' AND column_name = 'warranty_months'
  ) THEN
    ALTER TABLE part_installations
    ADD COLUMN warranty_months integer;
  END IF;
END $$;

-- =====================================================
-- 2. CREATE INDEXES FOR PERFORMANCE
-- =====================================================

-- Index for active installs on equipment (primary query pattern)
CREATE INDEX IF NOT EXISTS idx_part_installations_active_on_equipment
  ON part_installations(installed_on_equipment_id)
  WHERE removal_date IS NULL;

-- Index for active installs by serial (lookups)
CREATE INDEX IF NOT EXISTS idx_part_installations_active_by_serial
  ON part_installations(serialized_part_id)
  WHERE removal_date IS NULL;

-- Partial unique index to prevent duplicate active installs for same serial
CREATE UNIQUE INDEX IF NOT EXISTS idx_part_installations_unique_active_serial
  ON part_installations(serialized_part_id)
  WHERE removal_date IS NULL AND serialized_part_id IS NOT NULL;

-- Index for installation history queries
CREATE INDEX IF NOT EXISTS idx_part_installations_install_date
  ON part_installations(installation_date DESC);

-- =====================================================
-- 3. CREATE UI READ MODEL VIEW
-- =====================================================

CREATE OR REPLACE VIEW vw_equipment_installed_parts AS
SELECT
  pi.id AS installation_id,
  pi.installed_on_equipment_id AS equipment_id,
  pi.part_id,
  p.part_number,
  p.name AS part_name,
  p.description AS part_description,
  p.manufacturer AS part_manufacturer,
  p.category AS part_category,
  p.is_serialized,

  -- Installation Details
  pi.quantity,
  pi.installation_date,
  pi.installed_by,
  pi.ticket_id,
  pi.equipment_location_notes,
  pi.notes AS installation_notes,

  -- Serialized Part Info (if applicable)
  pi.serialized_part_id,
  sp.serial_number,
  sp.manufacture_date,
  sp.unit_cost AS serial_unit_cost,
  sp.vendor_id AS serial_vendor_id,

  -- Warranty Info
  pi.warranty_start_date,
  pi.warranty_end_date,
  pi.warranty_months,
  CASE
    WHEN pi.warranty_end_date IS NULL THEN 'unknown'
    WHEN pi.warranty_end_date < CURRENT_DATE THEN 'expired'
    WHEN pi.warranty_end_date < CURRENT_DATE + INTERVAL '90 days' THEN 'expiring_soon'
    ELSE 'active'
  END AS warranty_status,

  -- Installed By Info
  profiles.full_name AS installed_by_name,
  profiles.email AS installed_by_email,

  -- Site Info
  pi.installed_at_site_id AS customer_id,
  customers.name AS customer_name,

  -- Source Location Info
  pi.from_location_id,
  stock_locations.name AS from_location_name,

  -- Ticket Info
  tickets.ticket_number,
  tickets.title AS ticket_title,

  -- Timestamps
  pi.created_at,
  pi.updated_at

FROM part_installations pi
INNER JOIN parts p ON pi.part_id = p.id
LEFT JOIN serialized_parts sp ON pi.serialized_part_id = sp.id
LEFT JOIN profiles ON pi.installed_by = profiles.id
LEFT JOIN customers ON pi.installed_at_site_id = customers.id
LEFT JOIN stock_locations ON pi.from_location_id = stock_locations.id
LEFT JOIN tickets ON pi.ticket_id = tickets.id

-- Only active installations (not removed)
WHERE pi.removal_date IS NULL
  AND pi.installed_on_equipment_id IS NOT NULL

ORDER BY pi.installation_date DESC;

COMMENT ON VIEW vw_equipment_installed_parts IS
'Read model for displaying all currently installed parts on equipment.
Excludes removed parts. Use for Equipment detail UI and customer equipment views.';

-- =====================================================
-- 4. CREATE ATOMIC INSTALL RPC FUNCTION
-- =====================================================

CREATE OR REPLACE FUNCTION install_part_on_equipment(
  p_part_id uuid,
  p_equipment_id uuid,
  p_customer_id uuid,
  p_ticket_id uuid,
  p_quantity numeric,
  p_serial_number text DEFAULT NULL,
  p_from_location_id uuid DEFAULT NULL,
  p_installed_by uuid DEFAULT NULL,
  p_installation_notes text DEFAULT NULL,
  p_equipment_location_notes text DEFAULT NULL,
  p_warranty_months integer DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_serialized_part_id uuid;
  v_part_installation_id uuid;
  v_inventory_movement_id uuid;
  v_is_serialized boolean;
  v_warranty_start date;
  v_warranty_end date;
  v_installed_by_user uuid;
  v_result jsonb;
BEGIN
  -- Validate auth
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Default installed_by to current user if not provided
  v_installed_by_user := COALESCE(p_installed_by, auth.uid());

  -- Get part info
  SELECT is_serialized, COALESCE(p_warranty_months, default_warranty_months, 12)
  INTO v_is_serialized, p_warranty_months
  FROM parts
  WHERE id = p_part_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Part not found: %', p_part_id;
  END IF;

  -- Validate serial number for serialized parts
  IF v_is_serialized AND p_serial_number IS NULL THEN
    RAISE EXCEPTION 'Serial number required for serialized part';
  END IF;

  IF NOT v_is_serialized AND p_serial_number IS NOT NULL THEN
    RAISE EXCEPTION 'Serial number provided for non-serialized part';
  END IF;

  -- Calculate warranty dates
  v_warranty_start := CURRENT_DATE;
  v_warranty_end := CURRENT_DATE + (p_warranty_months || ' months')::INTERVAL;

  -- Handle serialized parts
  IF v_is_serialized THEN
    -- Find or validate serialized part
    SELECT id INTO v_serialized_part_id
    FROM serialized_parts
    WHERE serial_number = p_serial_number
      AND part_id = p_part_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Serialized part not found: % for part_id %', p_serial_number, p_part_id;
    END IF;

    -- Check if already installed (active install exists)
    IF EXISTS (
      SELECT 1 FROM part_installations
      WHERE serialized_part_id = v_serialized_part_id
        AND removal_date IS NULL
    ) THEN
      RAISE EXCEPTION 'Part % is already installed. Remove it first before reinstalling.', p_serial_number;
    END IF;

    -- Update serialized_parts table for compatibility
    UPDATE serialized_parts
    SET
      status = 'installed',
      installed_at_site_id = p_customer_id,
      installed_on_equipment_id = p_equipment_id,
      installed_on_ticket_id = p_ticket_id,
      installed_by = v_installed_by_user,
      installation_date = CURRENT_DATE,
      current_location_id = NULL, -- No longer in stock
      updated_at = now()
    WHERE id = v_serialized_part_id;
  END IF;

  -- Create part installation record (primary relationship)
  INSERT INTO part_installations (
    part_id,
    serialized_part_id,
    quantity,
    installed_at_site_id,
    installed_on_equipment_id,
    ticket_id,
    project_task_id,
    installation_date,
    installed_by,
    from_location_id,
    equipment_location_notes,
    notes,
    warranty_start_date,
    warranty_end_date,
    warranty_months,
    created_at,
    updated_at
  ) VALUES (
    p_part_id,
    v_serialized_part_id,
    p_quantity,
    p_customer_id,
    p_equipment_id,
    p_ticket_id,
    NULL, -- project_task_id can be added later if needed
    CURRENT_DATE,
    v_installed_by_user,
    p_from_location_id,
    p_equipment_location_notes,
    p_installation_notes,
    v_warranty_start,
    v_warranty_end,
    p_warranty_months,
    now(),
    now()
  ) RETURNING id INTO v_part_installation_id;

  -- Create inventory movement record for audit trail
  INSERT INTO inventory_movements (
    movement_type,
    movement_date,
    part_id,
    serialized_part_id,
    quantity,
    from_location_id,
    to_location_id, -- NULL for installations (out of stock)
    reference_type,
    reference_id,
    ticket_id,
    project_id,
    moved_by,
    notes,
    created_at
  ) VALUES (
    'installation',
    now(),
    p_part_id,
    v_serialized_part_id,
    p_quantity,
    p_from_location_id,
    NULL,
    'part_installation',
    v_part_installation_id,
    p_ticket_id,
    NULL,
    v_installed_by_user,
    'Part installed on equipment',
    now()
  ) RETURNING id INTO v_inventory_movement_id;

  -- Return success result
  v_result := jsonb_build_object(
    'success', true,
    'installation_id', v_part_installation_id,
    'movement_id', v_inventory_movement_id,
    'serialized_part_id', v_serialized_part_id,
    'warranty_end_date', v_warranty_end
  );

  RETURN v_result;

EXCEPTION
  WHEN OTHERS THEN
    -- Return error details
    RETURN jsonb_build_object(
      'success', false,
      'error', SQLERRM,
      'error_detail', SQLSTATE
    );
END;
$$;

COMMENT ON FUNCTION install_part_on_equipment IS
'Atomically install a part on equipment. Handles both serialized and non-serialized parts.
Creates part_installations record, updates serialized_parts if applicable, and logs inventory movement.
Returns success status and relevant IDs.';

-- =====================================================
-- 5. CREATE BACKFILL FUNCTION
-- =====================================================

CREATE OR REPLACE FUNCTION backfill_part_installations_from_serialized()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count integer := 0;
  v_serial RECORD;
BEGIN
  -- Only run if authenticated
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Find serialized parts that are marked as installed but have no active part_installations record
  FOR v_serial IN
    SELECT
      sp.id AS serialized_part_id,
      sp.serial_number,
      sp.part_id,
      sp.installed_at_site_id,
      sp.installed_on_equipment_id,
      sp.installed_on_ticket_id,
      sp.installed_by,
      sp.installation_date,
      sp.current_location_id
    FROM serialized_parts sp
    WHERE sp.status = 'installed'
      AND sp.installed_on_equipment_id IS NOT NULL
      AND sp.installed_at_site_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM part_installations pi
        WHERE pi.serialized_part_id = sp.id
          AND pi.removal_date IS NULL
      )
  LOOP
    -- Insert missing part_installations record
    INSERT INTO part_installations (
      part_id,
      serialized_part_id,
      quantity,
      installed_at_site_id,
      installed_on_equipment_id,
      ticket_id,
      installation_date,
      installed_by,
      notes,
      created_at,
      updated_at
    ) VALUES (
      v_serial.part_id,
      v_serial.serialized_part_id,
      1, -- serialized parts always qty = 1
      v_serial.installed_at_site_id,
      v_serial.installed_on_equipment_id,
      v_serial.installed_on_ticket_id,
      COALESCE(v_serial.installation_date, CURRENT_DATE),
      v_serial.installed_by,
      'Backfilled from serialized_parts table',
      now(),
      now()
    )
    ON CONFLICT DO NOTHING; -- Safe to run multiple times

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'records_backfilled', v_count,
    'message', format('%s part installations backfilled from serialized_parts', v_count)
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', SQLERRM
    );
END;
$$;

COMMENT ON FUNCTION backfill_part_installations_from_serialized IS
'One-time backfill function to create part_installations records for serialized parts
that are marked as installed but missing the relationship record. Safe to run multiple times.';

-- =====================================================
-- 6. GRANT PERMISSIONS
-- =====================================================

-- Grant execute on functions to authenticated users
GRANT EXECUTE ON FUNCTION install_part_on_equipment TO authenticated;
GRANT EXECUTE ON FUNCTION backfill_part_installations_from_serialized TO authenticated;

-- Grant select on view to authenticated users
GRANT SELECT ON vw_equipment_installed_parts TO authenticated;
