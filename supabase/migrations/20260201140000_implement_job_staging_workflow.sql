/*
  # Job Staging Workflow Implementation

  ## Overview
  Implements a "Chain of Custody" solution for parts received for tickets:
  - Parts are received into a "Job Staging" area, not directly to trucks
  - Parts are reserved/tagged for specific tickets
  - When ticket is assigned, a Pick List is generated
  - Technician clicks "Pickup Parts" to transfer from staging to their truck

  ## Benefits
  - Flexibility: Parts float in reserved status until dispatch decision
  - No manual transfers if technician assignment changes
  - Accountability: Tech must acknowledge pickup to accept liability

  ## Changes
  1. Create Job Staging stock location
  2. Add reservation tracking to part_inventory
  3. Create pick_lists table for pending pickups
  4. Update receiving trigger to use Job Staging
  5. Create pickup function for technicians
*/

-- =====================================================
-- STEP 1: Create Job Staging Stock Location
-- =====================================================

-- Insert Job Staging location if it doesn't exist
-- Using 'warehouse' type since Job Staging is functionally a warehouse area
INSERT INTO stock_locations (id, location_code, name, location_type, is_active)
VALUES (
  'a0000000-0000-0000-0000-000000000001',
  'JOB-STAGING',
  'Job Staging - Parts Ready',
  'warehouse',
  true
)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  is_active = true;

-- =====================================================
-- STEP 2: Add Reservation Tracking to Part Inventory
-- =====================================================

-- Add reserved_for_ticket_id to part_inventory if not exists
ALTER TABLE part_inventory
ADD COLUMN IF NOT EXISTS reserved_for_ticket_id uuid REFERENCES tickets(id);

-- Add reserved_at timestamp
ALTER TABLE part_inventory
ADD COLUMN IF NOT EXISTS reserved_at timestamptz;

-- Add reserved_by (who reserved it - usually the receiving user)
ALTER TABLE part_inventory
ADD COLUMN IF NOT EXISTS reserved_by uuid REFERENCES profiles(id);

-- Index for efficient lookup of reserved parts
CREATE INDEX IF NOT EXISTS idx_part_inventory_reserved_ticket
ON part_inventory(reserved_for_ticket_id) WHERE reserved_for_ticket_id IS NOT NULL;

-- =====================================================
-- STEP 3: Create Pick Lists Table
-- =====================================================

CREATE TABLE IF NOT EXISTS ticket_pick_lists (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  assigned_to uuid REFERENCES profiles(id),  -- The technician assigned to pick up
  status text NOT NULL DEFAULT 'pending',  -- pending, ready, picked_up, cancelled
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  picked_up_at timestamptz,
  picked_up_by uuid REFERENCES profiles(id),
  notes text,
  UNIQUE(ticket_id)  -- One pick list per ticket
);

-- Pick list line items (individual parts to pick up)
CREATE TABLE IF NOT EXISTS ticket_pick_list_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pick_list_id uuid NOT NULL REFERENCES ticket_pick_lists(id) ON DELETE CASCADE,
  part_id uuid NOT NULL REFERENCES parts(id),
  quantity integer NOT NULL DEFAULT 1,
  source_location_id uuid NOT NULL REFERENCES stock_locations(id),
  picked_up boolean DEFAULT false,
  picked_up_at timestamptz,
  notes text
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_pick_lists_ticket ON ticket_pick_lists(ticket_id);
CREATE INDEX IF NOT EXISTS idx_pick_lists_status ON ticket_pick_lists(status);
CREATE INDEX IF NOT EXISTS idx_pick_list_items_list ON ticket_pick_list_items(pick_list_id);

-- =====================================================
-- STEP 4: View for Parts Ready for Pickup
-- =====================================================

CREATE OR REPLACE VIEW vw_parts_ready_for_pickup AS
SELECT
  tpl.id AS pick_list_id,
  tpl.ticket_id,
  t.ticket_number,
  t.title AS ticket_title,
  t.assigned_to,
  p.full_name AS assigned_tech_name,
  t.scheduled_date,
  c.name AS customer_name,
  tpl.status AS pick_list_status,
  tpl.created_at,
  -- Aggregate parts to pick up
  (
    SELECT jsonb_agg(jsonb_build_object(
      'item_id', tpli.id,
      'part_id', tpli.part_id,
      'part_number', parts.part_number,
      'part_name', parts.name,
      'quantity', tpli.quantity,
      'location', sl.name,
      'picked_up', tpli.picked_up
    ))
    FROM ticket_pick_list_items tpli
    JOIN parts ON parts.id = tpli.part_id
    JOIN stock_locations sl ON sl.id = tpli.source_location_id
    WHERE tpli.pick_list_id = tpl.id
  ) AS items,
  -- Count items
  (SELECT COUNT(*) FROM ticket_pick_list_items WHERE pick_list_id = tpl.id) AS total_items,
  (SELECT COUNT(*) FROM ticket_pick_list_items WHERE pick_list_id = tpl.id AND picked_up = true) AS picked_items
FROM ticket_pick_lists tpl
JOIN tickets t ON t.id = tpl.ticket_id
LEFT JOIN profiles p ON p.id = t.assigned_to
LEFT JOIN customers c ON c.id = t.customer_id
WHERE tpl.status IN ('pending', 'ready')
ORDER BY t.scheduled_date ASC NULLS LAST, tpl.created_at ASC;

COMMENT ON VIEW vw_parts_ready_for_pickup IS 'Parts staged and ready for technician pickup';

-- =====================================================
-- STEP 5: Update Receiving Trigger for Job Staging
-- =====================================================

-- Drop the old trigger first
DROP TRIGGER IF EXISTS trg_process_received_parts ON purchase_order_lines;

-- Create improved function that uses Job Staging
CREATE OR REPLACE FUNCTION fn_process_received_parts_for_tickets()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_linked_ticket_id uuid;
  v_linked_request_id uuid;
  v_all_parts_received boolean;
  v_staging_location_id uuid := 'a0000000-0000-0000-0000-000000000001';  -- Job Staging location
  v_pick_list_id uuid;
BEGIN
  -- Only process when quantity_received is updated
  IF NEW.quantity_received IS DISTINCT FROM OLD.quantity_received THEN
    v_linked_ticket_id := NEW.linked_ticket_id;
    v_linked_request_id := NEW.linked_request_id;

    IF v_linked_ticket_id IS NOT NULL AND NEW.quantity_received > COALESCE(OLD.quantity_received, 0) THEN
      -- Calculate how many NEW parts were received this update
      DECLARE
        v_new_qty integer := NEW.quantity_received - COALESCE(OLD.quantity_received, 0);
      BEGIN
        -- Reserve the parts in Job Staging for this ticket
        -- First, check if there's existing inventory in staging for this part
        UPDATE part_inventory
        SET
          quantity = quantity + v_new_qty,
          reserved_for_ticket_id = v_linked_ticket_id,
          reserved_at = now(),
          reserved_by = auth.uid()
        WHERE part_id = NEW.part_id
        AND stock_location_id = v_staging_location_id
        AND (reserved_for_ticket_id = v_linked_ticket_id OR reserved_for_ticket_id IS NULL);

        -- If no rows updated, insert new inventory record
        IF NOT FOUND THEN
          INSERT INTO part_inventory (part_id, stock_location_id, quantity, reserved_for_ticket_id, reserved_at, reserved_by)
          VALUES (NEW.part_id, v_staging_location_id, v_new_qty, v_linked_ticket_id, now(), auth.uid());
        END IF;
      END;

      -- Check if all parts for this request have been received
      SELECT
        NOT EXISTS (
          SELECT 1
          FROM purchase_order_lines pol
          WHERE pol.linked_request_id = v_linked_request_id
          AND COALESCE(pol.quantity_received, 0) < pol.quantity_ordered
        )
      INTO v_all_parts_received;

      IF v_all_parts_received THEN
        -- Update the parts request status to 'received'
        UPDATE ticket_parts_requests
        SET
          status = 'received',
          fulfilled_at = now()
        WHERE id = v_linked_request_id
        AND status = 'ordered';

        -- Create or update pick list for this ticket
        INSERT INTO ticket_pick_lists (ticket_id, status, notes)
        VALUES (v_linked_ticket_id, 'ready', 'Parts received and staged for pickup')
        ON CONFLICT (ticket_id) DO UPDATE SET
          status = 'ready',
          updated_at = now();

        -- Get the pick list ID
        SELECT id INTO v_pick_list_id
        FROM ticket_pick_lists
        WHERE ticket_id = v_linked_ticket_id;

        -- Add items to pick list (aggregate all parts for this ticket in staging)
        INSERT INTO ticket_pick_list_items (pick_list_id, part_id, quantity, source_location_id)
        SELECT
          v_pick_list_id,
          pi.part_id,
          pi.quantity,
          pi.stock_location_id
        FROM part_inventory pi
        WHERE pi.reserved_for_ticket_id = v_linked_ticket_id
        AND pi.stock_location_id = v_staging_location_id
        ON CONFLICT DO NOTHING;

        -- Update ticket: mark as PARTS_READY but keep on hold until pickup
        UPDATE tickets
        SET
          hold_type = 'parts_ready',
          revisit_required = true,
          updated_at = now()
        WHERE id = v_linked_ticket_id;

        -- Resolve the hold but note parts need pickup
        UPDATE ticket_holds
        SET
          status = 'resolved',
          resolved_at = now(),
          metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
            'resolved_reason', 'parts_staged',
            'pickup_required', true,
            'pick_list_id', v_pick_list_id
          )
        WHERE ticket_id = v_linked_ticket_id
        AND hold_type = 'parts'
        AND status = 'active';

        -- Create a ticket update
        INSERT INTO ticket_updates (
          ticket_id,
          technician_id,
          update_type,
          notes,
          status
        ) VALUES (
          v_linked_ticket_id,
          auth.uid(),
          'parts_staged',
          'Parts received and staged in Job Staging area. Ready for technician pickup.',
          'scheduled'
        );
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Recreate trigger
CREATE TRIGGER trg_process_received_parts
AFTER UPDATE ON purchase_order_lines
FOR EACH ROW
EXECUTE FUNCTION fn_process_received_parts_for_tickets();

-- =====================================================
-- STEP 6: Technician Pickup Function
-- =====================================================

CREATE OR REPLACE FUNCTION fn_pickup_parts_for_ticket(
  p_ticket_id uuid,
  p_destination_location_id uuid  -- Tech's truck location
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_pick_list_id uuid;
  v_staging_location_id uuid := 'a0000000-0000-0000-0000-000000000001';
  v_item record;
  v_transferred_count integer := 0;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Get pick list
  SELECT id INTO v_pick_list_id
  FROM ticket_pick_lists
  WHERE ticket_id = p_ticket_id
  AND status IN ('pending', 'ready');

  IF v_pick_list_id IS NULL THEN
    RAISE EXCEPTION 'No pending pick list found for this ticket';
  END IF;

  -- Transfer each part from staging to destination (tech's truck)
  FOR v_item IN
    SELECT tpli.*, pi.quantity as staged_qty
    FROM ticket_pick_list_items tpli
    JOIN part_inventory pi ON pi.part_id = tpli.part_id
      AND pi.stock_location_id = tpli.source_location_id
      AND pi.reserved_for_ticket_id = p_ticket_id
    WHERE tpli.pick_list_id = v_pick_list_id
    AND tpli.picked_up = false
  LOOP
    -- Decrease from staging
    UPDATE part_inventory
    SET
      quantity = quantity - v_item.quantity,
      reserved_for_ticket_id = NULL,
      reserved_at = NULL,
      reserved_by = NULL
    WHERE part_id = v_item.part_id
    AND stock_location_id = v_staging_location_id
    AND reserved_for_ticket_id = p_ticket_id;

    -- Add to tech's truck
    INSERT INTO part_inventory (part_id, stock_location_id, quantity)
    VALUES (v_item.part_id, p_destination_location_id, v_item.quantity)
    ON CONFLICT (part_id, stock_location_id) DO UPDATE
    SET quantity = part_inventory.quantity + EXCLUDED.quantity;

    -- Mark item as picked up
    UPDATE ticket_pick_list_items
    SET picked_up = true, picked_up_at = now()
    WHERE id = v_item.id;

    v_transferred_count := v_transferred_count + 1;
  END LOOP;

  -- Update pick list status
  UPDATE ticket_pick_lists
  SET
    status = 'picked_up',
    picked_up_at = now(),
    picked_up_by = v_user_id,
    updated_at = now()
  WHERE id = v_pick_list_id;

  -- Update ticket - now fully ready to work
  UPDATE tickets
  SET
    hold_active = false,
    hold_type = NULL,
    updated_at = now()
  WHERE id = p_ticket_id;

  -- Add ticket update
  INSERT INTO ticket_updates (
    ticket_id,
    technician_id,
    update_type,
    notes
  ) VALUES (
    p_ticket_id,
    v_user_id,
    'parts_picked_up',
    'Parts picked up from staging area and loaded to truck. Ready to complete job.'
  );

  RETURN jsonb_build_object(
    'success', true,
    'pick_list_id', v_pick_list_id,
    'items_transferred', v_transferred_count,
    'destination_location_id', p_destination_location_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_pickup_parts_for_ticket TO authenticated;

-- =====================================================
-- STEP 7: Auto-generate Pick List on Assignment Change
-- =====================================================

CREATE OR REPLACE FUNCTION fn_handle_ticket_assignment_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- When a ticket with a pending pick list is reassigned, update the pick list
  IF NEW.assigned_to IS DISTINCT FROM OLD.assigned_to THEN
    UPDATE ticket_pick_lists
    SET
      assigned_to = NEW.assigned_to,
      updated_at = now()
    WHERE ticket_id = NEW.id
    AND status IN ('pending', 'ready');
  END IF;

  RETURN NEW;
END;
$$;

-- Create trigger on tickets for assignment changes
DROP TRIGGER IF EXISTS trg_ticket_assignment_change ON tickets;
CREATE TRIGGER trg_ticket_assignment_change
AFTER UPDATE ON tickets
FOR EACH ROW
WHEN (NEW.assigned_to IS DISTINCT FROM OLD.assigned_to)
EXECUTE FUNCTION fn_handle_ticket_assignment_change();

-- =====================================================
-- STEP 8: Grant Permissions
-- =====================================================

GRANT SELECT ON vw_parts_ready_for_pickup TO authenticated;
GRANT SELECT, INSERT, UPDATE ON ticket_pick_lists TO authenticated;
GRANT SELECT, INSERT, UPDATE ON ticket_pick_list_items TO authenticated;

-- RLS Policies
ALTER TABLE ticket_pick_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE ticket_pick_list_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view pick lists" ON ticket_pick_lists
  FOR SELECT USING (true);

CREATE POLICY "Users can manage pick lists" ON ticket_pick_lists
  FOR ALL USING (true);

CREATE POLICY "Users can view pick list items" ON ticket_pick_list_items
  FOR SELECT USING (true);

CREATE POLICY "Users can manage pick list items" ON ticket_pick_list_items
  FOR ALL USING (true);
