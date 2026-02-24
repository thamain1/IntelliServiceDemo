/*
  # Create Ticket Updates Table

  ## Overview
  Creates the `ticket_updates` table used for tracking timeline events, 
  technician notes, and status changes for service tickets.

  ## Schema
  - `id` (uuid, primary key)
  - `ticket_id` (uuid, references tickets)
  - `technician_id` (uuid, references profiles)
  - `update_type` (text) - e.g., 'status_change', 'needs_parts', 'issue', 'parts_staged'
  - `notes` (text)
  - `status` (ticket_status)
  - `progress_percent` (integer)
  - `created_at` (timestamptz)
  - `updated_at` (timestamptz)
*/

CREATE TABLE IF NOT EXISTS ticket_updates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  technician_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  update_type text NOT NULL DEFAULT 'status_change',
  notes text,
  status ticket_status,
  progress_percent integer CHECK (progress_percent >= 0 AND progress_percent <= 100),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE ticket_updates ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view updates for accessible tickets"
  ON ticket_updates FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM tickets
      WHERE tickets.id = ticket_updates.ticket_id
      AND (
        EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'dispatcher'))
        OR tickets.assigned_to = auth.uid()
      )
    )
  );

CREATE POLICY "Technicians can insert updates for assigned tickets"
  ON ticket_updates FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM tickets
      WHERE tickets.id = ticket_updates.ticket_id
      AND tickets.assigned_to = auth.uid()
    )
  );

CREATE POLICY "Admins and dispatchers can manage all updates"
  ON ticket_updates FOR ALL
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'dispatcher'))
  );

-- Indexes
CREATE INDEX IF NOT EXISTS idx_ticket_updates_ticket_id ON ticket_updates(ticket_id);
CREATE INDEX IF NOT EXISTS idx_ticket_updates_technician_id ON ticket_updates(technician_id);
CREATE INDEX IF NOT EXISTS idx_ticket_updates_created_at ON ticket_updates(created_at DESC);

-- Trigger for updated_at
CREATE TRIGGER update_ticket_updates_updated_at
  BEFORE UPDATE ON ticket_updates
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
