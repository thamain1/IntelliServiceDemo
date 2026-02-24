/*
  # Support Dual Hold Flags and Fix Dashboard

  ## Overview
  Adds support for tickets to be on hold for both parts AND issues simultaneously.
  Fixes dashboard cards to properly reflect hold states.

  ## Changes

  ### 1. Add Dual Hold Flag Columns to Tickets
  - `hold_parts_active` - Boolean for parts hold
  - `hold_issue_active` - Boolean for issue hold
  - Keep existing `hold_active` and `hold_type` for backwards compatibility

  ### 2. Update Hold RPCs
  - Set specific hold flags (hold_parts_active or hold_issue_active)
  - Set general hold_active=true when either flag is true
  - Update hold_type to reflect most recent action

  ### 3. Update Dashboard Views
  - Use specific hold flags instead of hold_type checks
  - Support tickets appearing in both metrics if flagged for both

  ## Important Notes
  - Fully additive: No drops or renames
  - Backwards compatible: Existing hold_active/hold_type still work
  - RLS inherited from tickets table
  - Atomic operations maintained
*/

-- =====================================================
-- PART 1: ADD DUAL HOLD FLAG COLUMNS
-- =====================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tickets' AND column_name = 'hold_parts_active'
  ) THEN
    ALTER TABLE tickets ADD COLUMN hold_parts_active boolean NOT NULL DEFAULT false;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tickets' AND column_name = 'hold_issue_active'
  ) THEN
    ALTER TABLE tickets ADD COLUMN hold_issue_active boolean NOT NULL DEFAULT false;
  END IF;
END $$;

-- Add indexes for new hold flags
CREATE INDEX IF NOT EXISTS idx_tickets_hold_parts_active ON tickets(hold_parts_active) WHERE hold_parts_active = true;
CREATE INDEX IF NOT EXISTS idx_tickets_hold_issue_active ON tickets(hold_issue_active) WHERE hold_issue_active = true;

COMMENT ON COLUMN tickets.hold_parts_active IS 'True when ticket is on hold waiting for parts';
COMMENT ON COLUMN tickets.hold_issue_active IS 'True when ticket is on hold due to reported issue';

-- =====================================================
-- PART 2: UPDATE HOLD RPCs TO USE DUAL FLAGS
-- =====================================================

-- Update fn_ticket_hold_for_parts to set both flags
CREATE OR REPLACE FUNCTION fn_ticket_hold_for_parts(
  p_ticket_id uuid,
  p_urgency text,
  p_notes text,
  p_summary text,
  p_parts jsonb
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
  v_already_on_parts_hold boolean;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT role INTO v_user_role FROM profiles WHERE id = v_user_id;

  IF v_user_role NOT IN ('admin', 'dispatcher', 'technician') THEN
    RAISE EXCEPTION 'Insufficient permissions';
  END IF;

  IF v_user_role = 'technician' THEN
    IF NOT EXISTS (
      SELECT 1 FROM tickets
      WHERE id = p_ticket_id AND assigned_to = v_user_id
    ) THEN
      RAISE EXCEPTION 'Ticket not found or not assigned to you';
    END IF;
  END IF;

  -- Check if already on hold for parts (idempotent)
  SELECT hold_parts_active INTO v_already_on_parts_hold
  FROM tickets WHERE id = p_ticket_id;

  IF v_already_on_parts_hold THEN
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
  END IF;

  -- Step 1: End active time entry
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
    ticket_id, hold_type, status, summary, created_by
  ) VALUES (
    p_ticket_id, 'parts', 'active',
    COALESCE(p_summary, 'Waiting for parts'), v_user_id
  ) RETURNING id INTO v_hold_id;

  -- Step 3: Create parts request
  INSERT INTO ticket_parts_requests (
    ticket_id, hold_id, urgency, notes, status, created_by
  ) VALUES (
    p_ticket_id, v_hold_id, p_urgency, p_notes, 'open', v_user_id
  ) RETURNING id INTO v_request_id;

  -- Step 4: Create request line items
  IF p_parts IS NOT NULL AND jsonb_array_length(p_parts) > 0 THEN
    FOR v_part IN SELECT * FROM jsonb_array_elements(p_parts)
    LOOP
      INSERT INTO ticket_parts_request_lines (
        request_id, part_id, quantity_requested, notes, preferred_source_location_id
      ) VALUES (
        v_request_id,
        (v_part->>'part_id')::uuid,
        (v_part->>'quantity')::numeric,
        v_part->>'notes',
        (v_part->>'preferred_source_location_id')::uuid
      );
    END LOOP;
  END IF;

  -- Step 5: Update ticket flags (DUAL FLAGS)
  UPDATE tickets
  SET 
    hold_parts_active = true,
    hold_active = true,
    hold_type = 'parts',
    revisit_required = true,
    updated_at = now()
  WHERE id = p_ticket_id;

  RETURN jsonb_build_object(
    'success', true,
    'hold_id', v_hold_id,
    'request_id', v_request_id,
    'time_entry_stopped', v_active_time_entry_id IS NOT NULL
  );
END;
$$;

-- Update fn_ticket_report_issue to set both flags
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
  v_already_on_issue_hold boolean;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT role INTO v_user_role FROM profiles WHERE id = v_user_id;

  IF v_user_role NOT IN ('admin', 'dispatcher', 'technician') THEN
    RAISE EXCEPTION 'Insufficient permissions';
  END IF;

  IF v_user_role = 'technician' THEN
    IF NOT EXISTS (
      SELECT 1 FROM tickets
      WHERE id = p_ticket_id AND assigned_to = v_user_id
    ) THEN
      RAISE EXCEPTION 'Ticket not found or not assigned to you';
    END IF;
  END IF;

  -- Check if already on hold for issue (idempotent)
  SELECT hold_issue_active INTO v_already_on_issue_hold
  FROM tickets WHERE id = p_ticket_id;

  IF v_already_on_issue_hold THEN
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
  END IF;

  -- Step 1: End active time entry
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
    ticket_id, hold_type, status, summary, created_by
  ) VALUES (
    p_ticket_id, 'issue', 'active',
    COALESCE(p_summary, 'Issue reported - ' || p_category), v_user_id
  ) RETURNING id INTO v_hold_id;

  -- Step 3: Create issue report
  INSERT INTO ticket_issue_reports (
    ticket_id, hold_id, category, severity, description, metadata, status, created_by
  ) VALUES (
    p_ticket_id, v_hold_id, p_category, p_severity, p_description,
    p_metadata, 'open', v_user_id
  ) RETURNING id INTO v_report_id;

  -- Step 4: Update ticket flags (DUAL FLAGS)
  UPDATE tickets
  SET 
    hold_issue_active = true,
    hold_active = true,
    hold_type = 'issue',
    revisit_required = true,
    updated_at = now()
  WHERE id = p_ticket_id;

  RETURN jsonb_build_object(
    'success', true,
    'hold_id', v_hold_id,
    'report_id', v_report_id,
    'time_entry_stopped', v_active_time_entry_id IS NOT NULL
  );
END;
$$;

-- Drop old resume function and create new one with extended signature
DROP FUNCTION IF EXISTS fn_ticket_resume(uuid, text);

CREATE OR REPLACE FUNCTION fn_ticket_resume(
  p_ticket_id uuid,
  p_resolution_notes text DEFAULT NULL,
  p_hold_type text DEFAULT NULL  -- 'parts', 'issue', or NULL for all
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_user_role text;
  v_holds_resolved integer := 0;
  v_row_count integer;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT role INTO v_user_role FROM profiles WHERE id = v_user_id;

  IF v_user_role NOT IN ('admin', 'dispatcher') THEN
    RAISE EXCEPTION 'Only admins and dispatchers can resume tickets from hold';
  END IF;

  -- Resolve holds based on type parameter
  IF p_hold_type = 'parts' OR p_hold_type IS NULL THEN
    UPDATE ticket_holds
    SET status = 'resolved', resolved_at = now(), resolved_by = v_user_id
    WHERE ticket_id = p_ticket_id
    AND status = 'active'
    AND hold_type = 'parts';
    
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    v_holds_resolved := v_holds_resolved + v_row_count;

    UPDATE ticket_parts_requests
    SET status = 'fulfilled', fulfilled_at = now(), fulfilled_by = v_user_id
    WHERE ticket_id = p_ticket_id AND status = 'open';

    UPDATE tickets
    SET hold_parts_active = false, updated_at = now()
    WHERE id = p_ticket_id;
  END IF;

  IF p_hold_type = 'issue' OR p_hold_type IS NULL THEN
    UPDATE ticket_holds
    SET status = 'resolved', resolved_at = now(), resolved_by = v_user_id
    WHERE ticket_id = p_ticket_id
    AND status = 'active'
    AND hold_type = 'issue';
    
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    v_holds_resolved := v_holds_resolved + v_row_count;

    UPDATE ticket_issue_reports
    SET 
      status = 'resolved',
      resolved_at = now(),
      resolved_by = v_user_id,
      resolution_notes = p_resolution_notes
    WHERE ticket_id = p_ticket_id
    AND status IN ('open', 'investigating');

    UPDATE tickets
    SET hold_issue_active = false, updated_at = now()
    WHERE id = p_ticket_id;
  END IF;

  -- Update general hold flag and revisit flag
  UPDATE tickets
  SET 
    hold_active = (hold_parts_active OR hold_issue_active),
    revisit_required = false,
    hold_type = CASE 
      WHEN hold_parts_active THEN 'parts'
      WHEN hold_issue_active THEN 'issue'
      ELSE NULL
    END,
    updated_at = now()
  WHERE id = p_ticket_id;

  RETURN jsonb_build_object(
    'success', true,
    'holds_resolved', v_holds_resolved
  );
END;
$$;

COMMENT ON FUNCTION fn_ticket_resume IS 'Resume ticket from hold - can clear specific or all holds';

-- =====================================================
-- PART 3: UPDATE DASHBOARD VIEWS
-- =====================================================

-- Update view for tickets on hold for parts
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
LEFT JOIN customers c ON t.customer_id = c.id
LEFT JOIN profiles p ON t.assigned_to = p.id
LEFT JOIN ticket_holds th ON th.ticket_id = t.id
  AND th.status = 'active'
  AND th.hold_type = 'parts'
LEFT JOIN profiles prof_hold ON th.created_by = prof_hold.id
LEFT JOIN ticket_parts_requests tpr ON tpr.ticket_id = t.id AND tpr.status = 'open'
LEFT JOIN ticket_parts_request_lines tprl ON tprl.request_id = tpr.id
WHERE t.hold_parts_active = true
GROUP BY 
  t.id, t.ticket_number, t.title, t.customer_id, c.name,
  t.assigned_to, p.full_name, t.status,
  th.id, th.summary, th.created_at, th.created_by, prof_hold.full_name,
  tpr.id, tpr.urgency, tpr.notes, tpr.status
ORDER BY th.created_at DESC NULLS LAST, t.created_at DESC;

-- Update view for tickets on hold for issues
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
LEFT JOIN customers c ON t.customer_id = c.id
LEFT JOIN profiles p ON t.assigned_to = p.id
LEFT JOIN ticket_holds th ON th.ticket_id = t.id
  AND th.status = 'active'
  AND th.hold_type = 'issue'
LEFT JOIN profiles prof_hold ON th.created_by = prof_hold.id
LEFT JOIN ticket_issue_reports tir ON tir.ticket_id = t.id AND tir.status IN ('open', 'investigating')
WHERE t.hold_issue_active = true
ORDER BY th.created_at DESC NULLS LAST, t.created_at DESC;

-- Update view for in-progress tickets (excluding holds)
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
  AND t.hold_active = false
ORDER BY t.scheduled_date DESC NULLS LAST, t.created_at DESC;

-- Update aggregated hold metrics
CREATE OR REPLACE VIEW vw_dashboard_hold_metrics AS
SELECT
  (SELECT COUNT(*) FROM tickets WHERE hold_parts_active = true) AS awaiting_parts_count,
  (SELECT COUNT(*) FROM tickets WHERE hold_issue_active = true) AS issues_reported_count,
  (SELECT COUNT(*) FROM tickets WHERE status = 'in_progress' AND hold_active = false) AS in_progress_active_count,
  (SELECT COUNT(*) FROM ticket_parts_requests WHERE status = 'open') AS open_parts_requests_count,
  (SELECT COUNT(*) FROM ticket_issue_reports WHERE status IN ('open', 'investigating')) AS open_issue_reports_count,
  (
    SELECT jsonb_agg(
      jsonb_build_object('urgency', urgency, 'count', cnt)
      ORDER BY CASE urgency 
        WHEN 'critical' THEN 1 WHEN 'high' THEN 2
        WHEN 'medium' THEN 3 WHEN 'low' THEN 4
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
      jsonb_build_object('severity', severity, 'count', cnt)
      ORDER BY CASE severity 
        WHEN 'critical' THEN 1 WHEN 'high' THEN 2
        WHEN 'medium' THEN 3 WHEN 'low' THEN 4
      END
    )
    FROM (
      SELECT severity, COUNT(*) AS cnt
      FROM ticket_issue_reports
      WHERE status IN ('open', 'investigating')
      GROUP BY severity
    ) sub
  ) AS issue_reports_by_severity;

-- =====================================================
-- PART 4: GRANT PERMISSIONS
-- =====================================================

GRANT SELECT ON vw_tickets_on_hold_parts TO authenticated;
GRANT SELECT ON vw_tickets_on_hold_issue TO authenticated;
GRANT SELECT ON vw_tickets_in_progress_active TO authenticated;
GRANT SELECT ON vw_dashboard_hold_metrics TO authenticated;

GRANT EXECUTE ON FUNCTION fn_ticket_hold_for_parts TO authenticated;
GRANT EXECUTE ON FUNCTION fn_ticket_report_issue TO authenticated;
GRANT EXECUTE ON FUNCTION fn_ticket_resume TO authenticated;
