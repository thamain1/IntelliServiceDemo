/*
  # Backfill Hold Flags from Existing Updates

  ## Overview
  Sets hold flags on tickets that have existing "needs_parts" or "issue" updates
  but were created before the new hold system was implemented.

  ## Changes
  - Identifies tickets with active needs_parts/issue updates
  - Sets appropriate hold flags (hold_parts_active, hold_issue_active)
  - Sets general hold_active and revisit_required flags
  - Creates corresponding hold records for tracking

  ## Safety
  - Only affects tickets with existing updates but no hold flags
  - Idempotent - safe to run multiple times
  - No data loss
*/

-- Backfill hold_parts_active for tickets with needs_parts updates
UPDATE tickets
SET 
  hold_parts_active = true,
  hold_active = true,
  hold_type = 'parts',
  revisit_required = true,
  updated_at = now()
WHERE id IN (
  SELECT DISTINCT ticket_id
  FROM ticket_updates
  WHERE update_type = 'needs_parts'
  AND ticket_id IN (
    SELECT id FROM tickets
    WHERE status IN ('open', 'scheduled', 'in_progress')
    AND hold_parts_active = false
  )
)
AND hold_parts_active = false;

-- Backfill hold_issue_active for tickets with issue updates
UPDATE tickets
SET 
  hold_issue_active = true,
  hold_active = true,
  hold_type = 'issue',
  revisit_required = true,
  updated_at = now()
WHERE id IN (
  SELECT DISTINCT ticket_id
  FROM ticket_updates
  WHERE update_type = 'issue'
  AND ticket_id IN (
    SELECT id FROM tickets
    WHERE status IN ('open', 'scheduled', 'in_progress')
    AND hold_issue_active = false
  )
)
AND hold_issue_active = false;

-- Create hold records for backfilled tickets with parts needs
INSERT INTO ticket_holds (ticket_id, hold_type, status, summary, created_by, created_at)
SELECT DISTINCT 
  t.id,
  'parts',
  'active',
  'Backfilled from legacy needs_parts update',
  tu.technician_id,
  tu.created_at
FROM tickets t
INNER JOIN ticket_updates tu ON tu.ticket_id = t.id
WHERE t.hold_parts_active = true
  AND tu.update_type = 'needs_parts'
  AND NOT EXISTS (
    SELECT 1 FROM ticket_holds th
    WHERE th.ticket_id = t.id
    AND th.hold_type = 'parts'
    AND th.status = 'active'
  )
ORDER BY tu.created_at DESC;

-- Create hold records for backfilled tickets with issues
INSERT INTO ticket_holds (ticket_id, hold_type, status, summary, created_by, created_at)
SELECT DISTINCT 
  t.id,
  'issue',
  'active',
  'Backfilled from legacy issue update',
  tu.technician_id,
  tu.created_at
FROM tickets t
INNER JOIN ticket_updates tu ON tu.ticket_id = t.id
WHERE t.hold_issue_active = true
  AND tu.update_type = 'issue'
  AND NOT EXISTS (
    SELECT 1 FROM ticket_holds th
    WHERE th.ticket_id = t.id
    AND th.hold_type = 'issue'
    AND th.status = 'active'
  )
ORDER BY tu.created_at DESC;

-- Create parts requests for backfilled tickets (best effort)
INSERT INTO ticket_parts_requests (ticket_id, hold_id, urgency, notes, status, created_by, created_at)
SELECT DISTINCT ON (t.id)
  t.id,
  th.id,
  'medium'::text,
  COALESCE(tu.notes, 'Backfilled from legacy update'),
  'open',
  tu.technician_id,
  tu.created_at
FROM tickets t
INNER JOIN ticket_holds th ON th.ticket_id = t.id AND th.hold_type = 'parts' AND th.status = 'active'
INNER JOIN ticket_updates tu ON tu.ticket_id = t.id AND tu.update_type = 'needs_parts'
WHERE t.hold_parts_active = true
  AND NOT EXISTS (
    SELECT 1 FROM ticket_parts_requests tpr
    WHERE tpr.ticket_id = t.id
    AND tpr.status = 'open'
  )
ORDER BY t.id, tu.created_at DESC;

-- Create issue reports for backfilled tickets (best effort)
INSERT INTO ticket_issue_reports (ticket_id, hold_id, category, severity, description, status, created_by, created_at)
SELECT DISTINCT ON (t.id)
  t.id,
  th.id,
  'other'::text,
  'medium'::text,
  COALESCE(tu.notes, 'Backfilled from legacy update'),
  'open',
  tu.technician_id,
  tu.created_at
FROM tickets t
INNER JOIN ticket_holds th ON th.ticket_id = t.id AND th.hold_type = 'issue' AND th.status = 'active'
INNER JOIN ticket_updates tu ON tu.ticket_id = t.id AND tu.update_type = 'issue'
WHERE t.hold_issue_active = true
  AND NOT EXISTS (
    SELECT 1 FROM ticket_issue_reports tir
    WHERE tir.ticket_id = t.id
    AND tir.status IN ('open', 'investigating')
  )
ORDER BY t.id, tu.created_at DESC;
