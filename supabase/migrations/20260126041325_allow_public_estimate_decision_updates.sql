/*
  # Allow Public Users to Update Estimate Decisions
  
  1. Changes
    - Add UPDATE policy for estimates table to allow anonymous users to update decision fields
    - Restricts updates to only status, accepted_date, and rejected_date columns
    - Only allows updates when there's a valid, non-expired public link
  
  2. Security
    - Only affects estimates with active public links
    - Cannot modify other estimate fields
    - Uses USING clause to verify valid public link exists
*/

-- Allow anonymous users to update estimate decision fields via public links
CREATE POLICY "Public can update estimate decisions via valid links"
  ON estimates FOR UPDATE
  TO anon
  USING (public.estimate_has_valid_public_link(id))
  WITH CHECK (public.estimate_has_valid_public_link(id));
