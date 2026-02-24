/*
  # Store Portal Token for Retrieval

  1. Changes
    - Add `token` column to `estimate_public_links` to store the plain token
    - This allows retrieving the portal URL after sending
    
  2. Security Notes
    - Token is a 64-character random hex string
    - Not as secure as hash-only, but necessary for portal link retrieval
    - Token should be treated as sensitive data
*/

-- Add token column to store plain token for URL generation
ALTER TABLE estimate_public_links
ADD COLUMN IF NOT EXISTS token text;

-- Create index for token lookups (used by portal)
CREATE INDEX IF NOT EXISTS idx_estimate_public_links_token
ON estimate_public_links(token)
WHERE token IS NOT NULL AND revoked_at IS NULL;