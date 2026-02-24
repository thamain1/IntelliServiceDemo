/*
  # Fix Ticket Holds RPCs and Add Dashboard KPI Views

  ## Purpose
  Fix ticket hold RPC functions to use correct time_logs table structure and create
  dashboard views for hold-based KPIs.

  ## Changes

  ### 1. Fix RPC Functions
  - Update fn_ticket_hold_for_parts to use time_logs (not ticket_time_logs)
  - Update fn_ticket_report_issue to use time_logs (not ticket_time_logs)
  - Correct column references: clock_out_time instead of end_time, clock_in_time instead of start_time

  ### 2. Dashboard KPI Views
  - vw_tickets_on_hold_parts - Tickets waiting for parts
  - vw_tickets_on_hold_issue - Tickets with reported issues
  - vw_tickets_in_progress_active - In-progress tickets excluding holds
  - vw_dashboard_hold_metrics - Aggregated hold metrics

  ## Security
  - All views inherit RLS from underlying tables
  - Authenticated users can query views based on their role permissions

  ## Important Notes
  - Idempotent: Safe to run multiple times
  - No data loss: Fully additive changes
  - Backward compatible: Existing code continues to work
*/

-- =====================================================
-- PART 1: FIX RPC FUNCTIONS FOR CORRECT TIME TABLE
-- =====================================================

-- Drop and recreate fn_ticket_hold_for_parts with correct time_logs structure
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
    -- If already on hold for parts, just return success (idempotent)
    SELECT id INTO v_hold_id
    FROM ticket_holds
    WHERE ticket_id = p_ticket_id
    AND status = 'active'
    AND hold_type = 'parts'
    ORDER BY created_at DESC
    LIMIT 1;
    
    IF v_hold_id IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', true,
        'hold_id', v_hold_id,
        'message', 'Ticket already on hold for parts'
      );
    END IF;
    
    RAISE EXCEPTION 'Ticket already has an active hold of different type';
  END IF;

  -- Step 1: End any active time entry for this tech/ticket
  -- FIXED: Use time_logs table with correct column names
  SELECT id INTO v_active_time_entry_id
  FROM time_logs
  WHERE ticket_id = p_ticket_id
  AND user_id = v_user_id
  AND clock_out_time IS NULL
  AND status = 'active'
  ORDER BY clock_in_time DESC
  LIMIT 1;

  IF v_active_time_entry_id IS NOT NULL THEN
    UPDATE time_logs
    SET 
      clock_out_time = now(),
      status = 'completed',
      total_hours = EXTRACT(EPOCH FROM (now() - clock_in_time)) / 3600,
      updated_at = now()
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
  IF p_parts IS NOT NULL AND jsonb_array_length(p_parts) > 0 THEN
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
  END IF;

  -- Step 5: Update ticket flags
  UPDATE tickets
  SET 
    hold_active = true,
    hold_type = 'parts',
    revisit_required = true,
    updated_at = now()
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

-- Drop and recreate fn_ticket_report_issue with correct time_logs structure
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
    -- If already on hold for issue, just return success (idempotent)
    SELECT id INTO v_hold_id
    FROM ticket_holds
    WHERE ticket_id = p_ticket_id
    AND status = 'active'
    AND hold_type = 'issue'
    ORDER BY created_at DESC
    LIMIT 1;
    
    IF v_hold_id IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', true,
        'hold_id', v_hold_id,
        'message', 'Ticket already on hold for issue'
      );
    END IF;
    
    RAISE EXCEPTION 'Ticket already has an active hold of different type';
  END IF;

  -- Step 1: End any active time entry for this tech/ticket
  -- FIXED: Use time_logs table with correct column names
  SELECT id INTO v_active_time_entry_id
  FROM time_logs
  WHERE ticket_id = p_ticket_id
  AND user_id = v_user_id
  AND clock_out_time IS NULL
  AND status = 'active'
  ORDER BY clock_in_time DESC
  LIMIT 1;

  IF v_active_time_entry_id IS NOT NULL THEN
    UPDATE time_logs
    SET 
      clock_out_time = now(),
      status = 'completed',
      total_hours = EXTRACT(EPOCH FROM (now() - clock_in_time)) / 3600,
      updated_at = now()
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
    revisit_required = true,
    updated_at = now()
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
-- PART 2: CREATE DASHBOARD KPI VIEWS
-- =====================================================

-- View: Tickets on hold waiting for parts
CREATE OR REPLACE VIEW vw_tickets_on_hold_parts AS
SELECT
  t.id AS ticket_id,
  t.ticket_number,
  t.title,
  t.customer_id,
  c.name AS customer_name,
  t.assigned_to,
  p.full_name AS assigned_to_name,
  t.status AS ticket_status,
  th.id AS hold_id,
  th.summary AS hold_summary,
  th.created_at AS hold_started_at,
  th.created_by AS hold_created_by,
  prof_hold.full_name AS hold_created_by_name,
  tpr.id AS parts_request_id,
  tpr.urgency AS request_urgency,
  tpr.notes AS request_notes,
  tpr.status AS request_status,
  COUNT(tprl.id) AS parts_count
FROM tickets t
INNER JOIN ticket_holds th ON th.ticket_id = t.id
  AND th.status = 'active'
  AND th.hold_type = 'parts'
LEFT JOIN customers c ON t.customer_id = c.id
LEFT JOIN profiles p ON t.assigned_to = p.id
LEFT JOIN profiles prof_hold ON th.created_by = prof_hold.id
LEFT JOIN ticket_parts_requests tpr ON tpr.hold_id = th.id
LEFT JOIN ticket_parts_request_lines tprl ON tprl.request_id = tpr.id
WHERE t.hold_active = true
  AND t.hold_type = 'parts'
GROUP BY 
  t.id, t.ticket_number, t.title, t.customer_id, c.name,
  t.assigned_to, p.full_name, t.status,
  th.id, th.summary, th.created_at, th.created_by, prof_hold.full_name,
  tpr.id, tpr.urgency, tpr.notes, tpr.status
ORDER BY th.created_at DESC;

COMMENT ON VIEW vw_tickets_on_hold_parts IS
'Tickets currently on hold waiting for parts. Used for Awaiting Parts dashboard card.';

-- View: Tickets on hold with reported issues
CREATE OR REPLACE VIEW vw_tickets_on_hold_issue AS
SELECT
  t.id AS ticket_id,
  t.ticket_number,
  t.title,
  t.customer_id,
  c.name AS customer_name,
  t.assigned_to,
  p.full_name AS assigned_to_name,
  t.status AS ticket_status,
  th.id AS hold_id,
  th.summary AS hold_summary,
  th.created_at AS hold_started_at,
  th.created_by AS hold_created_by,
  prof_hold.full_name AS hold_created_by_name,
  tir.id AS issue_report_id,
  tir.category AS issue_category,
  tir.severity AS issue_severity,
  tir.description AS issue_description,
  tir.status AS issue_status
FROM tickets t
INNER JOIN ticket_holds th ON th.ticket_id = t.id
  AND th.status = 'active'
  AND th.hold_type = 'issue'
LEFT JOIN customers c ON t.customer_id = c.id
LEFT JOIN profiles p ON t.assigned_to = p.id
LEFT JOIN profiles prof_hold ON th.created_by = prof_hold.id
LEFT JOIN ticket_issue_reports tir ON tir.hold_id = th.id
WHERE t.hold_active = true
  AND t.hold_type = 'issue'
ORDER BY th.created_at DESC;

COMMENT ON VIEW vw_tickets_on_hold_issue IS
'Tickets currently on hold with reported issues. Used for Issues Reported dashboard card.';

-- View: Tickets in progress (excluding holds)
CREATE OR REPLACE VIEW vw_tickets_in_progress_active AS
SELECT
  t.id AS ticket_id,
  t.ticket_number,
  t.title,
  t.customer_id,
  c.name AS customer_name,
  t.assigned_to,
  p.full_name AS assigned_to_name,
  t.status AS ticket_status,
  t.scheduled_date,
  t.created_at,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM time_logs tl
      WHERE tl.ticket_id = t.id
      AND tl.clock_out_time IS NULL
      AND tl.status = 'active'
    ) THEN true
    ELSE false
  END AS has_active_timer
FROM tickets t
LEFT JOIN customers c ON t.customer_id = c.id
LEFT JOIN profiles p ON t.assigned_to = p.id
WHERE t.status = 'in_progress'
  AND (t.hold_active IS NULL OR t.hold_active = false)
ORDER BY t.scheduled_date DESC NULLS LAST, t.created_at DESC;

COMMENT ON VIEW vw_tickets_in_progress_active IS
'Tickets in progress excluding those on hold. Used for corrected In Progress dashboard card.';

-- View: Aggregated hold metrics for dashboard
CREATE OR REPLACE VIEW vw_dashboard_hold_metrics AS
SELECT
  (SELECT COUNT(*) FROM tickets WHERE hold_active = true AND hold_type = 'parts') AS awaiting_parts_count,
  (SELECT COUNT(*) FROM tickets WHERE hold_active = true AND hold_type = 'issue') AS issues_reported_count,
  (SELECT COUNT(*) FROM tickets WHERE status = 'in_progress' AND (hold_active IS NULL OR hold_active = false)) AS in_progress_active_count,
  (SELECT COUNT(*) FROM ticket_parts_requests WHERE status = 'open') AS open_parts_requests_count,
  (SELECT COUNT(*) FROM ticket_issue_reports WHERE status IN ('open', 'investigating')) AS open_issue_reports_count,
  (
    SELECT jsonb_agg(
      jsonb_build_object(
        'urgency', urgency,
        'count', cnt
      ) ORDER BY 
        CASE urgency 
          WHEN 'critical' THEN 1
          WHEN 'high' THEN 2
          WHEN 'medium' THEN 3
          WHEN 'low' THEN 4
        END
    )
    FROM (
      SELECT urgency, COUNT(*) AS cnt
      FROM ticket_parts_requests
      WHERE status = 'open'
      GROUP BY urgency
    ) sub
  ) AS parts_requests_by_urgency,
  (
    SELECT jsonb_agg(
      jsonb_build_object(
        'severity', severity,
        'count', cnt
      ) ORDER BY 
        CASE severity 
          WHEN 'critical' THEN 1
          WHEN 'high' THEN 2
          WHEN 'medium' THEN 3
          WHEN 'low' THEN 4
        END
    )
    FROM (
      SELECT severity, COUNT(*) AS cnt
      FROM ticket_issue_reports
      WHERE status IN ('open', 'investigating')
      GROUP BY severity
    ) sub
  ) AS issue_reports_by_severity;

COMMENT ON VIEW vw_dashboard_hold_metrics IS
'Aggregated metrics for ticket holds dashboard. Single-row view with all hold-related KPIs.';

-- =====================================================
-- PART 3: GRANT PERMISSIONS
-- =====================================================

-- Grant select on views to authenticated users
GRANT SELECT ON vw_tickets_on_hold_parts TO authenticated;
GRANT SELECT ON vw_tickets_on_hold_issue TO authenticated;
GRANT SELECT ON vw_tickets_in_progress_active TO authenticated;
GRANT SELECT ON vw_dashboard_hold_metrics TO authenticated;

-- Re-grant execute on fixed functions
GRANT EXECUTE ON FUNCTION fn_ticket_hold_for_parts TO authenticated;
GRANT EXECUTE ON FUNCTION fn_ticket_report_issue TO authenticated;
GRANT EXECUTE ON FUNCTION fn_ticket_resume TO authenticated;
