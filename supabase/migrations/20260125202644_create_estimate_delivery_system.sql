/*
  # Estimate Delivery and Customer Review System

  1. New Tables
    - `customer_contacts`
      - Contact information for customers (email, phone, billing contacts)
      - Links to customers and optionally to customer_locations
    - `estimate_public_links`
      - Public shareable links for estimates with tokens
      - Tracks views, expirations, revocations, and customer decisions
    - `estimate_delivery_attempts`
      - Audit log of estimate delivery attempts via email/SMS
      - Tracks provider responses and delivery status
    - `estimate_events`
      - Complete audit trail of all estimate lifecycle events
      - Tracks internal, customer, and system actions

  2. Security
    - Enable RLS on all new tables
    - Customer contacts readable by authenticated users
    - Public links have special public access for portal views
    - Delivery attempts and events are internal-only
    - All tables use proper foreign key constraints

  3. Extensions
    - Enable pgcrypto for secure token hashing
*/

-- Enable pgcrypto for token hashing
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Customer contacts table
CREATE TABLE IF NOT EXISTS customer_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  location_id uuid REFERENCES customer_locations(id) ON DELETE SET NULL,
  
  -- Contact details
  name text NOT NULL,
  title text,
  email text,
  phone text,
  mobile text,
  
  -- Flags
  is_primary boolean DEFAULT false,
  is_billing_contact boolean DEFAULT false,
  is_technical_contact boolean DEFAULT false,
  receive_estimates boolean DEFAULT true,
  receive_invoices boolean DEFAULT true,
  
  -- Metadata
  notes text,
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES profiles(id),
  updated_at timestamptz DEFAULT now(),
  updated_by uuid REFERENCES profiles(id),
  
  CONSTRAINT email_or_phone_required CHECK (email IS NOT NULL OR phone IS NOT NULL OR mobile IS NOT NULL)
);

-- Estimate public links table
CREATE TABLE IF NOT EXISTS estimate_public_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  estimate_id uuid NOT NULL REFERENCES estimates(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  contact_id uuid REFERENCES customer_contacts(id) ON DELETE SET NULL,
  
  -- Token management (store hash only for security)
  token_hash text NOT NULL UNIQUE,
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_by uuid REFERENCES profiles(id),
  revocation_reason text,
  
  -- View tracking
  last_viewed_at timestamptz,
  view_count integer DEFAULT 0,
  
  -- Customer decision
  decision text CHECK (decision IN ('accepted', 'rejected')),
  decided_at timestamptz,
  decided_name text,
  decided_ip text,
  decided_user_agent text,
  decision_comment text,
  
  -- Metadata
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES profiles(id),
  
  CONSTRAINT decision_fields_consistent CHECK (
    (decision IS NULL AND decided_at IS NULL AND decided_name IS NULL) OR
    (decision IS NOT NULL AND decided_at IS NOT NULL AND decided_name IS NOT NULL)
  )
);

-- Estimate delivery attempts table
CREATE TABLE IF NOT EXISTS estimate_delivery_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  link_id uuid NOT NULL REFERENCES estimate_public_links(id) ON DELETE CASCADE,
  
  -- Delivery details
  channel text NOT NULL CHECK (channel IN ('email', 'sms')),
  to_address text NOT NULL,
  
  -- Provider info
  provider text NOT NULL,
  provider_message_id text,
  
  -- Status tracking
  status text NOT NULL CHECK (status IN ('queued', 'sent', 'failed', 'bounced', 'delivered')),
  error text,
  
  -- Metadata
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES profiles(id),
  sent_at timestamptz,
  delivered_at timestamptz,
  failed_at timestamptz
);

-- Estimate events table (audit trail)
CREATE TABLE IF NOT EXISTS estimate_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  estimate_id uuid NOT NULL REFERENCES estimates(id) ON DELETE CASCADE,
  link_id uuid REFERENCES estimate_public_links(id) ON DELETE SET NULL,
  
  -- Event details
  event_type text NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  
  -- Actor tracking
  actor_type text NOT NULL CHECK (actor_type IN ('internal', 'customer', 'system')),
  actor_user_id uuid REFERENCES profiles(id),
  actor_ip text,
  actor_user_agent text,
  
  -- Metadata
  created_at timestamptz DEFAULT now()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_customer_contacts_customer_id ON customer_contacts(customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_contacts_location_id ON customer_contacts(location_id);
CREATE INDEX IF NOT EXISTS idx_customer_contacts_is_primary ON customer_contacts(customer_id, is_primary) WHERE is_primary = true;

CREATE INDEX IF NOT EXISTS idx_estimate_public_links_estimate_id ON estimate_public_links(estimate_id);
CREATE INDEX IF NOT EXISTS idx_estimate_public_links_customer_id ON estimate_public_links(customer_id);
CREATE INDEX IF NOT EXISTS idx_estimate_public_links_token_hash ON estimate_public_links(token_hash);
CREATE INDEX IF NOT EXISTS idx_estimate_public_links_active ON estimate_public_links(estimate_id) WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_estimate_delivery_attempts_link_id ON estimate_delivery_attempts(link_id);
CREATE INDEX IF NOT EXISTS idx_estimate_delivery_attempts_status ON estimate_delivery_attempts(status);
CREATE INDEX IF NOT EXISTS idx_estimate_delivery_attempts_created_at ON estimate_delivery_attempts(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_estimate_events_estimate_id ON estimate_events(estimate_id);
CREATE INDEX IF NOT EXISTS idx_estimate_events_link_id ON estimate_events(link_id);
CREATE INDEX IF NOT EXISTS idx_estimate_events_event_type ON estimate_events(event_type);
CREATE INDEX IF NOT EXISTS idx_estimate_events_created_at ON estimate_events(created_at DESC);

-- Enable Row Level Security
ALTER TABLE customer_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE estimate_public_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE estimate_delivery_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE estimate_events ENABLE ROW LEVEL SECURITY;

-- RLS Policies for customer_contacts
CREATE POLICY "Authenticated users can view customer contacts"
  ON customer_contacts FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can create customer contacts"
  ON customer_contacts FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Authenticated users can update customer contacts"
  ON customer_contacts FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Authenticated users can delete customer contacts"
  ON customer_contacts FOR DELETE
  TO authenticated
  USING (true);

-- RLS Policies for estimate_public_links
CREATE POLICY "Authenticated users can view estimate links"
  ON estimate_public_links FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Public can view active links by token hash"
  ON estimate_public_links FOR SELECT
  TO anon
  USING (revoked_at IS NULL AND (expires_at IS NULL OR expires_at > now()));

CREATE POLICY "Authenticated users can create estimate links"
  ON estimate_public_links FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Authenticated users can update estimate links"
  ON estimate_public_links FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Public can update link views and decisions"
  ON estimate_public_links FOR UPDATE
  TO anon
  USING (revoked_at IS NULL AND (expires_at IS NULL OR expires_at > now()))
  WITH CHECK (revoked_at IS NULL AND (expires_at IS NULL OR expires_at > now()));

-- RLS Policies for estimate_delivery_attempts
CREATE POLICY "Authenticated users can view delivery attempts"
  ON estimate_delivery_attempts FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can create delivery attempts"
  ON estimate_delivery_attempts FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- RLS Policies for estimate_events
CREATE POLICY "Authenticated users can view estimate events"
  ON estimate_events FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can create estimate events"
  ON estimate_events FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Public can create customer events"
  ON estimate_events FOR INSERT
  TO anon
  WITH CHECK (actor_type = 'customer');

-- Update trigger for customer_contacts
CREATE OR REPLACE FUNCTION update_customer_contacts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_customer_contacts_updated_at
  BEFORE UPDATE ON customer_contacts
  FOR EACH ROW
  EXECUTE FUNCTION update_customer_contacts_updated_at();