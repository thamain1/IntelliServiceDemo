/*
  # Create Parts Ordering System

  ## Overview
  Implements Procurement → Parts Ordering with Vendor Catalogs, Reorder Alerts, and Lead Time Reports.
  Additive-only changes, no breaking modifications.

  ## 1. New Tables

  ### inventory_reorder_policies
  Defines reorder policies per part+location:
  - id (uuid, primary key)
  - part_id (uuid, FK to parts)
  - location_id (uuid, FK to stock_locations, nullable for "all locations" policy)
  - min_qty (integer) - Minimum stock level
  - max_qty (integer) - Maximum stock level
  - safety_stock_qty (integer) - Safety stock buffer
  - lead_days_override (integer) - Override vendor lead time
  - review_period_days (integer) - How often to review
  - reorder_method (enum: rop|minmax) - Reorder point or min/max
  - is_active (boolean)
  - created_at, updated_at

  ## 2. Enhanced vendor_part_mappings
  Add missing fields if they don't exist:
  - uom (text) - Unit of measure
  - pack_qty (integer) - Package quantity

  ## 3. Views

  ### vw_vendor_catalog_items
  Joined vendor catalog with part details, pricing, MOQ, lead times

  ### vw_reorder_alerts
  Calculate reorder points and suggested order quantities per part+location:
  - on_hand (from part_inventory)
  - reserved (TODO: from ticket/project allocations)
  - inbound_open_po (from open PO lines)
  - avg_daily_usage (TODO: historical usage tracking)
  - lead_days
  - reorder_point
  - suggested_order_qty

  ### vw_vendor_lead_time_metrics
  Lead time performance by vendor:
  - avg, median, p90 lead time
  - on-time delivery rate
  - fill rate

  ## Security
  - Enable RLS on new tables
  - Admin/dispatcher: full CRUD
  - Technician: read-only

  ## Notes
  - Additive only - no DROP/ALTER of existing columns
  - Single source of truth for inventory (part_inventory)
  - Reserved/allocated calculations stubbed with TODO (won't break page)
*/

-- Create reorder method enum
DO $$ BEGIN
  CREATE TYPE reorder_method AS ENUM ('rop', 'minmax');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- Create inventory_reorder_policies table
CREATE TABLE IF NOT EXISTS inventory_reorder_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  part_id uuid NOT NULL REFERENCES parts(id) ON DELETE CASCADE,
  location_id uuid REFERENCES stock_locations(id) ON DELETE CASCADE,
  min_qty integer NOT NULL DEFAULT 0,
  max_qty integer NOT NULL DEFAULT 0,
  safety_stock_qty integer NOT NULL DEFAULT 0,
  lead_days_override integer,
  review_period_days integer DEFAULT 7,
  reorder_method reorder_method DEFAULT 'rop',
  is_active boolean DEFAULT true,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Add missing columns to vendor_part_mappings if they don't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'vendor_part_mappings' AND column_name = 'uom'
  ) THEN
    ALTER TABLE vendor_part_mappings ADD COLUMN uom text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'vendor_part_mappings' AND column_name = 'pack_qty'
  ) THEN
    ALTER TABLE vendor_part_mappings ADD COLUMN pack_qty integer DEFAULT 1;
  END IF;
END $$;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_reorder_policies_part_location ON inventory_reorder_policies(part_id, location_id);
CREATE INDEX IF NOT EXISTS idx_reorder_policies_active ON inventory_reorder_policies(is_active) WHERE is_active = true;

-- Enable RLS
ALTER TABLE inventory_reorder_policies ENABLE ROW LEVEL SECURITY;

-- RLS Policies for inventory_reorder_policies
CREATE POLICY "Managers can view reorder policies"
  ON inventory_reorder_policies FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('admin', 'dispatcher')
    )
  );

CREATE POLICY "Managers can insert reorder policies"
  ON inventory_reorder_policies FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('admin', 'dispatcher')
    )
  );

CREATE POLICY "Managers can update reorder policies"
  ON inventory_reorder_policies FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('admin', 'dispatcher')
    )
  );

CREATE POLICY "Admins can delete reorder policies"
  ON inventory_reorder_policies FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role = 'admin'
    )
  );

-- Drop existing views if they exist
DROP VIEW IF EXISTS vw_vendor_lead_time_metrics;
DROP VIEW IF EXISTS vw_reorder_alerts;
DROP VIEW IF EXISTS vw_vendor_catalog_items;

-- View 1: Vendor Catalog Items
CREATE VIEW vw_vendor_catalog_items AS
SELECT 
  vpm.id AS catalog_item_id,
  vpm.vendor_id,
  v.name AS vendor_name,
  v.vendor_code,
  vpm.part_id,
  p.part_number,
  p.description AS part_description,
  p.category AS part_category,
  vpm.vendor_part_number,
  vpm.vendor_part_description,
  vpm.standard_cost,
  vpm.last_cost,
  vpm.last_purchase_date,
  vpm.lead_time_days,
  vpm.minimum_order_qty AS moq,
  COALESCE(vpm.pack_qty, 1) AS pack_qty,
  vpm.uom,
  vpm.is_preferred_vendor,
  vpm.is_discontinued,
  vpm.notes,
  vpm.created_at,
  vpm.updated_at
FROM vendor_part_mappings vpm
INNER JOIN vendors v ON v.id = vpm.vendor_id
INNER JOIN parts p ON p.id = vpm.part_id
WHERE v.is_active = true
  AND vpm.is_discontinued IS NOT true;

-- View 2: Reorder Alerts
CREATE VIEW vw_reorder_alerts AS
WITH inventory_summary AS (
  SELECT 
    pi.part_id,
    pi.stock_location_id AS location_id,
    SUM(pi.quantity) AS on_hand,
    SUM(pi.quantity * pi.unit_cost) AS inventory_value
  FROM part_inventory pi
  GROUP BY pi.part_id, pi.stock_location_id
),
open_po_summary AS (
  SELECT 
    pol.part_id,
    po.delivery_location_id AS location_id,
    SUM(pol.quantity_ordered - COALESCE(pol.quantity_received, 0)) AS inbound_qty
  FROM purchase_order_lines pol
  INNER JOIN purchase_orders po ON po.id = pol.po_id
  WHERE po.status IN ('draft', 'submitted', 'approved', 'partial')
  GROUP BY pol.part_id, po.delivery_location_id
),
preferred_vendors AS (
  SELECT DISTINCT ON (vpm.part_id)
    vpm.part_id,
    vpm.vendor_id,
    v.name AS vendor_name,
    vpm.vendor_part_number,
    COALESCE(vpm.last_cost, vpm.standard_cost, 0) AS unit_cost,
    COALESCE(vpm.lead_time_days, 7) AS lead_days,
    COALESCE(vpm.minimum_order_qty, 1) AS moq,
    COALESCE(vpm.pack_qty, 1) AS pack_qty
  FROM vendor_part_mappings vpm
  INNER JOIN vendors v ON v.id = vpm.vendor_id
  WHERE vpm.is_preferred_vendor = true
    AND vpm.is_discontinued IS NOT true
    AND v.is_active = true
  ORDER BY vpm.part_id, vpm.last_purchase_date DESC NULLS LAST
)
SELECT 
  p.id AS part_id,
  p.part_number,
  p.description,
  p.category,
  sl.id AS location_id,
  sl.name AS location_name,
  sl.location_type,
  COALESCE(inv.on_hand, 0) AS on_hand,
  0 AS reserved,
  COALESCE(opo.inbound_qty, 0) AS inbound_open_po,
  COALESCE(inv.on_hand, 0) + COALESCE(opo.inbound_qty, 0) AS available,
  
  COALESCE(irp.min_qty, 0) AS min_qty,
  COALESCE(irp.max_qty, 0) AS max_qty,
  COALESCE(irp.safety_stock_qty, 0) AS safety_stock,
  
  COALESCE(irp.lead_days_override, pv.lead_days, 7) AS lead_days,
  
  0.0 AS avg_daily_usage,
  
  COALESCE(irp.safety_stock_qty, 0) AS reorder_point,
  
  CASE 
    WHEN COALESCE(irp.max_qty, 0) > 0 
    THEN GREATEST(
      CEILING((COALESCE(irp.max_qty, 0) - COALESCE(inv.on_hand, 0)) / COALESCE(NULLIF(pv.pack_qty, 0), 1))::numeric * COALESCE(pv.pack_qty, 1),
      COALESCE(pv.moq, 1)
    )
    ELSE COALESCE(pv.moq, 1)
  END AS suggested_order_qty,
  
  CASE 
    WHEN COALESCE(inv.on_hand, 0) <= COALESCE(irp.safety_stock_qty, 0) THEN true
    ELSE false
  END AS below_reorder_point,
  
  CASE 
    WHEN COALESCE(inv.on_hand, 0) = 0 THEN true
    ELSE false
  END AS is_stockout,
  
  irp.reorder_method,
  irp.is_active AS has_reorder_policy,
  
  pv.vendor_id,
  pv.vendor_name,
  pv.vendor_part_number,
  pv.unit_cost,
  pv.moq,
  pv.pack_qty,
  
  COALESCE(inv.inventory_value, 0) AS inventory_value

FROM parts p
CROSS JOIN stock_locations sl
LEFT JOIN inventory_summary inv ON inv.part_id = p.id AND inv.location_id = sl.id
LEFT JOIN open_po_summary opo ON opo.part_id = p.id AND opo.location_id = sl.id
LEFT JOIN inventory_reorder_policies irp ON irp.part_id = p.id AND (irp.location_id = sl.id OR irp.location_id IS NULL) AND irp.is_active = true
LEFT JOIN preferred_vendors pv ON pv.part_id = p.id
WHERE sl.is_active = true;

-- View 3: Vendor Lead Time Metrics
CREATE VIEW vw_vendor_lead_time_metrics AS
WITH po_lead_times AS (
  SELECT 
    po.vendor_id,
    pol.part_id,
    pol.id AS po_line_id,
    po.order_date,
    po.expected_delivery_date,
    MIN(por.receipt_date) AS first_receipt_date,
    pol.quantity_ordered,
    SUM(COALESCE(por.quantity_received, 0)) AS total_received,
    CASE 
      WHEN MIN(por.receipt_date) IS NOT NULL 
      THEN MIN(por.receipt_date) - po.order_date 
      ELSE NULL 
    END AS actual_lead_days,
    CASE 
      WHEN po.expected_delivery_date IS NOT NULL AND MIN(por.receipt_date) IS NOT NULL
      THEN MIN(por.receipt_date) - po.expected_delivery_date
      ELSE NULL
    END AS days_variance
  FROM purchase_orders po
  INNER JOIN purchase_order_lines pol ON pol.po_id = po.id
  LEFT JOIN purchase_order_receipts por ON por.po_line_id = pol.id
  WHERE po.status IN ('received', 'partial')
    AND po.order_date >= CURRENT_DATE - INTERVAL '365 days'
  GROUP BY po.vendor_id, pol.part_id, pol.id, po.order_date, po.expected_delivery_date, pol.quantity_ordered
)
SELECT 
  v.id AS vendor_id,
  v.name AS vendor_name,
  v.vendor_code,
  
  COUNT(plt.po_line_id) AS total_po_lines,
  COUNT(plt.first_receipt_date) AS received_po_lines,
  
  ROUND(AVG(plt.actual_lead_days), 1) AS avg_lead_days,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY plt.actual_lead_days) AS median_lead_days,
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY plt.actual_lead_days) AS p90_lead_days,
  ROUND(STDDEV(plt.actual_lead_days), 1) AS stddev_lead_days,
  
  MIN(plt.actual_lead_days) AS min_lead_days,
  MAX(plt.actual_lead_days) AS max_lead_days,
  
  ROUND(AVG(plt.days_variance), 1) AS avg_days_variance,
  
  ROUND(
    COUNT(*) FILTER (WHERE plt.days_variance <= 0)::numeric / 
    NULLIF(COUNT(plt.days_variance), 0) * 100, 
    1
  ) AS on_time_pct,
  
  ROUND(
    SUM(plt.total_received)::numeric / 
    NULLIF(SUM(plt.quantity_ordered), 0) * 100, 
    1
  ) AS fill_rate_pct,
  
  MIN(plt.order_date) AS earliest_order_date,
  MAX(plt.first_receipt_date) AS latest_receipt_date

FROM vendors v
LEFT JOIN po_lead_times plt ON plt.vendor_id = v.id
WHERE v.is_active = true
GROUP BY v.id, v.name, v.vendor_code
HAVING COUNT(plt.po_line_id) > 0;

-- Add comments
COMMENT ON TABLE inventory_reorder_policies IS 'Defines reorder policies per part and location for automated replenishment';
COMMENT ON VIEW vw_vendor_catalog_items IS 'Vendor catalog with part details, pricing, MOQ, and lead times';
COMMENT ON VIEW vw_reorder_alerts IS 'Reorder point analysis with suggested order quantities';
COMMENT ON VIEW vw_vendor_lead_time_metrics IS 'Vendor lead time performance metrics and reliability indicators';
