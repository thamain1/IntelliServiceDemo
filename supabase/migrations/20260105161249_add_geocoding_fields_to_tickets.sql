/*
  # Add Geocoding Fields to Tickets Table

  1. Changes
    - Add nullable geocoding fields to tickets table for Google Maps integration
    - Fields: place_id, latitude, longitude, geocoded_at, geocode_source
    - All fields are nullable to maintain backward compatibility
    - No data loss or breaking changes
    
  2. Security
    - RLS policies remain unchanged
    - Existing ticket operations continue to work without modification
    
  3. Notes
    - This is an additive-only migration
    - Existing tickets will have NULL values for these fields
    - New tickets can optionally store geocoding data
    - Fields can be populated via geocoding process without affecting ticket creation
*/

-- Add geocoding fields to tickets table (all nullable for safety)
DO $$
BEGIN
  -- Add place_id if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tickets' AND column_name = 'place_id'
  ) THEN
    ALTER TABLE tickets ADD COLUMN place_id TEXT;
  END IF;

  -- Add latitude if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tickets' AND column_name = 'latitude'
  ) THEN
    ALTER TABLE tickets ADD COLUMN latitude NUMERIC(10, 7);
  END IF;

  -- Add longitude if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tickets' AND column_name = 'longitude'
  ) THEN
    ALTER TABLE tickets ADD COLUMN longitude NUMERIC(10, 7);
  END IF;

  -- Add geocoded_at if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tickets' AND column_name = 'geocoded_at'
  ) THEN
    ALTER TABLE tickets ADD COLUMN geocoded_at TIMESTAMPTZ;
  END IF;

  -- Add geocode_source if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tickets' AND column_name = 'geocode_source'
  ) THEN
    ALTER TABLE tickets ADD COLUMN geocode_source TEXT;
  END IF;
END $$;

-- Create an index on latitude and longitude for efficient spatial queries
CREATE INDEX IF NOT EXISTS idx_tickets_coordinates ON tickets(latitude, longitude)
WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

-- Create an index on geocoded_at for tracking geocoding progress
CREATE INDEX IF NOT EXISTS idx_tickets_geocoded_at ON tickets(geocoded_at)
WHERE geocoded_at IS NOT NULL;
