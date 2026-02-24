/*
  # Fix Estimate Conversion Ticket Type Enum

  ## Issue
  The fn_convert_estimate_to_service_ticket and fn_convert_estimate_to_project functions
  are using incorrect enum values for ticket_type.
  
  - Currently using: 'service' and 'project'
  - Should be using: 'SVC' and 'PRJ'

  ## Fix
  Update both conversion functions to use correct ticket_type enum values.

  ## Changes
  - fn_convert_estimate_to_service_ticket: 'service' → 'SVC'
  - fn_convert_estimate_to_project: 'project' → 'PRJ'
*/

-- Fix service ticket conversion function
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
    'SVC',  -- FIXED: was 'service'
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

-- Fix project conversion function
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
    'PRJ',  -- FIXED: was 'project'
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

COMMENT ON FUNCTION fn_convert_estimate_to_service_ticket(uuid, uuid) IS 'Converts accepted estimate to service ticket (SVC type) with planned parts/labor/charges';
COMMENT ON FUNCTION fn_convert_estimate_to_project(uuid, uuid) IS 'Converts accepted estimate to project with initial work order (PRJ type) and planned parts/labor/charges';
