/*
  # Allow Admins to View All Time Logs

  The current RLS policy only allows users to view their own time logs.
  For BI reports (Labor Efficiency, Payroll, etc.), admins need to see all staff time logs.

  This migration adds a policy that allows admins to view all time logs.
*/

-- Drop the restrictive policy
DROP POLICY IF EXISTS "Users can view own time logs" ON public.time_logs;

-- Create new policy: Users can view own OR admins can view all
CREATE POLICY "Users can view own time logs or admins view all"
  ON public.time_logs
  FOR SELECT
  TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = (SELECT auth.uid())
      AND profiles.role = 'admin'
    )
  );
