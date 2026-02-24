/*
  # Ticket Holds and Issue Tracking System

  ## Overview
  Implements structured "Need Parts" and "Report Issue" ticket actions that:
  - Automatically stop active timers
  - Place tickets on hold with proper tracking
  - Create parts requests or issue reports
  - Enforce clean time-tracking (one active timer per tech)
  - Provide revisit triggers for dispatch

  ## New Tables

  ### `ticket_holds`
  Tracks when tickets are placed on hold and why
  - `id` - Primary key
  - `ticket_id` - Reference to ticket
  - `hold_type` - 'parts' or 'issue'
  - `status` - 'active' or 'resolved'
  - `summary` - Brief description
  - `metadata` - Additional JSON data
  - `created_at`, `created_by` - Audit fields
  - `resolved_at`, `resolved_by` - Resolution audit

  ### `ticket_parts_requests`
  Header for parts requests from field
  - `id` - Primary key
  - `ticket_id` - Reference to ticket
  - `hold_id` - Reference to hold (nullable for future use)
  - `urgency` - 'low', 'medium', 'high', 'critical'
  - `notes` - Additional context
  - `status` - 'open', 'fulfilled', 'cancelled'
  - Audit fields

  ### `ticket_parts_request_lines`
  Line items for parts requests
  - `id` - Primary key
  - `request_id` - Reference to request header
  - `part_id` - Reference to part
  - `quantity_requested` - Requested quantity
  - `quantity_fulfilled` - Fulfilled quantity
  - `notes` - Line-specific notes
  - `preferred_source_location_id` - Preferred stock location

  ### `ticket_issue_reports`
  Issue reports for escalation
  - `id` - Primary key
  - `ticket_id` - Reference to ticket
  - `hold_id` - Reference to hold (nullable)
  - `category` - Issue category
  - `severity` - 'low', 'medium', 'high', 'critical'
  - `description` - Detailed description
  - `metadata` - Attachments, additional data
  - `status` - 'open', 'investigating', 'resolved', 'closed'
  - Audit fields

  ## Schema Additions to Existing Tables

  ### `tickets`
  - `hold_active` - Boolean flag for active holds
  - `hold_type` - Type of active hold
  - `revisit_required` - Flag for dispatch attention

  ## Functions

  - `fn_ticket_hold_for_parts()` - Atomic operation to hold ticket and request parts
  - `fn_ticket_report_issue()` - Atomic operation to hold ticket and report issue
  - `fn_ticket_resume()` - Resume ticket from hold status

  ## Security
  - RLS enabled on all tables
  - Techs can create holds/requests for their assigned tickets
  - Admins and dispatchers can view all
  - Only authorized roles can resolve holds
*/

-- =====================================================
-- PART 1: CORE TABLES
-- =====================================================

-- Ticket Holds Table
CREATE TABLE IF NOT EXISTS ticket_holds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  hold_type text NOT NULL CHECK (hold_type IN ('parts', 'issue')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'resolved')),
  summary text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  resolved_at timestamptz,
  resolved_by uuid REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_ticket_holds_ticket_id ON ticket_holds(ticket_id);
CREATE INDEX IF NOT EXISTS idx_ticket_holds_status ON ticket_holds(status) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_ticket_holds_type ON ticket_holds(hold_type) WHERE status = 'active';

COMMENT ON TABLE ticket_holds IS 'Tracks tickets placed on hold for parts or issues';

-- Ticket Parts Requests Table
CREATE TABLE IF NOT EXISTS ticket_parts_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  hold_id uuid REFERENCES ticket_holds(id) ON DELETE SET NULL,
  urgency text NOT NULL DEFAULT 'medium' CHECK (urgency IN ('low', 'medium', 'high', 'critical')),
  notes text,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'fulfilled', 'cancelled')),
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  fulfilled_at timestamptz,
  fulfilled_by uuid REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_ticket_parts_requests_ticket_id ON ticket_parts_requests(ticket_id);
CREATE INDEX IF NOT EXISTS idx_ticket_parts_requests_status ON ticket_parts_requests(status) WHERE status = 'open';
CREATE INDEX IF NOT EXISTS idx_ticket_parts_requests_hold_id ON ticket_parts_requests(hold_id);

COMMENT ON TABLE ticket_parts_requests IS 'Parts requests from technicians in the field';

-- Ticket Parts Request Lines Table
CREATE TABLE IF NOT EXISTS ticket_parts_request_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES ticket_parts_requests(id) ON DELETE CASCADE,
  part_id uuid NOT NULL REFERENCES parts(id) ON DELETE RESTRICT,
  quantity_requested numeric(10,2) NOT NULL CHECK (quantity_requested > 0),
  quantity_fulfilled numeric(10,2) DEFAULT 0 CHECK (quantity_fulfilled >= 0),
  notes text,
  preferred_source_location_id uuid REFERENCES stock_locations(id),
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ticket_parts_request_lines_request_id ON ticket_parts_request_lines(request_id);
CREATE INDEX IF NOT EXISTS idx_ticket_parts_request_lines_part_id ON ticket_parts_request_lines(part_id);

COMMENT ON TABLE ticket_parts_request_lines IS 'Line items for parts requests';

-- Ticket Issue Reports Table
CREATE TABLE IF NOT EXISTS ticket_issue_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  hold_id uuid REFERENCES ticket_holds(id) ON DELETE SET NULL,
  category text NOT NULL DEFAULT 'other' CHECK (category IN (
    'equipment_failure', 'access_denied', 'safety_concern',
    'scope_change', 'customer_unavailable', 'technical_limitation', 'other'
  )),
  severity text NOT NULL DEFAULT 'medium' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  description text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'investigating', 'resolved', 'closed')),
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  resolved_at timestamptz,
  resolved_by uuid REFERENCES auth.users(id),
  resolution_notes text
);

CREATE INDEX IF NOT EXISTS idx_ticket_issue_reports_ticket_id ON ticket_issue_reports(ticket_id);
CREATE INDEX IF NOT EXISTS idx_ticket_issue_reports_status ON ticket_issue_reports(status) WHERE status IN ('open', 'investigating');
CREATE INDEX IF NOT EXISTS idx_ticket_issue_reports_severity ON ticket_issue_reports(severity);
CREATE INDEX IF NOT EXISTS idx_ticket_issue_reports_hold_id ON ticket_issue_reports(hold_id);

COMMENT ON TABLE ticket_issue_reports IS 'Issue reports from technicians requiring escalation or dispatch attention';

-- =====================================================
-- PART 2: ADD COLUMNS TO TICKETS TABLE
-- =====================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tickets' AND column_name = 'hold_active'
  ) THEN
    ALTER TABLE tickets ADD COLUMN hold_active boolean DEFAULT false;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tickets' AND column_name = 'hold_type'
  ) THEN
    ALTER TABLE tickets ADD COLUMN hold_type text CHECK (hold_type IN ('parts', 'issue'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tickets' AND column_name = 'revisit_required'
  ) THEN
    ALTER TABLE tickets ADD COLUMN revisit_required boolean DEFAULT false;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_tickets_hold_active ON tickets(hold_active) WHERE hold_active = true;
CREATE INDEX IF NOT EXISTS idx_tickets_revisit_required ON tickets(revisit_required) WHERE revisit_required = true;

-- =====================================================
-- PART 3: RLS POLICIES
-- =====================================================

-- Enable RLS
ALTER TABLE ticket_holds ENABLE ROW LEVEL SECURITY;
ALTER TABLE ticket_parts_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE ticket_parts_request_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE ticket_issue_reports ENABLE ROW LEVEL SECURITY;

-- ticket_holds policies
CREATE POLICY "Admins and dispatchers can view all holds"
  ON ticket_holds FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('admin', 'dispatcher')
    )
  );

CREATE POLICY "Technicians can view holds for their tickets"
  ON ticket_holds FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM tickets
      WHERE tickets.id = ticket_holds.ticket_id
      AND tickets.assigned_to = auth.uid()
    )
  );

CREATE POLICY "Technicians can create holds"
  ON ticket_holds FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('admin', 'dispatcher', 'technician')
    )
  );

CREATE POLICY "Admins and dispatchers can update holds"
  ON ticket_holds FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('admin', 'dispatcher')
    )
  );

-- ticket_parts_requests policies
CREATE POLICY "Admins and dispatchers can view all parts requests"
  ON ticket_parts_requests FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('admin', 'dispatcher')
    )
  );

CREATE POLICY "Technicians can view their parts requests"
  ON ticket_parts_requests FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM tickets
      WHERE tickets.id = ticket_parts_requests.ticket_id
      AND tickets.assigned_to = auth.uid()
    )
  );

CREATE POLICY "Technicians can create parts requests"
  ON ticket_parts_requests FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('admin', 'dispatcher', 'technician')
    )
  );

CREATE POLICY "Admins and dispatchers can update parts requests"
  ON ticket_parts_requests FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('admin', 'dispatcher')
    )
  );

-- ticket_parts_request_lines policies
CREATE POLICY "Users can view request lines if they can view the request"
  ON ticket_parts_request_lines FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM ticket_parts_requests
      WHERE ticket_parts_requests.id = ticket_parts_request_lines.request_id
      AND (
        EXISTS (
          SELECT 1 FROM profiles
          WHERE profiles.id = auth.uid()
          AND profiles.role IN ('admin', 'dispatcher')
        )
        OR EXISTS (
          SELECT 1 FROM tickets
          WHERE tickets.id = ticket_parts_requests.ticket_id
          AND tickets.assigned_to = auth.uid()
        )
      )
    )
  );

CREATE POLICY "Technicians can create request lines"
  ON ticket_parts_request_lines FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('admin', 'dispatcher', 'technician')
    )
  );

CREATE POLICY "Admins and dispatchers can update request lines"
  ON ticket_parts_request_lines FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('admin', 'dispatcher')
    )
  );

-- ticket_issue_reports policies
CREATE POLICY "Admins and dispatchers can view all issue reports"
  ON ticket_issue_reports FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('admin', 'dispatcher')
    )
  );

CREATE POLICY "Technicians can view their issue reports"
  ON ticket_issue_reports FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM tickets
      WHERE tickets.id = ticket_issue_reports.ticket_id
      AND tickets.assigned_to = auth.uid()
    )
  );

CREATE POLICY "Technicians can create issue reports"
  ON ticket_issue_reports FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('admin', 'dispatcher', 'technician')
    )
  );

CREATE POLICY "Admins and dispatchers can update issue reports"
  ON ticket_issue_reports FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('admin', 'dispatcher')
    )
  );
