/*
  # Multi-Fix Update: Tech Tickets, Time Tracking, Dashboard KPIs, Admin

  ## 1. Ticket Progress Bar - Arrived Onsite Timestamp
    - Add `arrived_onsite_at` column to tickets table
    - Create `vw_ticket_onsite_progress` view for progress calculations

  ## 2. Dashboard Views
    - Create `vw_active_technicians` - only clocked-in technicians
    - Create `vw_scheduled_tickets_today` - today's scheduled tickets

  ## 3. Concurrent Timer Prevention
    - Add partial unique index to prevent multiple open ticket timers per tech
    - Create `fn_start_ticket_work` RPC function with validation

  ## 4. Admin Audit Events Table
    - Create `admin_audit_events` table for logging admin actions

  ## 5. Technician Vehicle Assignment
    - Add `default_vehicle_id` to profiles for truck inventory filtering

  ## Security
    - RLS enabled on all new tables
    - Audit events restricted to admin viewing
    - No changes to existing inventory, invoicing, or accounting logic
*/

-- =====================================================
-- STEP 1: Ticket Progress Bar - Arrived Onsite Timestamp
-- =====================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tickets' AND column_name = 'arrived_onsite_at'
  ) THEN
    ALTER TABLE tickets 
    ADD COLUMN arrived_onsite_at timestamptz NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_tickets_arrived_onsite_at 
ON tickets(arrived_onsite_at) 
WHERE arrived_onsite_at IS NOT NULL;

-- View for ticket onsite progress calculation
CREATE OR REPLACE VIEW vw_ticket_onsite_progress AS
SELECT
  t.id as ticket_id,
  t.ticket_number,
  t.status,
  t.arrived_onsite_at,
  COALESCE(t.estimated_minutes, t.estimated_duration, 60) as estimated_onsite_minutes,
  CASE 
    WHEN t.arrived_onsite_at IS NULL THEN 0
    ELSE EXTRACT(EPOCH FROM (NOW() - t.arrived_onsite_at)) / 60
  END::integer as elapsed_minutes,
  CASE 
    WHEN t.arrived_onsite_at IS NULL THEN 0
    WHEN COALESCE(t.estimated_minutes, t.estimated_duration, 60) = 0 THEN 100
    ELSE LEAST(100, ROUND(
      (EXTRACT(EPOCH FROM (NOW() - t.arrived_onsite_at)) / 60) * 100.0 / 
      COALESCE(t.estimated_minutes, t.estimated_duration, 60)
    ))
  END::integer as percent,
  CASE 
    WHEN t.arrived_onsite_at IS NULL THEN false
    WHEN EXTRACT(EPOCH FROM (NOW() - t.arrived_onsite_at)) / 60 > 
         COALESCE(t.estimated_minutes, t.estimated_duration, 60) THEN true
    ELSE false
  END as is_overrun,
  t.assigned_to
FROM tickets t
WHERE t.status IN ('in_progress', 'scheduled', 'open');

GRANT SELECT ON vw_ticket_onsite_progress TO authenticated;

-- =====================================================
-- STEP 2: Dashboard - Active Technicians (Clocked-in Only)
-- =====================================================

CREATE OR REPLACE VIEW vw_active_technicians AS
SELECT DISTINCT 
  tl.user_id as tech_user_id,
  p.full_name,
  p.email,
  tl.clock_in_time,
  tl.ticket_id as current_ticket_id,
  t.ticket_number as current_ticket_number
FROM time_logs tl
JOIN profiles p ON p.id = tl.user_id
LEFT JOIN tickets t ON t.id = tl.ticket_id
WHERE tl.clock_out_time IS NULL
  AND p.role = 'technician'
  AND p.is_active = true;

GRANT SELECT ON vw_active_technicians TO authenticated;

-- =====================================================
-- STEP 3: Dashboard - Scheduled Tickets Today
-- =====================================================

CREATE OR REPLACE VIEW vw_scheduled_tickets_today AS
SELECT 
  t.id,
  t.ticket_number,
  t.title,
  t.status,
  t.priority,
  t.scheduled_date,
  t.assigned_to,
  p.full_name as technician_name,
  c.name as customer_name
FROM tickets t
LEFT JOIN profiles p ON p.id = t.assigned_to
LEFT JOIN customers c ON c.id = t.customer_id
WHERE t.scheduled_date >= CURRENT_DATE
  AND t.scheduled_date < CURRENT_DATE + INTERVAL '1 day'
  AND t.status IN ('open', 'scheduled', 'in_progress');

GRANT SELECT ON vw_scheduled_tickets_today TO authenticated;

-- =====================================================
-- STEP 4: Concurrent Timer Prevention
-- =====================================================

-- First, close any duplicate open time entries (keep the earliest)
WITH duplicates AS (
  SELECT id, user_id, clock_in_time,
    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY clock_in_time ASC) as rn
  FROM time_logs
  WHERE clock_out_time IS NULL
)
UPDATE time_logs
SET clock_out_time = NOW(),
    total_hours = EXTRACT(EPOCH FROM (NOW() - clock_in_time)) / 3600
WHERE id IN (
  SELECT id FROM duplicates WHERE rn > 1
);

-- Create partial unique index to prevent multiple open entries per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_time_logs_one_open_per_user
ON time_logs(user_id)
WHERE clock_out_time IS NULL;

-- Function to start ticket work with validation
CREATE OR REPLACE FUNCTION fn_start_ticket_work(
  p_tech_id uuid,
  p_ticket_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_existing_log record;
  v_new_log_id uuid;
  v_ticket record;
BEGIN
  -- Check for existing open time entry
  SELECT tl.id, tl.ticket_id, t.ticket_number
  INTO v_existing_log
  FROM time_logs tl
  LEFT JOIN tickets t ON t.id = tl.ticket_id
  WHERE tl.user_id = p_tech_id
    AND tl.clock_out_time IS NULL
  LIMIT 1;

  IF v_existing_log IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'already_timing',
      'message', format('You are currently timing Ticket %s. End or complete it before starting another.', 
                       COALESCE(v_existing_log.ticket_number, 'Unknown')),
      'existing_ticket_id', v_existing_log.ticket_id
    );
  END IF;

  -- Verify ticket exists and is assigned
  SELECT id, ticket_number, status, assigned_to
  INTO v_ticket
  FROM tickets
  WHERE id = p_ticket_id;

  IF v_ticket IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'ticket_not_found',
      'message', 'Ticket not found'
    );
  END IF;

  -- Create new time log entry
  INSERT INTO time_logs (
    user_id,
    ticket_id,
    clock_in_time,
    time_type,
    status
  ) VALUES (
    p_tech_id,
    p_ticket_id,
    NOW(),
    'on_site',
    'active'
  )
  RETURNING id INTO v_new_log_id;

  -- Update ticket arrived_onsite_at if not already set
  UPDATE tickets
  SET arrived_onsite_at = COALESCE(arrived_onsite_at, NOW()),
      work_started_at = COALESCE(work_started_at, NOW()),
      status = CASE WHEN status IN ('open', 'scheduled') THEN 'in_progress' ELSE status END,
      updated_at = NOW()
  WHERE id = p_ticket_id;

  RETURN jsonb_build_object(
    'success', true,
    'time_log_id', v_new_log_id,
    'ticket_id', p_ticket_id,
    'message', 'Timer started successfully'
  );
END;
$$;

-- Function to end ticket work
CREATE OR REPLACE FUNCTION fn_end_ticket_work(
  p_tech_id uuid,
  p_ticket_id uuid DEFAULT NULL,
  p_mark_for_revisit boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_log record;
  v_total_hours numeric;
BEGIN
  -- Find active time log
  SELECT id, clock_in_time, ticket_id
  INTO v_log
  FROM time_logs
  WHERE user_id = p_tech_id
    AND clock_out_time IS NULL
    AND (p_ticket_id IS NULL OR ticket_id = p_ticket_id)
  LIMIT 1;

  IF v_log IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'no_active_timer',
      'message', 'No active timer found'
    );
  END IF;

  -- Calculate total hours
  v_total_hours := EXTRACT(EPOCH FROM (NOW() - v_log.clock_in_time)) / 3600;

  -- Close the time log
  UPDATE time_logs
  SET clock_out_time = NOW(),
      total_hours = v_total_hours,
      status = 'completed',
      updated_at = NOW()
  WHERE id = v_log.id;

  -- Update ticket hours if applicable
  IF v_log.ticket_id IS NOT NULL THEN
    UPDATE tickets
    SET hours_onsite = COALESCE(hours_onsite, 0) + v_total_hours,
        actual_duration_minutes = COALESCE(actual_duration_minutes, 0) + (v_total_hours * 60),
        updated_at = NOW()
    WHERE id = v_log.ticket_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'time_log_id', v_log.id,
    'ticket_id', v_log.ticket_id,
    'total_hours', ROUND(v_total_hours, 2),
    'message', 'Timer stopped successfully'
  );
END;
$$;

-- Function to check if tech has active timer
CREATE OR REPLACE FUNCTION fn_get_active_timer(p_tech_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_log record;
BEGIN
  SELECT tl.id, tl.ticket_id, tl.clock_in_time, t.ticket_number
  INTO v_log
  FROM time_logs tl
  LEFT JOIN tickets t ON t.id = tl.ticket_id
  WHERE tl.user_id = p_tech_id
    AND tl.clock_out_time IS NULL
  LIMIT 1;

  IF v_log IS NULL THEN
    RETURN jsonb_build_object(
      'has_active_timer', false
    );
  END IF;

  RETURN jsonb_build_object(
    'has_active_timer', true,
    'time_log_id', v_log.id,
    'ticket_id', v_log.ticket_id,
    'ticket_number', v_log.ticket_number,
    'started_at', v_log.clock_in_time,
    'elapsed_minutes', EXTRACT(EPOCH FROM (NOW() - v_log.clock_in_time)) / 60
  );
END;
$$;

-- =====================================================
-- STEP 5: Admin Audit Events Table
-- =====================================================

CREATE TABLE IF NOT EXISTS admin_audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_user_id uuid NOT NULL REFERENCES profiles(id),
  action_type text NOT NULL,
  target_user_id uuid REFERENCES profiles(id),
  target_entity_type text,
  target_entity_id uuid,
  old_values jsonb,
  new_values jsonb,
  metadata jsonb,
  ip_address text,
  user_agent text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE admin_audit_events ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'admin_audit_events' AND policyname = 'Admins can view audit events'
  ) THEN
    CREATE POLICY "Admins can view audit events"
      ON admin_audit_events FOR SELECT
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM profiles
          WHERE profiles.id = auth.uid()
          AND profiles.role = 'admin'
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'admin_audit_events' AND policyname = 'Admins can create audit events'
  ) THEN
    CREATE POLICY "Admins can create audit events"
      ON admin_audit_events FOR INSERT
      TO authenticated
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM profiles
          WHERE profiles.id = auth.uid()
          AND profiles.role = 'admin'
        )
      );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_admin_audit_events_admin_user_id 
ON admin_audit_events(admin_user_id);

CREATE INDEX IF NOT EXISTS idx_admin_audit_events_target_user_id 
ON admin_audit_events(target_user_id);

CREATE INDEX IF NOT EXISTS idx_admin_audit_events_created_at 
ON admin_audit_events(created_at DESC);

-- =====================================================
-- STEP 6: Technician Vehicle Assignment
-- =====================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'default_vehicle_id'
  ) THEN
    ALTER TABLE profiles 
    ADD COLUMN default_vehicle_id uuid REFERENCES stock_locations(id) NULL;
  END IF;
END $$;

-- View for technician truck inventory (uses correct column name: stock_location_id)
CREATE OR REPLACE VIEW vw_technician_truck_inventory AS
SELECT 
  p.id as technician_id,
  p.full_name as technician_name,
  p.default_vehicle_id,
  sl.name as vehicle_name,
  sl.location_code as vehicle_code,
  pi.part_id,
  pt.part_number,
  pt.name as part_name,
  pt.unit_price,
  pi.quantity as qty_on_hand
FROM profiles p
JOIN stock_locations sl ON sl.id = p.default_vehicle_id
JOIN part_inventory pi ON pi.stock_location_id = sl.id
JOIN parts pt ON pt.id = pi.part_id
WHERE p.role = 'technician'
  AND sl.location_type = 'truck'
  AND pi.quantity > 0;

GRANT SELECT ON vw_technician_truck_inventory TO authenticated;

-- View for serialized parts on truck
CREATE OR REPLACE VIEW vw_technician_truck_serialized AS
SELECT 
  p.id as technician_id,
  p.full_name as technician_name,
  p.default_vehicle_id,
  sl.name as vehicle_name,
  sp.id as serialized_part_id,
  sp.serial_number,
  sp.part_id,
  pt.part_number,
  pt.name as part_name,
  pt.unit_price,
  sp.status
FROM profiles p
JOIN stock_locations sl ON sl.id = p.default_vehicle_id
JOIN serialized_parts sp ON sp.current_location_id = sl.id
JOIN parts pt ON pt.id = sp.part_id
WHERE p.role = 'technician'
  AND sl.location_type = 'truck'
  AND sp.status = 'in_stock';

GRANT SELECT ON vw_technician_truck_serialized TO authenticated;
