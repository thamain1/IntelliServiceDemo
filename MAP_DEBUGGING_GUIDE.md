# Map Marker Debugging Guide

## Comprehensive Diagnostic Logging Implemented

This guide will help you diagnose why markers aren't showing on the map. The system now has extensive console logging to track every step of the data flow.

## Step 1: Check Browser Console for Diagnostic Logs

Navigate to the Call Map page and open your browser's Developer Tools console (F12). You should see detailed logs that will tell you exactly what's happening.

### Expected Console Output (Success Case)

```
[MappingView] Loading tickets for map...
[MappingView] Loaded tickets: 25
[MappingView] Tickets WITH coordinates: 15
[MappingView] Tickets MISSING coordinates: 10
[MappingView] Sample ticket with coords: {
  ticket_number: "T-2024-001",
  status: "open",
  priority: "high",
  ticket_lat: null,
  ticket_lng: null,
  customer_lat: 32.3547,
  customer_lng: -89.3985,
  customer_name: "ABC Company"
}
Initializing map from useEffect
Loading Google Maps API...
Google Maps API loaded successfully
Creating map instance...
Map instance created successfully
[Map] Updating markers...
[Map] Total active tickets: 15
[Map] Tickets with coords: 15
[Map] Tickets without coords: 0
[Map] Adding marker for ticket: T-2024-001 at position: {lat: 32.3547, lng: -89.3985} status: open priority: high
[Map] Successfully created marker # 1 for T-2024-001
[Map] Adding marker for ticket: T-2024-002 at position: {lat: 32.3621, lng: -89.4102} status: scheduled priority: normal
[Map] Successfully created marker # 2 for T-2024-002
...
[Map] Created 15 markers
[Map] Markers state updated
[Map] Fitting bounds for 15 markers
[Map] Multiple markers - fitting bounds: {north: 32.4xxx, south: 32.2xxx, east: -89.3xxx, west: -89.5xxx}
```

### Problem Case 1: No Tickets Loaded

```
[MappingView] Loading tickets for map...
[MappingView] Loaded tickets: 0
[MappingView] Tickets WITH coordinates: 0
[MappingView] Tickets MISSING coordinates: 0
```

**Diagnosis:** No tickets match the filter criteria.

**Solution:** Check that you have tickets with status `open`, `scheduled`, or `in_progress` (not cancelled, closed_billed, or completed).

### Problem Case 2: Tickets Loaded but No Coordinates

```
[MappingView] Loading tickets for map...
[MappingView] Loaded tickets: 20
[MappingView] Tickets WITH coordinates: 0
[MappingView] Tickets MISSING coordinates: 20
[MappingView] Sample ticket missing coords: {
  ticket_number: "T-2024-001",
  customer_name: "ABC Company",
  customer_address: "123 Main St"
}
```

**Diagnosis:** Tickets exist but have no geocoded coordinates.

**Solution:** Add latitude/longitude to customer records. See "How to Add Coordinates" section below.

### Problem Case 3: Markers Created but Not Visible

```
[Map] Created 15 markers
[Map] Markers state updated
[Map] Fitting bounds for 15 markers
(No errors, but markers still not visible on map)
```

**Diagnosis:** Possible map rendering or Google Maps API issue.

**Solution:**
1. Check for Google Maps console errors (red text)
2. Verify your Google Maps API key is valid and has Maps JavaScript API enabled
3. Check for CORS/CSP errors blocking Google Maps resources
4. Try refreshing the page

## Step 2: Query Configuration

### Database Query (MappingView.tsx)

The system now loads tickets with this query:

```typescript
.from('tickets')
.select('*, customers!tickets_customer_id_fkey(name, address, city, state, latitude, longitude, place_id), profiles!tickets_assigned_to_fkey(full_name)')
.not('status', 'in', '(cancelled,closed_billed,completed)')
.order('priority', { ascending: false });
```

**What it does:**
- Loads tickets that are NOT cancelled, closed_billed, or completed
- Includes customer data (including lat/lng)
- Includes assigned technician data
- Orders by priority (urgent first)

**Tickets shown on map:**
- ✅ Open tickets
- ✅ Scheduled tickets
- ✅ In Progress tickets
- ❌ Completed tickets (excluded)
- ❌ Cancelled tickets (excluded)
- ❌ Closed & Billed tickets (excluded)

## Step 3: Coordinate Resolution Logic

The system checks for coordinates in this order:

1. **First:** Check `ticket.latitude` and `ticket.longitude`
2. **Fallback:** Check `customer.latitude` and `customer.longitude`
3. **If neither exist:** Ticket cannot be displayed on map

### Verification Query

Run this in Supabase SQL Editor to see which tickets have coordinates:

```sql
SELECT
  t.ticket_number,
  t.status,
  t.priority,
  t.assigned_to,
  t.latitude as ticket_lat,
  t.longitude as ticket_lng,
  c.name as customer,
  c.address,
  c.city,
  c.state,
  c.latitude as customer_lat,
  c.longitude as customer_lng,
  CASE
    WHEN t.latitude IS NOT NULL AND t.longitude IS NOT NULL THEN 'ticket'
    WHEN c.latitude IS NOT NULL AND c.longitude IS NOT NULL THEN 'customer'
    ELSE 'none'
  END as coord_source
FROM tickets t
LEFT JOIN customers c ON c.id = t.customer_id
WHERE t.status NOT IN ('cancelled', 'closed_billed', 'completed')
ORDER BY
  CASE
    WHEN t.latitude IS NOT NULL OR c.latitude IS NOT NULL THEN 0
    ELSE 1
  END,
  t.created_at DESC;
```

This will show you:
- Which tickets have coordinates (and from where)
- Which tickets are missing coordinates
- What the coordinate values are

## Step 4: How to Add Coordinates to Customers

### Option 1: Manual Entry (for testing)

```sql
-- Update a specific customer with coordinates
UPDATE customers
SET
  latitude = 32.3547,    -- Your latitude
  longitude = -89.3985,  -- Your longitude
  geocoded_at = NOW(),
  geocode_source = 'manual'
WHERE name = 'ABC Company';
```

### Option 2: Geocode Customer Addresses

You need to geocode your customer addresses using a service like Google Geocoding API. Here's the general process:

1. Get customer addresses:
```sql
SELECT id, name, address, city, state, zip
FROM customers
WHERE latitude IS NULL
  AND address IS NOT NULL;
```

2. For each address, call a geocoding API to get lat/lng

3. Update the customer record:
```sql
UPDATE customers
SET
  latitude = <geocoded_lat>,
  longitude = <geocoded_lng>,
  place_id = <google_place_id>,
  geocoded_at = NOW(),
  geocode_source = 'geocoding'
WHERE id = <customer_id>;
```

### Option 3: Use Google Geocoding API (Example)

You would need to create a background job or admin tool that:

1. Fetches customers without coordinates
2. Constructs full address: `"123 Main St, Jackson, MS 39201, USA"`
3. Calls Google Geocoding API
4. Stores results in customer record

**Note:** This requires a Google Geocoding API key and counts against your API quota.

## Common Console Error Messages

### "CORB blocked cross-origin response"

This is usually benign and relates to Google Analytics/Tag Manager. If it's blocking the map tiles or API, check:
- Your Google Maps API key restrictions
- That the domain is allowed in API key settings
- CORS headers are properly configured

### "Google Maps API error: RefererNotAllowedMapError"

**Solution:** Add your domain to the API key's allowed referrers in Google Cloud Console.

### "Google Maps API error: InvalidKeyMapError"

**Solution:** Check that your VITE_GOOGLE_MAPS_API_KEY environment variable is set correctly.

### "Failed to load map"

Check the detailed error message in the console. Common causes:
- Missing or invalid API key
- API not enabled in Google Cloud Console
- Network connectivity issues
- Ad blockers or security extensions

## Empty State Display

When tickets exist but have no coordinates, you'll see an overlay on the map that says:

> **No Location Data Available**
>
> X tickets loaded but none have geocoded coordinates. Add latitude/longitude to customer records to display markers.

This confirms:
✅ Tickets are loading correctly
✅ Map is rendering correctly
❌ Coordinates are missing

## Marker Display Rules

When coordinates exist, markers display with:

### Color by Status:
- 🔴 **Red:** Open tickets
- 🔵 **Blue:** Scheduled tickets
- 🟡 **Yellow:** In Progress tickets

### Size by Priority:
- **Largest (1.5x):** Urgent priority
- **Large (1.2x):** High priority
- **Standard (1.0x):** Normal priority
- **Small (0.8x):** Low priority

## Testing Checklist

- [ ] Navigate to Call Map page
- [ ] Open browser console (F12)
- [ ] Check for `[MappingView] Loaded tickets:` message
- [ ] Verify ticket count > 0
- [ ] Check `[MappingView] Tickets WITH coordinates:` count
- [ ] If count > 0, look for `[Map] Created X markers` message
- [ ] Verify `[Map] Fitting bounds` or `[Map] Single marker - centering` message
- [ ] Check map displays markers at correct locations
- [ ] Click a marker to verify info window appears
- [ ] Test priority sizes (urgent should be noticeably larger)
- [ ] Test status colors (open=red, scheduled=blue, in_progress=yellow)

## Next Steps

1. **Load the map page and check console output**
2. **Identify which problem case matches your situation**
3. **If no coordinates:** Run the verification query to see which customers need geocoding
4. **Add coordinates** to at least one customer for testing
5. **Refresh the map** and verify markers appear

## Support Information

If markers still don't appear after following this guide:

1. Copy the complete console output (all `[MappingView]` and `[Map]` messages)
2. Run the verification query and share results
3. Check for any red error messages in console
4. Note any visible error overlays on the map

This information will help diagnose any remaining issues.
