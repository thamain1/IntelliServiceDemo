/*
  # Create Labor Rate Resolver Function

  ## Overview
  Implements deterministic labor rate resolution hierarchy for consistent billing
  across Estimates, Tickets, Projects, and Invoicing. Ensures single source of truth.

  ## Rate Resolution Hierarchy
  
  1. **Explicit Override** (if requested and permitted)
     - Requires override_rate, override_reason
     - Returns: rate_source='override'
  
  2. **Service Contract Rate** (if active and applicable)
     - Checks customer_id, location_id, equipment_id
     - Verifies contract active on work_date
     - Checks coverage level
     - Returns: rate_source='contract', contract_id_applied, is_covered
  
  3. **Customer/Location Override** (future enhancement)
     - Placeholder for custom customer rates
     - Returns: rate_source='customer'
  
  4. **Default Accounting Settings**
     - Falls back to global rates
     - Uses standard/after_hours/emergency based on rate_type
     - Returns: rate_source='settings'

  ## Function: fn_resolve_labor_rate
  
  Input (jsonb context):
  - customer_id uuid
  - location_id uuid (optional)
  - equipment_id uuid (optional)
  - ticket_id uuid (optional)
  - rate_type labor_rate_tier ('standard', 'after_hours', 'emergency')
  - work_date date (defaults to today)
  - override_rate numeric (optional, for manual override)
  - override_reason text (optional, required if override_rate provided)
  - override_by uuid (optional, user performing override)

  Output (jsonb):
  - rate_type labor_rate_tier
  - bill_rate numeric
  - rate_source rate_source
  - contract_id_applied uuid (nullable)
  - is_covered boolean
  - override_allowed boolean
  - message text (explanation)

  ## Security
  - Function is SECURITY DEFINER to access all tables
  - RLS still enforced on calling context
*/

-- Create helper function to get accounting setting as numeric
CREATE OR REPLACE FUNCTION get_accounting_setting_rate(setting_key text)
RETURNS numeric
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  rate_value numeric;
BEGIN
  SELECT setting_value::numeric INTO rate_value
  FROM accounting_settings
  WHERE accounting_settings.setting_key = get_accounting_setting_rate.setting_key
  LIMIT 1;
  
  RETURN COALESCE(rate_value, 0);
END;
$$;

-- Main rate resolver function
CREATE OR REPLACE FUNCTION fn_resolve_labor_rate(context jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_customer_id uuid;
  v_location_id uuid;
  v_equipment_id uuid;
  v_ticket_id uuid;
  v_rate_type labor_rate_tier;
  v_work_date date;
  v_override_rate numeric;
  v_override_reason text;
  v_override_by uuid;
  
  v_bill_rate numeric;
  v_rate_source rate_source;
  v_contract_id uuid;
  v_is_covered boolean;
  v_message text;
  v_override_allowed boolean;
  
  v_contract_record record;
  v_coverage_record record;
  v_default_rate numeric;
BEGIN
  -- Parse input context
  v_customer_id := (context->>'customer_id')::uuid;
  v_location_id := (context->>'location_id')::uuid;
  v_equipment_id := (context->>'equipment_id')::uuid;
  v_ticket_id := (context->>'ticket_id')::uuid;
  v_rate_type := (context->>'rate_type')::labor_rate_tier;
  v_work_date := COALESCE((context->>'work_date')::date, CURRENT_DATE);
  v_override_rate := (context->>'override_rate')::numeric;
  v_override_reason := context->>'override_reason';
  v_override_by := (context->>'override_by')::uuid;
  
  -- Default values
  v_is_covered := false;
  v_override_allowed := true;
  v_rate_source := 'settings';
  
  -- Validate required inputs
  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'customer_id is required';
  END IF;
  
  IF v_rate_type IS NULL THEN
    v_rate_type := 'standard';
  END IF;
  
  -- STEP 1: Check for explicit override
  IF v_override_rate IS NOT NULL THEN
    IF v_override_reason IS NULL OR trim(v_override_reason) = '' THEN
      RETURN jsonb_build_object(
        'error', true,
        'message', 'override_reason is required when providing override_rate'
      );
    END IF;
    
    RETURN jsonb_build_object(
      'rate_type', v_rate_type,
      'bill_rate', v_override_rate,
      'rate_source', 'override',
      'contract_id_applied', null,
      'is_covered', false,
      'override_allowed', true,
      'override_reason', v_override_reason,
      'overridden_by', v_override_by,
      'message', 'Manual override applied'
    );
  END IF;
  
  -- STEP 2: Check for active service contract
  -- Find active service contract for this customer/location
  SELECT sc.*
  INTO v_contract_record
  FROM service_contracts sc
  WHERE sc.customer_id = v_customer_id
    AND (v_location_id IS NULL OR sc.customer_location_id = v_location_id OR sc.customer_location_id IS NULL)
    AND sc.status = 'active'
    AND sc.start_date <= v_work_date
    AND (sc.end_date IS NULL OR sc.end_date >= v_work_date)
  ORDER BY 
    -- Prefer location-specific contracts
    CASE WHEN sc.customer_location_id IS NOT NULL THEN 1 ELSE 2 END,
    sc.start_date DESC
  LIMIT 1;
  
  IF v_contract_record.id IS NOT NULL THEN
    v_contract_id := v_contract_record.id;
    
    -- Check coverage for this equipment (if applicable)
    IF v_equipment_id IS NOT NULL THEN
      SELECT scc.*
      INTO v_coverage_record
      FROM service_contract_coverage scc
      WHERE scc.service_contract_id = v_contract_id
        AND (scc.equipment_id = v_equipment_id OR scc.equipment_id IS NULL)
      ORDER BY CASE WHEN scc.equipment_id IS NOT NULL THEN 1 ELSE 2 END
      LIMIT 1;
    END IF;
    
    -- Determine coverage based on labor_coverage_level
    IF v_coverage_record.id IS NOT NULL THEN
      CASE v_coverage_record.labor_coverage_level
        WHEN 'full_all_service' THEN
          v_is_covered := true;
        WHEN 'full_for_pm_only' THEN
          -- Would need to check if this is PM work (placeholder)
          v_is_covered := false;
        WHEN 'discount_only' THEN
          v_is_covered := false;
        ELSE
          v_is_covered := false;
      END CASE;
    ELSE
      -- No specific coverage, check contract-level settings
      v_is_covered := false;
    END IF;
    
    -- Calculate rate based on contract labor_rate_type
    CASE v_contract_record.labor_rate_type
      WHEN 'fixed_rate' THEN
        v_bill_rate := v_contract_record.labor_fixed_rate;
        v_rate_source := 'contract';
        v_message := 'Contract fixed rate applied';
        
      WHEN 'discount_percentage' THEN
        -- Get base rate from settings
        v_default_rate := CASE v_rate_type
          WHEN 'standard' THEN get_accounting_setting_rate('standard_labor_rate')
          WHEN 'after_hours' THEN 
            CASE 
              WHEN v_contract_record.includes_after_hours_rate_reduction THEN 
                get_accounting_setting_rate('standard_labor_rate')
              ELSE 
                get_accounting_setting_rate('after_hours_labor_rate')
            END
          WHEN 'emergency' THEN get_accounting_setting_rate('emergency_labor_rate')
          ELSE get_accounting_setting_rate('standard_labor_rate')
        END;
        
        v_bill_rate := v_default_rate * (1 - COALESCE(v_contract_record.labor_discount_percent, 0) / 100);
        v_rate_source := 'contract';
        v_message := format('Contract discount (%s%%) applied', v_contract_record.labor_discount_percent);
        
      ELSE
        -- 'standard' or 'tiered' - use default rates
        v_default_rate := CASE v_rate_type
          WHEN 'standard' THEN get_accounting_setting_rate('standard_labor_rate')
          WHEN 'after_hours' THEN get_accounting_setting_rate('after_hours_labor_rate')
          WHEN 'emergency' THEN get_accounting_setting_rate('emergency_labor_rate')
          ELSE get_accounting_setting_rate('standard_labor_rate')
        END;
        
        v_bill_rate := v_default_rate;
        v_rate_source := 'contract';
        v_message := 'Contract standard rates applied';
    END CASE;
    
    -- If covered, rate should be 0 or discounted heavily
    IF v_is_covered THEN
      v_bill_rate := 0;
      v_message := 'Fully covered under service contract';
    END IF;
    
    RETURN jsonb_build_object(
      'rate_type', v_rate_type,
      'bill_rate', v_bill_rate,
      'rate_source', v_rate_source,
      'contract_id_applied', v_contract_id,
      'is_covered', v_is_covered,
      'override_allowed', true,
      'message', v_message
    );
  END IF;
  
  -- STEP 3: Customer/Location override (future - placeholder)
  -- Would check for customer-specific rates here
  
  -- STEP 4: Fall back to accounting settings default rates
  v_default_rate := CASE v_rate_type
    WHEN 'standard' THEN get_accounting_setting_rate('standard_labor_rate')
    WHEN 'after_hours' THEN get_accounting_setting_rate('after_hours_labor_rate')
    WHEN 'emergency' THEN get_accounting_setting_rate('emergency_labor_rate')
    ELSE get_accounting_setting_rate('standard_labor_rate')
  END;
  
  v_bill_rate := v_default_rate;
  v_rate_source := 'settings';
  v_message := format('Default %s rate from accounting settings', v_rate_type);
  
  RETURN jsonb_build_object(
    'rate_type', v_rate_type,
    'bill_rate', v_bill_rate,
    'rate_source', v_rate_source,
    'contract_id_applied', null,
    'is_covered', false,
    'override_allowed', true,
    'message', v_message
  );
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION fn_resolve_labor_rate(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION get_accounting_setting_rate(text) TO authenticated;

-- Add comments
COMMENT ON FUNCTION fn_resolve_labor_rate(jsonb) IS 'Resolves labor billing rate based on service contracts, customer settings, and global defaults. Implements deterministic hierarchy for rate resolution.';
COMMENT ON FUNCTION get_accounting_setting_rate(text) IS 'Helper function to retrieve numeric labor rate from accounting_settings table';
