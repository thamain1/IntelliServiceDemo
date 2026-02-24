# Labor Rate Management System

## Overview
Comprehensive labor rate management with snapshot-based billing, service contract integration, and controlled overrides. Ensures consistent billing across Estimates, Tickets, Projects, and Invoicing regardless of future rate changes.

## Core Principles

### 1. Single Source of Truth
- **Accounting Settings** stores global labor rates (standard, after-hours, emergency)
- **Service Contracts** define customer-specific rates and coverage
- **Rate Snapshots** prevent billing drift when rates change

### 2. Deterministic Rate Hierarchy
1. **Explicit Override** (requires reason + approval)
2. **Service Contract Rate** (if active and applicable)
3. **Customer/Location Override** (future enhancement)
4. **Default Accounting Settings**

### 3. Immutable Snapshots
Once a rate is applied to a time entry or estimate line, it's frozen. Historical data never changes when settings update.

## Database Schema

### New Fields in `time_logs`

```sql
rate_tier               labor_rate_tier  -- 'standard', 'after_hours', 'emergency' (existed)
billing_rate_applied    numeric          -- Snapshot of rate (existed)
rate_source             rate_source      -- 'settings', 'contract', 'customer', 'override'
contract_id_applied     uuid             -- FK to service_contracts
is_covered              boolean          -- Covered by service contract?
override_reason         text             -- Explanation for manual override
overridden_by           uuid             -- FK to profiles (who overrode)
overridden_at           timestamptz      -- When override occurred
```

### New Fields in `estimate_line_items`

```sql
rate_type               labor_rate_tier  -- 'standard', 'after_hours', 'emergency'
rate_source             rate_source      -- Where rate came from
bill_rate               numeric          -- Snapshot of billing rate
contract_id_applied     uuid             -- FK to service_contracts
is_covered              boolean          -- Would be covered?
override_reason         text             -- Explanation for override
overridden_by           uuid             -- Who overrode
overridden_at           timestamptz      -- When override occurred
```

### Enums

```sql
-- Already existed
labor_rate_tier: 'standard', 'after_hours', 'emergency'

-- New
rate_source: 'settings', 'contract', 'customer', 'override'
```

## Rate Resolution Function

### `fn_resolve_labor_rate(context jsonb)`

**Input Context:**
```json
{
  "customer_id": "uuid (required)",
  "location_id": "uuid (optional)",
  "equipment_id": "uuid (optional)",
  "ticket_id": "uuid (optional)",
  "rate_type": "standard|after_hours|emergency (default: standard)",
  "work_date": "YYYY-MM-DD (default: today)",
  "override_rate": "numeric (optional)",
  "override_reason": "text (required if override_rate)",
  "override_by": "uuid (optional)"
}
```

**Output:**
```json
{
  "rate_type": "standard|after_hours|emergency",
  "bill_rate": 120.00,
  "rate_source": "settings|contract|customer|override",
  "contract_id_applied": "uuid or null",
  "is_covered": false,
  "override_allowed": true,
  "message": "Explanation of rate applied"
}
```

### Resolution Logic

#### Step 1: Explicit Override
```sql
IF override_rate IS NOT NULL THEN
  IF override_reason IS NULL THEN
    RETURN error
  END IF
  RETURN override_rate with rate_source='override'
END IF
```

#### Step 2: Service Contract
```sql
-- Find active contract for customer/location on work_date
SELECT * FROM service_contracts
WHERE customer_id = ?
  AND (location_id = ? OR location_id IS NULL)
  AND status = 'active'
  AND start_date <= work_date
  AND (end_date IS NULL OR end_date >= work_date)
ORDER BY location_specificity, start_date DESC
LIMIT 1

-- Check equipment coverage
SELECT * FROM service_contract_coverage
WHERE service_contract_id = ?
  AND (equipment_id = ? OR equipment_id IS NULL)

-- Apply contract rate based on labor_rate_type
CASE contract.labor_rate_type
  WHEN 'fixed_rate' THEN
    bill_rate = contract.labor_fixed_rate
  WHEN 'discount_percentage' THEN
    bill_rate = base_rate * (1 - contract.labor_discount_percent / 100)
  ELSE
    bill_rate = base_rate
END CASE

-- If fully covered
IF labor_coverage_level = 'full_all_service' THEN
  bill_rate = 0
  is_covered = true
END IF
```

#### Step 3: Customer Override
```sql
-- Future enhancement
-- Check for customer-specific rates
```

#### Step 4: Default Settings
```sql
-- Fallback to accounting_settings
SELECT setting_value FROM accounting_settings
WHERE setting_key = CASE rate_type
  WHEN 'standard' THEN 'standard_labor_rate'
  WHEN 'after_hours' THEN 'after_hours_labor_rate'
  WHEN 'emergency' THEN 'emergency_labor_rate'
END
```

## Service Layer: RateService.ts

### Key Methods

#### `resolveLaborRate(context): Promise<ResolvedRate>`
Calls the RPC function and returns typed result.

```typescript
const resolved = await RateService.resolveLaborRate({
  customerId: ticket.customer_id,
  locationId: ticket.location_id,
  equipmentId: ticket.equipment_id,
  rateType: 'standard',
  workDate: '2024-01-15',
});

console.log(resolved.billRate); // 120.00
console.log(resolved.rateSource); // 'contract'
console.log(resolved.isCovered); // false
```

#### `getDefaultRate(rateType): Promise<number>`
Quick lookup of global rate without resolution logic.

```typescript
const standardRate = await RateService.getDefaultRate('standard'); // 120
const afterHoursRate = await RateService.getDefaultRate('after_hours'); // 160
```

#### `createSnapshot(resolvedRate): LaborRateSnapshot`
Converts resolved rate to snapshot format for storage.

```typescript
const resolved = await RateService.resolveLaborRate(context);
const snapshot = RateService.createSnapshot(resolved);

// Store in time_logs or estimate_line_items
await supabase.from('time_logs').insert({
  ...otherFields,
  rate_tier: snapshot.rateType,
  billing_rate_applied: snapshot.billRate,
  rate_source: snapshot.rateSource,
  contract_id_applied: snapshot.contractIdApplied,
  is_covered: snapshot.isCovered,
});
```

#### `verifyRateSnapshot(timeLogId): Promise<{isValid, currentRate, snapshotRate}>`
Compares snapshot to current resolution (useful for auditing).

```typescript
const verification = await RateService.verifyRateSnapshot(timeLogId);

if (!verification.isValid) {
  console.warn(
    `Rate drift detected: snapshot=${verification.snapshotRate}, current=${verification.currentRate}`
  );
}
```

## Integration Guide

### Estimates

**When Adding Labor Line:**
```typescript
// 1. Resolve rate
const resolved = await RateService.resolveLaborRate({
  customerId: estimate.customer_id,
  locationId: estimate.location_id,
  rateType: 'standard',
});

// 2. Create estimate line item
await supabase.from('estimate_line_items').insert({
  estimate_id: estimateId,
  item_type: 'labor',
  description: 'Labor hours',
  quantity: hours,
  unit_price: resolved.billRate, // This is the snapshot
  bill_rate: resolved.billRate,
  rate_type: resolved.rateType,
  rate_source: resolved.rateSource,
  contract_id_applied: resolved.contractIdApplied,
  is_covered: resolved.isCovered,
  line_total: hours * resolved.billRate,
});
```

**Allowing Override:**
```typescript
// User clicks "Override Rate"
const resolved = await RateService.resolveLaborRate({
  customerId: estimate.customer_id,
  rateType: 'standard',
  overrideRate: 150.00,
  overrideReason: 'Customer negotiation - approved by manager',
  overrideBy: currentUserId,
});

// rate_source will be 'override'
```

### Tickets/Time Logs

**When Closing Time Entry:**
```typescript
// 1. Get ticket context
const { data: ticket } = await supabase
  .from('tickets')
  .select('customer_id, location_id, equipment_id')
  .eq('id', ticketId)
  .single();

// 2. Determine rate type (e.g., based on time of day)
const clockInTime = new Date(timeLog.clock_in_time);
const hour = clockInTime.getHours();
const rateType = hour >= 17 || hour < 8 ? 'after_hours' : 'standard';

// 3. Resolve rate
const resolved = await RateService.resolveLaborRate({
  customerId: ticket.customer_id,
  locationId: ticket.location_id,
  equipmentId: ticket.equipment_id,
  ticketId: ticketId,
  rateType: rateType,
  workDate: clockInTime.toISOString().split('T')[0],
});

// 4. Update time log with snapshot
await supabase
  .from('time_logs')
  .update({
    rate_tier: resolved.rateType,
    billing_rate_applied: resolved.billRate,
    rate_source: resolved.rateSource,
    contract_id_applied: resolved.contractIdApplied,
    is_covered: resolved.isCovered,
    total_billed_amount: totalHours * resolved.billRate,
  })
  .eq('id', timeLogId);
```

**Automatic vs Manual:**
- **Automatic**: Rate resolved when time entry is completed (clock-out)
- **Manual Override**: Dispatcher/manager can override with reason

### Projects

Same as Tickets - resolve rate when time entry is created or closed.

### Invoicing

**When Generating Invoice from Time Entries:**
```typescript
// Fetch time logs with snapshot data
const { data: timeLogs } = await supabase
  .from('time_logs')
  .select(
    `
    *,
    rate_tier,
    billing_rate_applied,
    rate_source,
    contract_id_applied,
    is_covered
  `
  )
  .eq('ticket_id', ticketId);

// Use snapshotted rates - DO NOT re-resolve
timeLogs.forEach((log) => {
  invoiceLines.push({
    description: `Labor - ${log.rate_tier}`,
    quantity: log.total_hours,
    unit_price: log.billing_rate_applied, // Use snapshot, not current rate
    line_total: log.total_billed_amount,
  });
});
```

**Important:** Invoices ALWAYS use snapshot rates. Never recalculate rates when creating invoices from completed work.

**Refresh in Draft (Optional):**
If invoice is still in draft, you can optionally provide a "Recalculate Rates" button that re-resolves all rates. Once invoice is finalized, rates are locked forever.

## Service Contract Integration

### Contract-Level Settings

```sql
service_contracts:
  labor_rate_type: 'standard' | 'discount_percentage' | 'fixed_rate' | 'tiered'
  labor_discount_percent: 15  -- e.g., 15% off
  labor_fixed_rate: 95.00      -- flat rate per hour
  includes_after_hours_rate_reduction: true  -- use standard rate for after-hours
```

### Equipment-Level Coverage

```sql
service_contract_coverage:
  equipment_id: uuid
  labor_coverage_level: 'none' | 'discount_only' | 'full_for_pm_only' | 'full_all_service'
```

### Coverage Scenarios

#### Scenario 1: Discount Only
```
Contract: 15% discount, labor_coverage_level = 'discount_only'
Base rate: $120/hr
Applied rate: $120 * 0.85 = $102/hr
is_covered: false
```

#### Scenario 2: Fully Covered
```
Contract: labor_coverage_level = 'full_all_service'
Applied rate: $0/hr
is_covered: true
```

#### Scenario 3: Fixed Rate
```
Contract: labor_rate_type = 'fixed_rate', labor_fixed_rate = $95
Applied rate: $95/hr
is_covered: false
```

#### Scenario 4: No Contract
```
No active contract found
Applied rate: From accounting_settings ($120 standard)
rate_source: 'settings'
is_covered: false
```

## Override Workflow

### UI Requirements
1. Show current rate and source
2. Provide "Override Rate" button
3. Modal prompts for:
   - New rate amount
   - Reason (required)
4. Display who overrode and when
5. Badge/indicator for overridden rates

### Example UI Code
```typescript
// Show rate info
<div className="rate-info">
  <span>Rate: ${timeLog.billing_rate_applied}/hr</span>
  <span className="badge">
    {RateService.formatRateSource(timeLog.rate_source)}
  </span>

  {timeLog.is_covered && (
    <span className="badge badge-success">Covered</span>
  )}

  {timeLog.rate_source === 'override' && (
    <Tooltip content={timeLog.override_reason}>
      <AlertTriangle className="text-yellow-500" />
    </Tooltip>
  )}
</div>

// Override button
<button onClick={handleOverride}>Override Rate</button>
```

## Testing Scenarios

### Test 1: Default Rates
```typescript
// Customer with no contract
const resolved = await RateService.resolveLaborRate({
  customerId: 'cust-123',
  rateType: 'standard',
});

expect(resolved.rateSource).toBe('settings');
expect(resolved.billRate).toBe(120);
expect(resolved.isCovered).toBe(false);
```

### Test 2: Service Contract Discount
```typescript
// Customer with 15% discount contract
const resolved = await RateService.resolveLaborRate({
  customerId: 'cust-456',
  rateType: 'standard',
});

expect(resolved.rateSource).toBe('contract');
expect(resolved.billRate).toBe(102); // 120 * 0.85
expect(resolved.contractIdApplied).toBeTruthy();
```

### Test 3: Fully Covered
```typescript
// Equipment fully covered by contract
const resolved = await RateService.resolveLaborRate({
  customerId: 'cust-789',
  equipmentId: 'equip-123',
  rateType: 'standard',
});

expect(resolved.rateSource).toBe('contract');
expect(resolved.billRate).toBe(0);
expect(resolved.isCovered).toBe(true);
```

### Test 4: Manual Override
```typescript
// Manager overrides rate
const resolved = await RateService.resolveLaborRate({
  customerId: 'cust-123',
  rateType: 'standard',
  overrideRate: 150,
  overrideReason: 'Special project - approved by VP',
  overrideBy: 'user-admin',
});

expect(resolved.rateSource).toBe('override');
expect(resolved.billRate).toBe(150);
expect(resolved.overrideReason).toBe('Special project - approved by VP');
```

### Test 5: Rate Change Doesn't Affect History
```sql
-- Update accounting settings
UPDATE accounting_settings
SET setting_value = '130'
WHERE setting_key = 'standard_labor_rate';

-- Verify old time logs still show $120
SELECT billing_rate_applied FROM time_logs WHERE id = 'old-log';
-- Returns: 120 (not 130)

-- Verify new work gets $130
-- New rate resolution will return 130
```

## Reporting & Analytics

### Show Rate Source in Reports
```sql
SELECT
  tl.id,
  tl.total_hours,
  tl.billing_rate_applied,
  tl.rate_source,
  CASE
    WHEN tl.rate_source = 'contract' THEN sc.name
    ELSE 'N/A'
  END as contract_name,
  tl.is_covered
FROM time_logs tl
LEFT JOIN service_contracts sc ON sc.id = tl.contract_id_applied
WHERE tl.ticket_id = ?;
```

### Audit Rate Changes
```sql
-- Find all overridden rates
SELECT
  tl.id,
  t.ticket_number,
  tl.billing_rate_applied,
  tl.override_reason,
  p.full_name as overridden_by_name,
  tl.overridden_at
FROM time_logs tl
INNER JOIN tickets t ON t.id = tl.ticket_id
LEFT JOIN profiles p ON p.id = tl.overridden_by
WHERE tl.rate_source = 'override'
ORDER BY tl.overridden_at DESC;
```

### Compare Rate Sources
```sql
-- Breakdown of labor billing by rate source
SELECT
  rate_source,
  COUNT(*) as entry_count,
  SUM(total_hours) as total_hours,
  SUM(total_billed_amount) as total_billed,
  AVG(billing_rate_applied) as avg_rate
FROM time_logs
WHERE clock_in_time >= '2024-01-01'
GROUP BY rate_source
ORDER BY total_billed DESC;
```

## Migration Path

### Phase 1: Infrastructure ✅ (Complete)
- Add snapshot fields to time_logs and estimate_line_items
- Create fn_resolve_labor_rate RPC function
- Create RateService TypeScript helper

### Phase 2: UI Integration (Next Steps)
- Update Estimate creation to use rate resolver
- Update Time Clock to snapshot rates on clock-out
- Add override UI with reason capture
- Show rate source badges in time entry lists

### Phase 3: Invoicing (Next Steps)
- Ensure invoice generation uses snapshot rates
- Add rate verification/audit tool
- Display contract coverage on invoices

### Phase 4: Reporting
- Add rate source to financial reports
- Create override audit report
- Add contract utilization analytics

## Best Practices

### DO:
✅ Always call `resolveLaborRate()` when creating time entries or estimate lines
✅ Store the complete snapshot (rate + source + contract + coverage)
✅ Require override_reason for any manual rate changes
✅ Use snapshot rates for invoicing (never recalculate)
✅ Show rate source visually (badge, icon, tooltip)
✅ Log who performed overrides and when

### DON'T:
❌ Recalculate rates after work is completed
❌ Allow overrides without documented reason
❌ Assume default rates - always call resolver
❌ Ignore service contract coverage
❌ Skip snapshot fields (they prevent future bugs)
❌ Use billing_rate_applied without also storing rate_source

## Troubleshooting

### Issue: Rates don't match expectations
1. Check service contract status and dates
2. Verify equipment_id matches coverage
3. Look at rate_source to understand which rule applied
4. Use `verifyRateSnapshot()` to compare current vs snapshot

### Issue: Override not working
1. Verify override_reason is provided
2. Check permissions (is user allowed to override?)
3. Ensure override_rate is different from resolved rate

### Issue: Old invoices showing wrong rates
- This is by design - invoices use snapshot rates
- If truly wrong, must be corrected via credit memo + new invoice
- Never retroactively change historical billing rates

## Future Enhancements

1. **Customer-Specific Rates**
   - Add customer_labor_rates table
   - Slot into hierarchy between contract and settings

2. **Time-of-Day Auto-Detection**
   - Automatically determine rate_type from clock_in_time
   - Smart rules: weekends = after_hours, nights = after_hours

3. **Rate Approval Workflow**
   - Require manager approval for overrides over $X
   - Email notifications for override requests

4. **Contract Utilization Tracking**
   - Track visits_used against included_visits_per_year
   - Alert when approaching limit

5. **Rate History**
   - Track changes to accounting_settings rates
   - Show historical rate curves in reports

## Summary

This system ensures:
- ✅ **Consistency**: Same rate logic across all modules
- ✅ **Auditability**: Every rate has a source and reason
- ✅ **Stability**: Historical data never changes
- ✅ **Flexibility**: Service contracts + overrides + customer rates
- ✅ **Transparency**: Clear indication of rate source and coverage
