/*
  # Add Geocoding Support to Customers Table

  1. Changes
    - Add `latitude` and `longitude` columns to customers table for storing coordinates
    - Add `place_id` column for Google Maps Place ID
    - Add `geocoded_at` timestamp to track when geocoding was performed
    - Add `geocode_source` to track how coordinates were obtained (manual, geocoding, gps)
    - Add index on latitude/longitude for spatial queries
  
  2. Migration Strategy
    - Backfill ticket coordinates from customers where customer has coordinates
    - This eliminates redundant geocoding for tickets sharing the same customer
  
  3. Benefits
    - Geocode once per customer address instead of per ticket
    - More efficient API usage
    - Centralized coordinate management
    - Easier to update coordinates when customer address changes
*/

-- Add geocoding fields to customers table
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'customers' AND column_name = 'latitude'
  ) THEN
    ALTER TABLE customers ADD COLUMN latitude decimal(10, 8);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'customers' AND column_name = 'longitude'
  ) THEN
    ALTER TABLE customers ADD COLUMN longitude decimal(11, 8);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'customers' AND column_name = 'place_id'
  ) THEN
    ALTER TABLE customers ADD COLUMN place_id text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'customers' AND column_name = 'geocoded_at'
  ) THEN
    ALTER TABLE customers ADD COLUMN geocoded_at timestamptz;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'customers' AND column_name = 'geocode_source'
  ) THEN
    ALTER TABLE customers ADD COLUMN geocode_source text;
  END IF;
END $$;

-- Create index for spatial queries
CREATE INDEX IF NOT EXISTS idx_customers_coordinates 
  ON customers (latitude, longitude) 
  WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

-- Backfill: Copy any existing ticket coordinates to their customers
-- This preserves any manual geocoding that was done at the ticket level
UPDATE customers c
SET 
  latitude = t.latitude,
  longitude = t.longitude,
  place_id = t.place_id,
  geocoded_at = t.geocoded_at,
  geocode_source = COALESCE(t.geocode_source, 'migrated_from_ticket')
FROM tickets t
WHERE t.customer_id = c.id
  AND t.latitude IS NOT NULL 
  AND t.longitude IS NOT NULL
  AND c.latitude IS NULL;

COMMENT ON COLUMN customers.latitude IS 'Latitude coordinate for customer address';
COMMENT ON COLUMN customers.longitude IS 'Longitude coordinate for customer address';
COMMENT ON COLUMN customers.place_id IS 'Google Maps Place ID for customer address';
COMMENT ON COLUMN customers.geocoded_at IS 'Timestamp when address was geocoded';
COMMENT ON COLUMN customers.geocode_source IS 'Source of coordinates: manual, geocoding, gps, migrated_from_ticket';
