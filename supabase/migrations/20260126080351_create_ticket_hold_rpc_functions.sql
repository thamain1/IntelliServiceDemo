/*
  # Ticket Hold RPC Functions

  ## Overview
  Atomic functions for managing ticket holds:
  - `fn_ticket_hold_for_parts()` - Stop timer, create hold, request parts
  - `fn_ticket_report_issue()` - Stop timer, create hold, report issue
  - `fn_ticket_resume()` - Resume ticket from hold

  ## Functions

  ### fn_ticket_hold_for_parts
  Atomically:
  1. Validates tech has permission
  2. Ends active time entry for this tech/ticket
  3. Creates hold record
  4. Creates parts request with line items
  5. Updates ticket status and flags
  6. Returns hold and request IDs

  ### fn_ticket_report_issue
  Atomically:
  1. Validates tech has permission
  2. Ends active time entry for this tech/ticket
  3. Creates hold record
  4. Creates issue report
  5. Updates ticket status and flags
  6. Returns hold and report IDs

  ### fn_ticket_resume
  Atomically:
  1. Resolves active hold
  2. Updates ticket flags
  3. Returns success

  ## Security
  Functions use SECURITY DEFINER but validate permissions internally
*/

-- =====================================================
-- FUNCTION: Hold Ticket for Parts
-- =====================================================

CREATE OR REPLACE FUNCTION fn_ticket_hold_for_parts(
  p_ticket_id uuid,
  p_urgency text,
  p_notes text,
  p_summary text,
  p_parts jsonb  -- Array of {part_id, quantity, notes, preferred_source_location_id}
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_user_role text;
  v_hold_id uuid;
  v_request_id uuid;
  v_part jsonb;
  v_active_time_entry_id uuid;
BEGIN
  -- Get current user
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Get user role
  SELECT role INTO v_user_role
  FROM profiles
  WHERE id = v_user_id;

  -- Validate role
  IF v_user_role NOT IN ('admin', 'dispatcher', 'technician') THEN
    RAISE EXCEPTION 'Insufficient permissions';
  END IF;

  -- Validate ticket exists and is assigned (if tech)
  IF v_user_role = 'technician' THEN
    IF NOT EXISTS (
      SELECT 1 FROM tickets
      WHERE id = p_ticket_id
      AND assigned_to = v_user_id
    ) THEN
      RAISE EXCEPTION 'Ticket not found or not assigned to you';
    END IF;
  END IF;

  -- Check if ticket already has an active hold
  IF EXISTS (
    SELECT 1 FROM tickets
    WHERE id = p_ticket_id
    AND hold_active = true
  ) THEN
    RAISE EXCEPTION 'Ticket already has an active hold';
  END IF;

  -- Step 1: End any active time entry for this tech/ticket
  SELECT id INTO v_active_time_entry_id
  FROM ticket_time_logs
  WHERE ticket_id = p_ticket_id
  AND user_id = v_user_id
  AND end_time IS NULL
  AND status = 'in_progress'
  ORDER BY start_time DESC
  LIMIT 1;

  IF v_active_time_entry_id IS NOT NULL THEN
    UPDATE ticket_time_logs
    SET 
      end_time = now(),
      status = 'completed',
      duration_minutes = EXTRACT(EPOCH FROM (now() - start_time)) / 60
    WHERE id = v_active_time_entry_id;
  END IF;

  -- Step 2: Create hold record
  INSERT INTO ticket_holds (
    ticket_id,
    hold_type,
    status,
    summary,
    created_by
  ) VALUES (
    p_ticket_id,
    'parts',
    'active',
    COALESCE(p_summary, 'Waiting for parts'),
    v_user_id
  )
  RETURNING id INTO v_hold_id;

  -- Step 3: Create parts request
  INSERT INTO ticket_parts_requests (
    ticket_id,
    hold_id,
    urgency,
    notes,
    status,
    created_by
  ) VALUES (
    p_ticket_id,
    v_hold_id,
    p_urgency,
    p_notes,
    'open',
    v_user_id
  )
  RETURNING id INTO v_request_id;

  -- Step 4: Create request line items
  FOR v_part IN SELECT * FROM jsonb_array_elements(p_parts)
  LOOP
    INSERT INTO ticket_parts_request_lines (
      request_id,
      part_id,
      quantity_requested,
      notes,
      preferred_source_location_id
    ) VALUES (
      v_request_id,
      (v_part->>'part_id')::uuid,
      (v_part->>'quantity')::numeric,
      v_part->>'notes',
      (v_part->>'preferred_source_location_id')::uuid
    );
  END LOOP;

  -- Step 5: Update ticket flags
  UPDATE tickets
  SET 
    hold_active = true,
    hold_type = 'parts',
    revisit_required = true
  WHERE id = p_ticket_id;

  -- Return results
  RETURN jsonb_build_object(
    'success', true,
    'hold_id', v_hold_id,
    'request_id', v_request_id,
    'time_entry_stopped', v_active_time_entry_id IS NOT NULL
  );
END;
$$;

COMMENT ON FUNCTION fn_ticket_hold_for_parts IS 'Atomically hold ticket and request parts - stops timer, creates hold and request';

-- =====================================================
-- FUNCTION: Report Ticket Issue
-- =====================================================

CREATE OR REPLACE FUNCTION fn_ticket_report_issue(
  p_ticket_id uuid,
  p_category text,
  p_severity text,
  p_description text,
  p_summary text,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_user_role text;
  v_hold_id uuid;
  v_report_id uuid;
  v_active_time_entry_id uuid;
BEGIN
  -- Get current user
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Get user role
  SELECT role INTO v_user_role
  FROM profiles
  WHERE id = v_user_id;

  -- Validate role
  IF v_user_role NOT IN ('admin', 'dispatcher', 'technician') THEN
    RAISE EXCEPTION 'Insufficient permissions';
  END IF;

  -- Validate ticket exists and is assigned (if tech)
  IF v_user_role = 'technician' THEN
    IF NOT EXISTS (
      SELECT 1 FROM tickets
      WHERE id = p_ticket_id
      AND assigned_to = v_user_id
    ) THEN
      RAISE EXCEPTION 'Ticket not found or not assigned to you';
    END IF;
  END IF;

  -- Check if ticket already has an active hold
  IF EXISTS (
    SELECT 1 FROM tickets
    WHERE id = p_ticket_id
    AND hold_active = true
  ) THEN
    RAISE EXCEPTION 'Ticket already has an active hold';
  END IF;

  -- Step 1: End any active time entry for this tech/ticket
  SELECT id INTO v_active_time_entry_id
  FROM ticket_time_logs
  WHERE ticket_id = p_ticket_id
  AND user_id = v_user_id
  AND end_time IS NULL
  AND status = 'in_progress'
  ORDER BY start_time DESC
  LIMIT 1;

  IF v_active_time_entry_id IS NOT NULL THEN
    UPDATE ticket_time_logs
    SET 
      end_time = now(),
      status = 'completed',
      duration_minutes = EXTRACT(EPOCH FROM (now() - start_time)) / 60
    WHERE id = v_active_time_entry_id;
  END IF;

  -- Step 2: Create hold record
  INSERT INTO ticket_holds (
    ticket_id,
    hold_type,
    status,
    summary,
    created_by
  ) VALUES (
    p_ticket_id,
    'issue',
    'active',
    COALESCE(p_summary, 'Issue reported - ' || p_category),
    v_user_id
  )
  RETURNING id INTO v_hold_id;

  -- Step 3: Create issue report
  INSERT INTO ticket_issue_reports (
    ticket_id,
    hold_id,
    category,
    severity,
    description,
    metadata,
    status,
    created_by
  ) VALUES (
    p_ticket_id,
    v_hold_id,
    p_category,
    p_severity,
    p_description,
    p_metadata,
    'open',
    v_user_id
  )
  RETURNING id INTO v_report_id;

  -- Step 4: Update ticket flags
  UPDATE tickets
  SET 
    hold_active = true,
    hold_type = 'issue',
    revisit_required = true
  WHERE id = p_ticket_id;

  -- Return results
  RETURN jsonb_build_object(
    'success', true,
    'hold_id', v_hold_id,
    'report_id', v_report_id,
    'time_entry_stopped', v_active_time_entry_id IS NOT NULL
  );
END;
$$;

COMMENT ON FUNCTION fn_ticket_report_issue IS 'Atomically hold ticket and report issue - stops timer, creates hold and issue report';

-- =====================================================
-- FUNCTION: Resume Ticket from Hold
-- =====================================================

CREATE OR REPLACE FUNCTION fn_ticket_resume(
  p_ticket_id uuid,
  p_resolution_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_user_role text;
  v_hold_id uuid;
  v_hold_type text;
BEGIN
  -- Get current user
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Get user role
  SELECT role INTO v_user_role
  FROM profiles
  WHERE id = v_user_id;

  -- Validate role (only admin/dispatcher can resume)
  IF v_user_role NOT IN ('admin', 'dispatcher') THEN
    RAISE EXCEPTION 'Only admins and dispatchers can resume tickets from hold';
  END IF;

  -- Get active hold
  SELECT id, hold_type INTO v_hold_id, v_hold_type
  FROM ticket_holds
  WHERE ticket_id = p_ticket_id
  AND status = 'active'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_hold_id IS NULL THEN
    RAISE EXCEPTION 'No active hold found for this ticket';
  END IF;

  -- Resolve the hold
  UPDATE ticket_holds
  SET 
    status = 'resolved',
    resolved_at = now(),
    resolved_by = v_user_id
  WHERE id = v_hold_id;

  -- Update associated records based on hold type
  IF v_hold_type = 'parts' THEN
    -- Update parts request (if not already fulfilled)
    UPDATE ticket_parts_requests
    SET 
      status = 'fulfilled',
      fulfilled_at = now(),
      fulfilled_by = v_user_id
    WHERE hold_id = v_hold_id
    AND status = 'open';
  ELSIF v_hold_type = 'issue' THEN
    -- Update issue report (if not already resolved)
    UPDATE ticket_issue_reports
    SET 
      status = 'resolved',
      resolved_at = now(),
      resolved_by = v_user_id,
      resolution_notes = p_resolution_notes
    WHERE hold_id = v_hold_id
    AND status IN ('open', 'investigating');
  END IF;

  -- Clear ticket flags
  UPDATE tickets
  SET 
    hold_active = false,
    hold_type = NULL,
    revisit_required = false
  WHERE id = p_ticket_id;

  -- Return results
  RETURN jsonb_build_object(
    'success', true,
    'hold_id', v_hold_id,
    'hold_type', v_hold_type
  );
END;
$$;

COMMENT ON FUNCTION fn_ticket_resume IS 'Resume ticket from hold - resolves hold and clears ticket flags';

-- =====================================================
-- GRANT EXECUTE PERMISSIONS
-- =====================================================

GRANT EXECUTE ON FUNCTION fn_ticket_hold_for_parts TO authenticated;
GRANT EXECUTE ON FUNCTION fn_ticket_report_issue TO authenticated;
GRANT EXECUTE ON FUNCTION fn_ticket_resume TO authenticated;
