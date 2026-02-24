/*
  # Add item_type Column to Parts Table for Tools Inventory

  This migration adds support for a unified inventory system that can track both
  Parts and Tools using the same underlying tables and logic.

  ## Changes

  1. New Columns on `parts` table:
    - `item_type` (text, NOT NULL, DEFAULT 'part') - Distinguishes between 'part' and 'tool'
    - `is_returnable` (boolean, DEFAULT true) - Whether item can be returned/checked back in
    - `tool_category` (text, NULL) - Optional category specific to tools
    - `asset_tag` (text, NULL) - Optional asset tag for fixed asset tracking

  2. New Indexes:
    - `idx_parts_item_type` - For efficient filtering by item type
    - `idx_parts_asset_tag` - For asset tag lookups

  3. Security:
    - No RLS changes needed (parts table already has appropriate policies)

  ## Notes
    - Existing rows will automatically default to item_type='part'
    - No data migration required - existing parts remain unchanged
    - Tools use the same inventory engine: receiving, transfers, stock levels, serialization
*/

-- Add item_type column to parts table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'parts' AND column_name = 'item_type'
  ) THEN
    ALTER TABLE parts ADD COLUMN item_type text NOT NULL DEFAULT 'part';
  END IF;
END $$;

-- Add check constraint for valid item types
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.check_constraints
    WHERE constraint_name = 'parts_item_type_check'
  ) THEN
    ALTER TABLE parts ADD CONSTRAINT parts_item_type_check 
      CHECK (item_type IN ('part', 'tool'));
  END IF;
END $$;

-- Add is_returnable column (useful for tools that can be checked out/in)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'parts' AND column_name = 'is_returnable'
  ) THEN
    ALTER TABLE parts ADD COLUMN is_returnable boolean NOT NULL DEFAULT true;
  END IF;
END $$;

-- Add tool_category column for tool-specific categorization
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'parts' AND column_name = 'tool_category'
  ) THEN
    ALTER TABLE parts ADD COLUMN tool_category text NULL;
  END IF;
END $$;

-- Add asset_tag column for fixed asset tracking
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'parts' AND column_name = 'asset_tag'
  ) THEN
    ALTER TABLE parts ADD COLUMN asset_tag text NULL;
  END IF;
END $$;

-- Create index for item_type filtering
CREATE INDEX IF NOT EXISTS idx_parts_item_type ON parts(item_type);

-- Create index for asset_tag lookups
CREATE INDEX IF NOT EXISTS idx_parts_asset_tag ON parts(asset_tag) WHERE asset_tag IS NOT NULL;

-- Create view for tools-only items
CREATE OR REPLACE VIEW vw_tools AS
SELECT 
  p.*,
  COALESCE(
    (SELECT SUM(pi.quantity) FROM part_inventory pi WHERE pi.part_id = p.id),
    0
  ) as total_on_hand
FROM parts p
WHERE p.item_type = 'tool';

-- Create view for parts-only items (explicit filter for clarity)
CREATE OR REPLACE VIEW vw_parts AS
SELECT 
  p.*,
  COALESCE(
    (SELECT SUM(pi.quantity) FROM part_inventory pi WHERE pi.part_id = p.id),
    0
  ) as total_on_hand
FROM parts p
WHERE p.item_type = 'part';

-- Create helper function to get items by type with inventory details
CREATE OR REPLACE FUNCTION fn_get_items_by_type(p_item_type text)
RETURNS TABLE(
  id uuid,
  part_number text,
  name text,
  description text,
  manufacturer text,
  category text,
  item_type text,
  is_serialized boolean,
  is_returnable boolean,
  tool_category text,
  asset_tag text,
  unit_price numeric,
  reorder_level integer,
  reorder_point numeric,
  reorder_quantity numeric,
  total_on_hand bigint,
  total_value numeric
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = 'public'
AS $$
  SELECT 
    p.id,
    p.part_number,
    p.name,
    p.description,
    p.manufacturer,
    p.category,
    p.item_type,
    p.is_serialized,
    p.is_returnable,
    p.tool_category,
    p.asset_tag,
    p.unit_price,
    p.reorder_level,
    p.reorder_point,
    p.reorder_quantity,
    COALESCE(SUM(pi.quantity), 0)::bigint as total_on_hand,
    COALESCE(SUM(pi.quantity * COALESCE(pi.unit_cost, p.unit_price)), 0) as total_value
  FROM parts p
  LEFT JOIN part_inventory pi ON pi.part_id = p.id
  WHERE p.item_type = p_item_type
  GROUP BY p.id
  ORDER BY p.name;
$$;
