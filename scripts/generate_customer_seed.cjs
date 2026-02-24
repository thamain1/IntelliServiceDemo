

const fs = require('fs');
const path = require('path');
const readline = require('readline');

async function generateSql() {
  const inputPath = path.join(__dirname, '../../docs/DunawayData/payzer_customers_geocoded_final_v2.csv');
  const outputPath = path.join(__dirname, '../project/supabase/seeds/seed_dunaway_customers.sql');

  const fileStream = fs.createReadStream(inputPath);
  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity
  });

  let isHeader = true;
  const sqlStatements = [];
  
  // Header for SQL file
  sqlStatements.push(`/*
  # Seed Real Customer Data
  # Generated from payzer_customers_geocoded_final_v2.csv
*/

-- Create temporary table for import
CREATE TEMP TABLE IF NOT EXISTS temp_customers_import (
  customer_number text,
  display_name text,
  email text,
  mobile_phone text,
  home_phone text,
  address text,
  address2 text,
  city text,
  state text,
  zip text,
  latitude numeric,
  longitude numeric,
  geocode_status text
);

-- Clear temp table
TRUNCATE temp_customers_import;

-- Insert data
INSERT INTO temp_customers_import (customer_number, display_name, email, mobile_phone, home_phone, address, address2, city, state, zip, latitude, longitude, geocode_status) VALUES
`);

  let count = 0;
  let batch = [];
  const BATCH_SIZE = 1000;

  for await (const line of rl) {
    if (isHeader) {
      isHeader = false;
      continue;
    }

    // Simple CSV parser (handles quoted strings)
    const matches = line.match(/(".*?"|[^",\s]+)(?=\s*,|\s*$)/g) || [];
    // Fallback split if regex fails or simple split is needed (complex CSV parsing is better with a lib, but we'll try a robust split) 
    
    // Better CSV split that respects quotes
    const row = [];
    let currentToken = '';
    let insideQuotes = false;
    
    for (let i = 0; i < line.length; i++) {
      const char = line[i];
      if (char === '"') {
        insideQuotes = !insideQuotes;
      } else if (char === ',' && !insideQuotes) {
        row.push(currentToken);
        currentToken = '';
      } else {
        currentToken += char;
      }
    }
    row.push(currentToken); // Push last token

    // Map columns based on CSV header:
    // 0:CUSTOMER_NUMBER, 1:DISPLAY_NAME, 2:EMAIL, 3:MOBILE_PHONE, 4:HOME_PHONE, 
    // 5:ADDRESS, 6:ADDRESS2, 7:CITY, 8:STATE, 9:ZIP, 
    // 10:FULL_ADDRESS, 11:PLACE_ID, 12:LATITUDE, 13:LONGITUDE, 14:GEOCODE_STATUS
    
    const customer_number = row[0]?.trim() || '';
    const name = (row[1]?.trim() || '').replace(/'/g, "''"); // Escape single quotes
    const email = (row[2]?.trim() || '').replace(/'/g, "''");
    const mobile = (row[3]?.trim() || '').replace(/'/g, "''");
    const home = (row[4]?.trim() || '').replace(/'/g, "''");
    const address = (row[5]?.trim() || '').replace(/'/g, "''");
    const address2 = (row[6]?.trim() || '').replace(/'/g, "''");
    const city = (row[7]?.trim() || '').replace(/'/g, "''");
    const state = (row[8]?.trim() || '').replace(/'/g, "''");
    const zip = (row[9]?.trim() || '').replace(/'/g, "''");
    
    let lat = row[12]?.trim();
    let lng = row[13]?.trim();
    const status = row[14]?.trim();

    // Validate Lat/Long
    if (!lat || lat === '' || isNaN(parseFloat(lat))) lat = 'NULL';
    if (!lng || lng === '' || isNaN(parseFloat(lng))) lng = 'NULL';

    const values = `('${customer_number}', '${name}', '${email}', '${mobile}', '${home}', '${address}', '${address2}', '${city}', '${state}', '${zip}', ${lat}, ${lng}, '${status}')`;
    batch.push(values);
    count++;
  }

  // Join all values with commas
  sqlStatements.push(batch.join(',\n'));
  sqlStatements.push(';\n');

  // Add the UPSERT logic
  sqlStatements.push(`
-- Insert into main customers table from temp table
INSERT INTO customers (
  external_customer_id,
  name,
  email,
  phone,
  address,
  city,
  state,
  zip_code,
  latitude,
  longitude,
  geocode_source,
  created_at,
  updated_at
)
SELECT
  customer_number,
  display_name,
  NULLIF(email, ''),
  COALESCE(NULLIF(mobile_phone, ''), NULLIF(home_phone, '')),
  CASE WHEN address2 IS NOT NULL AND address2 != '' THEN address || ' ' || address2 ELSE address END,
  city,
  state,
  zip,
  latitude,
  longitude,
  CASE WHEN latitude IS NOT NULL THEN 'payzer_import' ELSE NULL END,
  NOW(),
  NOW()
FROM temp_customers_import
ON CONFLICT (id) DO NOTHING; 
-- Note: Ideally we'd upsert on external_customer_id if it was unique constraint, 
-- but since we don't strictly enforce that in schema, we rely on new inserts.
-- If you need to avoid dupes based on name/email, we can modify this.

-- Clean up
DROP TABLE temp_customers_import;

-- Summary
DO $$
DECLARE
  v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count FROM customers WHERE geocode_source = 'payzer_import';
  RAISE NOTICE 'Imported % customers from Payzer export.', v_count;
END $$
`);

  // Ensure directory exists
  const dir = path.dirname(outputPath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }

  fs.writeFileSync(outputPath, sqlStatements.join(''));
  console.log(`Generated SQL at ${outputPath} with ${count} records.`);
}

generateSql();
