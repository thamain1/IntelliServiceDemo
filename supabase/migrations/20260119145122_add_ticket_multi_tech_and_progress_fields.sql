/*
  # Add Multi-Technician and Progress Tracking to Tickets

  1. New Tables
    - `ticket_assignments` - junction table for multi-tech assignments
      - `id` (uuid, primary key)
      - `ticket_id` (uuid, foreign key to tickets)
      - `technician_id` (uuid, foreign key to profiles)
      - `scheduled_start` (timestamptz, nullable) - when tech scheduled to start
      - `scheduled_end` (timestamptz, nullable) - when tech scheduled to end
      - `role` (text, nullable) - 'lead' or 'helper' designation
      - `created_at` (timestamptz)
      - `created_by` (uuid, foreign key to profiles)
      - `updated_at` (timestamptz)

  2. New Columns on `tickets`
    - `estimated_minutes` (integer, nullable) - estimated work duration in minutes
    - `work_started_at` (timestamptz, nullable) - when work actually started on site
    - `closed_billed_date` (timestamptz, nullable) - when ticket was closed and billed

  3. Security
    - Enable RLS on `ticket_assignments` table
    - Add policies for authenticated users to read/write assignments

  4. Notes
    - Maintains backward compatibility with existing `assigned_to` field
    - Multi-day scheduling supported via multiple assignment rows
    - Progress calculation will use time_logs when available, fallback to work_started_at
*/

-- Add new fields to tickets table
ALTER TABLE tickets
  ADD COLUMN IF NOT EXISTS estimated_minutes integer,
  ADD COLUMN IF NOT EXISTS work_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS closed_billed_date timestamptz;

-- Create ticket_assignments table for multi-tech support
CREATE TABLE IF NOT EXISTS ticket_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  technician_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  scheduled_start timestamptz,
  scheduled_end timestamptz,
  role text CHECK (role IN ('lead', 'helper', NULL)),
  created_at timestamptz DEFAULT now() NOT NULL,
  created_by uuid REFERENCES profiles(id),
  updated_at timestamptz DEFAULT now() NOT NULL
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_ticket_assignments_ticket_id ON ticket_assignments(ticket_id);
CREATE INDEX IF NOT EXISTS idx_ticket_assignments_technician_id ON ticket_assignments(technician_id);
CREATE INDEX IF NOT EXISTS idx_ticket_assignments_scheduled_start ON ticket_assignments(scheduled_start);

-- Enable RLS
ALTER TABLE ticket_assignments ENABLE ROW LEVEL SECURITY;

-- RLS Policies for ticket_assignments
CREATE POLICY "Users can view ticket assignments"
  ON ticket_assignments FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admins and dispatchers can insert ticket assignments"
  ON ticket_assignments FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('admin', 'dispatcher')
    )
  );

CREATE POLICY "Admins and dispatchers can update ticket assignments"
  ON ticket_assignments FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('admin', 'dispatcher')
    )
  );

CREATE POLICY "Admins and dispatchers can delete ticket assignments"
  ON ticket_assignments FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('admin', 'dispatcher')
    )
  );

-- Create function to auto-update updated_at
CREATE OR REPLACE FUNCTION update_ticket_assignments_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for updated_at
DROP TRIGGER IF EXISTS ticket_assignments_updated_at ON ticket_assignments;
CREATE TRIGGER ticket_assignments_updated_at
  BEFORE UPDATE ON ticket_assignments
  FOR EACH ROW
  EXECUTE FUNCTION update_ticket_assignments_updated_at();

-- Create helper function to get ticket progress percentage
CREATE OR REPLACE FUNCTION get_ticket_progress(p_ticket_id uuid)
RETURNS numeric AS $$
DECLARE
  v_estimated_minutes integer;
  v_worked_minutes numeric;
  v_work_started_at timestamptz;
  v_progress numeric;
BEGIN
  -- Get ticket estimated minutes and work_started_at
  SELECT estimated_minutes, work_started_at
  INTO v_estimated_minutes, v_work_started_at
  FROM tickets
  WHERE id = p_ticket_id;

  -- If no estimate, return NULL
  IF v_estimated_minutes IS NULL OR v_estimated_minutes = 0 THEN
    RETURN NULL;
  END IF;

  -- Try to get worked minutes from time_logs
  SELECT COALESCE(SUM(
    EXTRACT(EPOCH FROM (
      COALESCE(clock_out, now()) - clock_in
    )) / 60
  ), 0)
  INTO v_worked_minutes
  FROM time_logs
  WHERE ticket_id = p_ticket_id;

  -- If no time logs and work_started_at exists, calculate elapsed time
  IF v_worked_minutes = 0 AND v_work_started_at IS NOT NULL THEN
    v_worked_minutes := EXTRACT(EPOCH FROM (now() - v_work_started_at)) / 60;
  END IF;

  -- Calculate progress percentage (clamped between 0 and 100)
  v_progress := LEAST(100, GREATEST(0, (v_worked_minutes / v_estimated_minutes * 100)));

  RETURN ROUND(v_progress, 1);
END;
$$ LANGUAGE plpgsql STABLE;