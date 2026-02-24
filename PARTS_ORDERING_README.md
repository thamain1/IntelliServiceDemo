# Parts Ordering System - Implementation Guide

## Overview
The Parts Ordering system implements lean/JIT (Just-In-Time) inventory management best practices with three main features:
1. **Vendor Catalogs** - Browse vendor part catalogs with pricing and lead times
2. **Reorder Alerts** - Monitor inventory levels and receive reorder recommendations
3. **Lead Time Reports** - Track vendor delivery performance and reliability

## Routing

All three pages are accessible via:
- Left menu: **Procurement** → **Parts Ordering** → submenu items
- Routes are correctly wired and distinct:
  - `/procurement/parts-ordering/vendor-catalogs` → `VendorCatalogsView`
  - `/procurement/parts-ordering/reorder-alerts` → `ReorderAlertsView`
  - `/procurement/parts-ordering/lead-time-reports` → `LeadTimeReportsView`

## Database Schema

### New Tables

#### `inventory_reorder_policies`
Defines reorder rules per part and location:
- `part_id` - FK to parts table
- `location_id` - FK to stock_locations (nullable for global policies)
- `min_qty` - Minimum stock level
- `max_qty` - Maximum stock level
- `safety_stock_qty` - Safety stock buffer
- `lead_days_override` - Override vendor lead time
- `reorder_method` - 'rop' (reorder point) or 'minmax'
- `is_active` - Enable/disable policy

### Enhanced Tables

#### `vendor_part_mappings`
Added columns:
- `uom` - Unit of measure (text)
- `pack_qty` - Package quantity (integer, default 1)

### Views

#### `vw_vendor_catalog_items`
Joins vendor_part_mappings + vendors + parts to provide:
- Part details (number, description, category)
- Vendor details (name, code)
- Pricing (standard_cost, last_cost)
- Ordering info (MOQ, pack qty, lead time)
- Preferred vendor flag

#### `vw_reorder_alerts`
Calculates reorder recommendations per part+location:

**Inputs:**
- `on_hand` - Current inventory from part_inventory
- `reserved` - Allocated to tickets/projects (currently 0, TODO)
- `inbound_open_po` - Qty on open POs not yet received
- `avg_daily_usage` - Historical usage rate (currently 0, TODO)

**Calculations:**
- `available` = on_hand + inbound_open_po
- `reorder_point` = Currently set to safety_stock_qty
  - *Future: (avg_daily_usage × lead_days) + safety_stock*
- `suggested_order_qty` = Rounds up to pack qty/MOQ, respects max_qty
- `below_reorder_point` = on_hand ≤ reorder_point
- `is_stockout` = on_hand = 0

**Vendor Selection:**
- Uses preferred vendor (is_preferred_vendor = true)
- Falls back to most recent purchase if multiple vendors

#### `vw_vendor_lead_time_metrics`
Analyzes vendor delivery performance from PO history:

**Metrics:**
- `avg_lead_days` - Average time from order to first receipt
- `median_lead_days` - Median lead time
- `p90_lead_days` - 90th percentile (worst-case planning)
- `on_time_pct` - % delivered on/before expected date
- `fill_rate_pct` - % of ordered qty actually received

**Data Source:**
- Based on purchase_orders + purchase_order_lines + purchase_order_receipts
- Filters: POs with status 'received' or 'partial'
- Time range: Last 365 days

## How Reorder Calculations Work

### Current Implementation (Phase 1)

```
Reorder Point = safety_stock_qty
```

The system flags items for reorder when:
```
on_hand ≤ safety_stock_qty
```

Suggested order quantity calculation:
```
IF max_qty > 0:
  suggested_qty = max_qty - on_hand
  Round up to pack_qty
  Enforce MOQ minimum
ELSE:
  suggested_qty = MOQ
```

### Future Enhancement (Phase 2)

Once historical usage tracking is implemented:

```
Reorder Point = (avg_daily_usage × lead_days) + safety_stock_qty
```

This ensures you order when inventory will last through the lead time plus safety buffer.

### Reserved/Allocated Quantities

Currently stub return 0. Future implementation will calculate:
```
reserved = SUM(ticket allocations) + SUM(project allocations)
```

This prevents ordering when parts are on hand but already committed.

## Service Layer

### `PartsOrderingService.ts`

**Methods:**
- `getVendorCatalogItems(params)` - Fetch catalog items
  - Filters: vendorId, partId, category, preferredOnly, search
- `getReorderAlerts(params)` - Fetch reorder recommendations
  - Filters: locationId, vendorId, criticalOnly, belowRopOnly, stockoutsOnly
- `getVendorLeadTimeMetrics(params)` - Fetch lead time stats
  - Filter: vendorId
- `getReorderPolicy(partId, locationId)` - Get policy for part
- `upsertReorderPolicy(policy)` - Create/update reorder policy

All methods use typed DTOs and include error handling.

## UI Features

### Vendor Catalogs
- Search by part number, description, or vendor SKU
- Filter by vendor
- Filter to preferred vendors only
- Shows: pricing, MOQ, pack qty, lead time, last purchase date
- Star icon indicates preferred vendor

### Reorder Alerts
- KPI cards: Critical Alerts, Low Stock, Total Locations
- Filter by location, vendor, status
- Color-coded status badges:
  - Red: Stockout (on_hand = 0)
  - Yellow: Below ROP (on_hand ≤ reorder_point)
  - Orange: Low (on_hand ≤ 10)
  - Green: OK
- Shows suggested order qty and estimated cost
- Sorted by urgency (stockouts first, then below ROP, then low stock)

### Lead Time Reports
- KPI cards: Avg Lead Time, On-Time %, Fill Rate %
- Performance badges:
  - Excellent: ≥95% on-time
  - Good: ≥85% on-time
  - Fair: ≥70% on-time
  - Poor: <70% on-time
- Statistical metrics: avg, median, P90, range
- Based on last 365 days of PO data

## Single Source of Truth

All inventory data comes from:
- `part_inventory` - Current stock levels
- `purchase_orders` + `purchase_order_lines` - Inbound qty
- `purchase_order_receipts` - Receipt history for lead time calculations

No duplicate inventory tracking tables. Views are read-only aggregations.

## Security (RLS)

### `inventory_reorder_policies`
- Admin/dispatcher: Full CRUD access
- Technician: Read-only (via views)

All views inherit RLS from underlying tables (parts, vendors, part_inventory, etc.)

## Future Enhancements

1. **Historical Usage Tracking**
   - Create `inventory_usage_history` table
   - Calculate avg_daily_usage from ticket parts consumed
   - Update reorder_point formula

2. **Reserved/Allocated Tracking**
   - Link ticket parts to inventory records
   - Link project material allocations
   - Update `reserved` calculation in view

3. **Draft PO Generation**
   - "Create Draft PO" button on reorder alerts
   - Group by vendor + location
   - Pre-populate with suggested quantities

4. **Email Alerts**
   - Notify when items hit reorder point
   - Daily/weekly reorder summary
   - Stockout alerts

5. **ABC Analysis**
   - Classify parts by value/velocity
   - Different reorder policies by class
   - Focus attention on high-value items

## Non-Regression Verification

All existing features verified working:
- ✅ Tickets module (add parts from truck inventory)
- ✅ Purchase Orders (create/manage POs)
- ✅ Parts Receiving (receive against POs)
- ✅ Parts Transfers (warehouse ↔ vehicle)
- ✅ Serialization & Warranty tracking
- ✅ Inventory balances match across views
- ✅ No routing regressions (all menu items work)

## Build Status

- ✅ TypeScript compilation successful
- ✅ No ESLint errors
- ✅ Bundle size acceptable (1.35MB before gzip)
- ✅ All routes functional

## Performance Considerations

- Views use indexed columns (vendor_id, part_id, location_id, status)
- Reorder alerts CROSS JOIN limited to active parts + active locations
- Lead time metrics filter to last 365 days
- All queries optimized for typical dataset sizes

## Testing Recommendations

1. **Vendor Catalogs**
   - Add vendor part mappings via vendor detail page
   - Mark some vendors as preferred
   - Verify search and filtering

2. **Reorder Alerts**
   - Create reorder policies for test parts
   - Adjust inventory to trigger alerts
   - Verify suggested qty calculations

3. **Lead Time Reports**
   - Create and receive test POs
   - Verify metrics calculation
   - Test on-time vs late deliveries
