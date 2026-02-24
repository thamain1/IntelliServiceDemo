/*
  # Fix Activity Log Column Names in Code Triggers

  The activity_log table uses:
  - user_id (not performed_by)
  - details (jsonb, not description)

  This migration fixes the check_ticket_code_flags function to use correct columns.
*/

-- Fix the function to use correct activity_log column names
CREATE OR REPLACE FUNCTION check_ticket_code_flags()
RETURNS TRIGGER AS $$
DECLARE
    problem_triggers_sales BOOLEAN := FALSE;
    resolution_triggers_sales BOOLEAN := FALSE;
    resolution_triggers_urgent BOOLEAN := FALSE;
    is_gas_leak BOOLEAN := FALSE;
BEGIN
    -- Check problem code flags
    IF NEW.problem_code IS NOT NULL THEN
        SELECT
            COALESCE(triggers_sales_lead, FALSE),
            COALESCE(is_critical_safety, FALSE)
        INTO problem_triggers_sales, is_gas_leak
        FROM standard_codes
        WHERE code = NEW.problem_code;
    END IF;

    -- Check resolution code flags
    IF NEW.resolution_code IS NOT NULL THEN
        SELECT
            COALESCE(triggers_sales_lead, FALSE),
            COALESCE(triggers_urgent_review, FALSE)
        INTO resolution_triggers_sales, resolution_triggers_urgent
        FROM standard_codes
        WHERE code = NEW.resolution_code;
    END IF;

    -- Set sales opportunity flag
    IF problem_triggers_sales OR resolution_triggers_sales THEN
        NEW.sales_opportunity_flag := TRUE;
    END IF;

    -- Set urgent review flag
    IF resolution_triggers_urgent THEN
        NEW.urgent_review_flag := TRUE;
    END IF;

    -- Log activity if flags were set (only on changes)
    IF NEW.sales_opportunity_flag = TRUE AND
       (OLD.sales_opportunity_flag IS NULL OR OLD.sales_opportunity_flag = FALSE) THEN
        INSERT INTO activity_log (
            entity_type,
            entity_id,
            action,
            user_id,
            details
        ) VALUES (
            'ticket',
            NEW.id,
            'sales_opportunity_flagged',
            COALESCE(NEW.assigned_to, auth.uid()),
            jsonb_build_object(
                'description', 'Sales opportunity flagged based on code',
                'problem_code', NEW.problem_code,
                'resolution_code', NEW.resolution_code
            )
        );
    END IF;

    IF NEW.urgent_review_flag = TRUE AND
       (OLD.urgent_review_flag IS NULL OR OLD.urgent_review_flag = FALSE) THEN
        INSERT INTO activity_log (
            entity_type,
            entity_id,
            action,
            user_id,
            details
        ) VALUES (
            'ticket',
            NEW.id,
            'urgent_review_flagged',
            COALESCE(NEW.assigned_to, auth.uid()),
            jsonb_build_object(
                'description', 'Urgent review required - Temporary fix applied',
                'resolution_code', NEW.resolution_code
            )
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
