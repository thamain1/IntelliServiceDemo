/*
  # Enable Public Access for Estimate Portal
  
  1. Changes
    - Add public SELECT policies for estimates, estimate_line_items, and customers
    - These policies allow unauthenticated access when there's a valid public link
    - Uses a helper function to check if an estimate has a valid (non-expired, non-revoked) public link
  
  2. Security
    - Only allows SELECT (read-only) access
    - Only works for estimates with active public links
    - Customers table limited to records referenced by publicly-accessible estimates
*/

-- Helper function to check if an estimate has a valid public link
CREATE OR REPLACE FUNCTION public.estimate_has_valid_public_link(estimate_uuid uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM estimate_public_links 
    WHERE estimate_id = estimate_uuid
      AND revoked_at IS NULL
      AND (expires_at IS NULL OR expires_at > now())
  );
$$;

-- Public SELECT policy for estimates (via public links)
CREATE POLICY "Public can view estimates with valid links"
  ON estimates FOR SELECT
  TO anon
  USING (public.estimate_has_valid_public_link(id));

-- Public SELECT policy for estimate_line_items (via public links)
CREATE POLICY "Public can view line items for estimates with valid links"
  ON estimate_line_items FOR SELECT
  TO anon
  USING (public.estimate_has_valid_public_link(estimate_id));

-- Public SELECT policy for customers (via public links)
CREATE POLICY "Public can view customers for estimates with valid links"
  ON customers FOR SELECT
  TO anon
  USING (
    EXISTS (
      SELECT 1 
      FROM estimates e
      WHERE e.customer_id = customers.id
        AND public.estimate_has_valid_public_link(e.id)
    )
  );
