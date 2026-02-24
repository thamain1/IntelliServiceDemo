/*
  # Estimate Costing and Conversion System

  ## Part A: Auto-populate Part Costs on Estimates
  
  1. New Columns on estimate_line_items:
    - `unit_cost` (numeric, nullable) - Cost per unit snapshot
    - `ext_cost` (numeric, nullable) - Extended cost (qty * unit_cost)
    - `cost_source` (text, nullable) - Where cost came from
    - `cost_as_of` (timestamptz, nullable) - When cost was snapshotted

  2. New View:
    - `vw_part_cost_current` - Resolves current cost from inventory/receiving data
      Priority: weighted avg cost -> last receipt cost -> part master default

  3. New Functions:
    - `fn_get_part_current_cost(part_id)` - Returns current cost for a part
    - `fn_refresh_estimate_part_costs(estimate_id)` - Refreshes all part costs

  4. Trigger:
    - Auto-populates cost on insert/update of part lines

  ## Part B: Convert Accepted Estimate to Service Ticket / Project

  1. New Table:
    - `estimate_conversions` - Tracks conversions for idempotency

  2. New Columns:
    - `source_estimate_id` on tickets table
    - `source_estimate_id` on projects table

  3. New Tables:
    - `ticket_parts_planned` - Planned parts from estimate
    - `ticket_labor_planned` - Planned labor from estimate

  4. New Functions:
    - `fn_convert_estimate_to_service_ticket(estimate_id)` - Creates service ticket
    - `fn_convert_estimate_to_project(estimate_id)` - Creates project

  ## Security
    - RLS enabled on new tables
    - Functions use SECURITY DEFINER with proper search_path
*/

-- ============================================================================
-- PART A: ESTIMATE COSTING
-- ============================================================================

-- Add cost columns to estimate_line_items
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'estimate_line_items' AND column_name = 'unit_cost'
  ) THEN
    ALTER TABLE estimate_line_items ADD COLUMN unit_cost numeric NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'estimate_line_items' AND column_name = 'ext_cost'
  ) THEN
    ALTER TABLE estimate_line_items ADD COLUMN ext_cost numeric NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'estimate_line_items' AND column_name = 'cost_source'
  ) THEN
    ALTER TABLE estimate_line_items ADD COLUMN cost_source text NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'estimate_line_items' AND column_name = 'cost_as_of'
  ) THEN
    ALTER TABLE estimate_line_items ADD COLUMN cost_as_of timestamptz NULL;
  END IF;
END $$;

-- Create view for current part cost resolution
CREATE OR REPLACE VIEW vw_part_cost_current AS
WITH inventory_weighted_avg AS (
  SELECT 
    pi.part_id,
    CASE 
      WHEN SUM(pi.quantity) > 0 THEN 
        SUM(COALESCE(pi.unit_cost, 0) * pi.quantity) / NULLIF(SUM(pi.quantity), 0)
      ELSE NULL
    END as weighted_avg_cost,
    MAX(pi.updated_at) as cost_as_of
  FROM part_inventory pi
  WHERE pi.quantity > 0 AND pi.unit_cost IS NOT NULL AND pi.unit_cost > 0
  GROUP BY pi.part_id
),
last_receipt AS (
  SELECT DISTINCT ON (pol.part_id)
    pol.part_id,
    pol.unit_price as last_receipt_cost,
    pol.updated_at as receipt_date
  FROM purchase_order_lines pol
  WHERE pol.quantity_received > 0 AND pol.unit_price IS NOT NULL AND pol.unit_price > 0
  ORDER BY pol.part_id, pol.updated_at DESC
)
SELECT 
  p.id as part_id,
  p.part_number,
  p.name as part_name,
  COALESCE(
    iwa.weighted_avg_cost,
    lr.last_receipt_cost,
    NULLIF(p.unit_price, 0)
  ) as unit_cost,
  CASE 
    WHEN iwa.weighted_avg_cost IS NOT NULL THEN 'inventory_weighted_avg'
    WHEN lr.last_receipt_cost IS NOT NULL THEN 'last_receipt'
    WHEN p.unit_price IS NOT NULL AND p.unit_price > 0 THEN 'part_master'
    ELSE 'unknown'
  END as source,
  COALESCE(iwa.cost_as_of, lr.receipt_date, p.updated_at) as as_of
FROM parts p
LEFT JOIN inventory_weighted_avg iwa ON iwa.part_id = p.id
LEFT JOIN last_receipt lr ON lr.part_id = p.id;

-- Function to get current cost for a single part
CREATE OR REPLACE FUNCTION fn_get_part_current_cost(p_part_id uuid)
RETURNS TABLE(unit_cost numeric, source text, as_of timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT vpc.unit_cost, vpc.source, vpc.as_of
  FROM vw_part_cost_current vpc
  WHERE vpc.part_id = p_part_id;
END;
$$;

-- Function to refresh all part costs for an estimate (Draft only)
CREATE OR REPLACE FUNCTION fn_refresh_estimate_part_costs(p_estimate_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_estimate_status text;
  v_updated_count integer := 0;
  v_line record;
BEGIN
  SELECT status::text INTO v_estimate_status
  FROM estimates
  WHERE id = p_estimate_id;

  IF v_estimate_status IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Estimate not found');
  END IF;

  IF v_estimate_status != 'draft' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Can only refresh costs for draft estimates');
  END IF;

  FOR v_line IN
    SELECT eli.id, eli.part_id, eli.quantity
    FROM estimate_line_items eli
    WHERE eli.estimate_id = p_estimate_id
      AND eli.item_type = 'parts'
      AND eli.part_id IS NOT NULL
  LOOP
    UPDATE estimate_line_items
    SET 
      unit_cost = vpc.unit_cost,
      ext_cost = v_line.quantity * vpc.unit_cost,
      cost_source = vpc.source,
      cost_as_of = vpc.as_of,
      updated_at = NOW()
    FROM vw_part_cost_current vpc
    WHERE estimate_line_items.id = v_line.id
      AND vpc.part_id = v_line.part_id;

    IF FOUND THEN
      v_updated_count := v_updated_count + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true, 
    'updated_count', v_updated_count,
    'refreshed_at', NOW()
  );
END;
$$;

-- Trigger function to auto-populate cost on part line insert/update
CREATE OR REPLACE FUNCTION fn_estimate_line_auto_cost()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_cost_info record;
BEGIN
  IF NEW.item_type = 'parts' AND NEW.part_id IS NOT NULL AND NEW.unit_cost IS NULL THEN
    SELECT unit_cost, source, as_of INTO v_cost_info
    FROM vw_part_cost_current
    WHERE part_id = NEW.part_id;

    IF v_cost_info.unit_cost IS NOT NULL THEN
      NEW.unit_cost := v_cost_info.unit_cost;
      NEW.ext_cost := COALESCE(NEW.quantity, 1) * v_cost_info.unit_cost;
      NEW.cost_source := v_cost_info.source;
      NEW.cost_as_of := v_cost_info.as_of;
    END IF;
  ELSIF NEW.item_type = 'parts' AND NEW.unit_cost IS NOT NULL THEN
    NEW.ext_cost := COALESCE(NEW.quantity, 1) * NEW.unit_cost;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_estimate_line_auto_cost ON estimate_line_items;
CREATE TRIGGER trg_estimate_line_auto_cost
  BEFORE INSERT OR UPDATE ON estimate_line_items
  FOR EACH ROW
  EXECUTE FUNCTION fn_estimate_line_auto_cost();

-- ============================================================================
-- PART B: ESTIMATE CONVERSION
-- ============================================================================

-- Add source_estimate_id to tickets if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tickets' AND column_name = 'source_estimate_id'
  ) THEN
    ALTER TABLE tickets ADD COLUMN source_estimate_id uuid NULL REFERENCES estimates(id);
  END IF;
END $$;

-- Add source_estimate_id to projects if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'projects' AND column_name = 'source_estimate_id'
  ) THEN
    ALTER TABLE projects ADD COLUMN source_estimate_id uuid NULL REFERENCES estimates(id);
  END IF;
END $$;

-- Create estimate_conversions table for idempotency
CREATE TABLE IF NOT EXISTS estimate_conversions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  estimate_id uuid NOT NULL UNIQUE REFERENCES estimates(id),
  target_type text NOT NULL CHECK (target_type IN ('service_ticket', 'project')),
  target_id uuid NOT NULL,
  created_at timestamptz DEFAULT NOW(),
  created_by uuid REFERENCES profiles(id),
  metadata jsonb DEFAULT '{}'::jsonb
);

ALTER TABLE estimate_conversions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view conversions"
  ON estimate_conversions FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can create conversions"
  ON estimate_conversions FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Create ticket_parts_planned table for planned parts from estimates
CREATE TABLE IF NOT EXISTS ticket_parts_planned (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  part_id uuid REFERENCES parts(id),
  description text NOT NULL,
  quantity numeric NOT NULL DEFAULT 1,
  unit_price numeric,
  unit_cost numeric,
  line_total numeric,
  notes text,
  source_line_id uuid REFERENCES estimate_line_items(id),
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

ALTER TABLE ticket_parts_planned ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view planned parts"
  ON ticket_parts_planned FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can manage planned parts"
  ON ticket_parts_planned FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_ticket_parts_planned_ticket ON ticket_parts_planned(ticket_id);
CREATE INDEX IF NOT EXISTS idx_ticket_parts_planned_part ON ticket_parts_planned(part_id);

-- Create ticket_labor_planned table for planned labor from estimates
CREATE TABLE IF NOT EXISTS ticket_labor_planned (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  description text NOT NULL,
  labor_hours numeric NOT NULL DEFAULT 0,
  labor_rate numeric,
  line_total numeric,
  notes text,
  source_line_id uuid REFERENCES estimate_line_items(id),
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

ALTER TABLE ticket_labor_planned ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view planned labor"
  ON ticket_labor_planned FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can manage planned labor"
  ON ticket_labor_planned FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_ticket_labor_planned_ticket ON ticket_labor_planned(ticket_id);

-- Create ticket_charges_planned table for misc/equipment charges from estimates
CREATE TABLE IF NOT EXISTS ticket_charges_planned (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  charge_type text NOT NULL DEFAULT 'other',
  description text NOT NULL,
  quantity numeric NOT NULL DEFAULT 1,
  unit_price numeric,
  line_total numeric,
  notes text,
  source_line_id uuid REFERENCES estimate_line_items(id),
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

ALTER TABLE ticket_charges_planned ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view planned charges"
  ON ticket_charges_planned FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can manage planned charges"
  ON ticket_charges_planned FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_ticket_charges_planned_ticket ON ticket_charges_planned(ticket_id);

-- Function to convert estimate to service ticket
CREATE OR REPLACE FUNCTION fn_convert_estimate_to_service_ticket(p_estimate_id uuid, p_created_by uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_estimate record;
  v_existing_conversion record;
  v_ticket_id uuid;
  v_ticket_number text;
  v_line record;
BEGIN
  SELECT * INTO v_estimate
  FROM estimates
  WHERE id = p_estimate_id;

  IF v_estimate IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Estimate not found');
  END IF;

  IF v_estimate.status != 'accepted' AND v_estimate.accepted_date IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Estimate must be accepted before conversion');
  END IF;

  SELECT * INTO v_existing_conversion
  FROM estimate_conversions
  WHERE estimate_id = p_estimate_id;

  IF v_existing_conversion IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_converted', true,
      'target_type', v_existing_conversion.target_type,
      'target_id', v_existing_conversion.target_id,
      'converted_at', v_existing_conversion.created_at
    );
  END IF;

  v_ticket_number := generate_svc_ticket_number();
  v_ticket_id := gen_random_uuid();

  INSERT INTO tickets (
    id,
    ticket_number,
    ticket_type,
    customer_id,
    site_id,
    title,
    description,
    status,
    priority,
    created_by,
    source_estimate_id,
    estimated_duration,
    billable
  ) VALUES (
    v_ticket_id,
    v_ticket_number,
    'service',
    v_estimate.customer_id,
    v_estimate.location_id,
    v_estimate.job_title,
    COALESCE(v_estimate.job_description, '') || 
      CASE WHEN v_estimate.notes IS NOT NULL THEN E'\n\nNotes: ' || v_estimate.notes ELSE '' END,
    'open',
    'medium',
    COALESCE(p_created_by, v_estimate.created_by),
    p_estimate_id,
    60,
    true
  );

  FOR v_line IN
    SELECT * FROM estimate_line_items
    WHERE estimate_id = p_estimate_id
    ORDER BY line_order
  LOOP
    IF v_line.item_type = 'parts' THEN
      INSERT INTO ticket_parts_planned (
        ticket_id, part_id, description, quantity, 
        unit_price, unit_cost, line_total, notes, source_line_id
      ) VALUES (
        v_ticket_id, v_line.part_id, v_line.description, v_line.quantity,
        v_line.unit_price, v_line.unit_cost, v_line.line_total, v_line.notes, v_line.id
      );
    ELSIF v_line.item_type = 'labor' THEN
      INSERT INTO ticket_labor_planned (
        ticket_id, description, labor_hours, labor_rate, line_total, notes, source_line_id
      ) VALUES (
        v_ticket_id, v_line.description, COALESCE(v_line.labor_hours, 0), 
        v_line.labor_rate, v_line.line_total, v_line.notes, v_line.id
      );
    ELSIF v_line.item_type IN ('equipment', 'other') THEN
      INSERT INTO ticket_charges_planned (
        ticket_id, charge_type, description, quantity, unit_price, line_total, notes, source_line_id
      ) VALUES (
        v_ticket_id, v_line.item_type::text, v_line.description, v_line.quantity,
        v_line.unit_price, v_line.line_total, v_line.notes, v_line.id
      );
    END IF;
  END LOOP;

  INSERT INTO estimate_conversions (
    estimate_id, target_type, target_id, created_by, metadata
  ) VALUES (
    p_estimate_id, 'service_ticket', v_ticket_id, p_created_by,
    jsonb_build_object(
      'ticket_number', v_ticket_number,
      'estimate_number', v_estimate.estimate_number,
      'estimate_total', v_estimate.total_amount
    )
  );

  UPDATE estimates
  SET converted_to_ticket_id = v_ticket_id,
      conversion_date = NOW(),
      updated_at = NOW()
  WHERE id = p_estimate_id;

  RETURN jsonb_build_object(
    'success', true,
    'target_type', 'service_ticket',
    'target_id', v_ticket_id,
    'ticket_number', v_ticket_number,
    'converted_at', NOW()
  );
END;
$$;

-- Function to convert estimate to project
CREATE OR REPLACE FUNCTION fn_convert_estimate_to_project(p_estimate_id uuid, p_created_by uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_estimate record;
  v_existing_conversion record;
  v_project_id uuid;
  v_project_number text;
  v_ticket_id uuid;
  v_ticket_number text;
  v_labor_budget numeric := 0;
  v_parts_budget numeric := 0;
  v_equipment_budget numeric := 0;
  v_line record;
BEGIN
  SELECT * INTO v_estimate
  FROM estimates
  WHERE id = p_estimate_id;

  IF v_estimate IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Estimate not found');
  END IF;

  IF v_estimate.status != 'accepted' AND v_estimate.accepted_date IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Estimate must be accepted before conversion');
  END IF;

  SELECT * INTO v_existing_conversion
  FROM estimate_conversions
  WHERE estimate_id = p_estimate_id;

  IF v_existing_conversion IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_converted', true,
      'target_type', v_existing_conversion.target_type,
      'target_id', v_existing_conversion.target_id,
      'converted_at', v_existing_conversion.created_at
    );
  END IF;

  SELECT 
    COALESCE(SUM(CASE WHEN item_type = 'labor' THEN line_total ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN item_type = 'parts' THEN line_total ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN item_type = 'equipment' THEN line_total ELSE 0 END), 0)
  INTO v_labor_budget, v_parts_budget, v_equipment_budget
  FROM estimate_line_items
  WHERE estimate_id = p_estimate_id;

  v_project_number := generate_project_number();
  v_project_id := gen_random_uuid();

  INSERT INTO projects (
    id,
    project_number,
    name,
    description,
    customer_id,
    status,
    priority,
    project_type,
    start_date,
    budget,
    budget_labor,
    budget_parts,
    budget_equipment,
    location,
    created_by,
    source_estimate_id
  ) VALUES (
    v_project_id,
    v_project_number,
    v_estimate.job_title,
    COALESCE(v_estimate.job_description, '') || 
      CASE WHEN v_estimate.notes IS NOT NULL THEN E'\n\nNotes: ' || v_estimate.notes ELSE '' END,
    v_estimate.customer_id,
    'planning',
    'medium',
    'standard',
    CURRENT_DATE,
    v_estimate.total_amount,
    v_labor_budget,
    v_parts_budget,
    v_equipment_budget,
    v_estimate.site_location,
    COALESCE(p_created_by, v_estimate.created_by),
    p_estimate_id
  );

  v_ticket_number := generate_prj_ticket_number(v_project_id);
  v_ticket_id := gen_random_uuid();

  INSERT INTO tickets (
    id,
    ticket_number,
    ticket_type,
    customer_id,
    site_id,
    project_id,
    title,
    description,
    status,
    priority,
    created_by,
    source_estimate_id,
    estimated_duration,
    billable
  ) VALUES (
    v_ticket_id,
    v_ticket_number,
    'project',
    v_estimate.customer_id,
    v_estimate.location_id,
    v_project_id,
    'Initial Work Order - ' || v_estimate.job_title,
    'Initial work order created from estimate ' || v_estimate.estimate_number,
    'open',
    'medium',
    COALESCE(p_created_by, v_estimate.created_by),
    p_estimate_id,
    60,
    true
  );

  FOR v_line IN
    SELECT * FROM estimate_line_items
    WHERE estimate_id = p_estimate_id
    ORDER BY line_order
  LOOP
    IF v_line.item_type = 'parts' THEN
      INSERT INTO ticket_parts_planned (
        ticket_id, part_id, description, quantity, 
        unit_price, unit_cost, line_total, notes, source_line_id
      ) VALUES (
        v_ticket_id, v_line.part_id, v_line.description, v_line.quantity,
        v_line.unit_price, v_line.unit_cost, v_line.line_total, v_line.notes, v_line.id
      );
    ELSIF v_line.item_type = 'labor' THEN
      INSERT INTO ticket_labor_planned (
        ticket_id, description, labor_hours, labor_rate, line_total, notes, source_line_id
      ) VALUES (
        v_ticket_id, v_line.description, COALESCE(v_line.labor_hours, 0), 
        v_line.labor_rate, v_line.line_total, v_line.notes, v_line.id
      );
    ELSIF v_line.item_type IN ('equipment', 'other') THEN
      INSERT INTO ticket_charges_planned (
        ticket_id, charge_type, description, quantity, unit_price, line_total, notes, source_line_id
      ) VALUES (
        v_ticket_id, v_line.item_type::text, v_line.description, v_line.quantity,
        v_line.unit_price, v_line.line_total, v_line.notes, v_line.id
      );
    END IF;
  END LOOP;

  INSERT INTO estimate_conversions (
    estimate_id, target_type, target_id, created_by, metadata
  ) VALUES (
    p_estimate_id, 'project', v_project_id, p_created_by,
    jsonb_build_object(
      'project_number', v_project_number,
      'initial_ticket_id', v_ticket_id,
      'initial_ticket_number', v_ticket_number,
      'estimate_number', v_estimate.estimate_number,
      'estimate_total', v_estimate.total_amount
    )
  );

  UPDATE estimates
  SET converted_to_project_id = v_project_id,
      conversion_date = NOW(),
      updated_at = NOW()
  WHERE id = p_estimate_id;

  RETURN jsonb_build_object(
    'success', true,
    'target_type', 'project',
    'target_id', v_project_id,
    'project_number', v_project_number,
    'initial_ticket_id', v_ticket_id,
    'initial_ticket_number', v_ticket_number,
    'converted_at', NOW()
  );
END;
$$;

-- Create view to show estimate margin calculation
CREATE OR REPLACE VIEW vw_estimate_margin AS
SELECT 
  e.id as estimate_id,
  e.estimate_number,
  e.status,
  e.subtotal as revenue,
  COALESCE(SUM(eli.ext_cost), 0) as total_cost,
  e.subtotal - COALESCE(SUM(eli.ext_cost), 0) as gross_margin,
  CASE 
    WHEN e.subtotal > 0 THEN 
      ROUND(((e.subtotal - COALESCE(SUM(eli.ext_cost), 0)) / e.subtotal) * 100, 2)
    ELSE 0
  END as margin_percent
FROM estimates e
LEFT JOIN estimate_line_items eli ON eli.estimate_id = e.id AND eli.item_type = 'parts'
GROUP BY e.id, e.estimate_number, e.status, e.subtotal;

-- Create index for faster cost lookups
CREATE INDEX IF NOT EXISTS idx_estimate_line_items_part_id ON estimate_line_items(part_id) WHERE part_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_estimate_conversions_target ON estimate_conversions(target_type, target_id);
