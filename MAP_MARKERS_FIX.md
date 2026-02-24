# Map Markers Display Fix

## Issues Fixed

1. **Markers not displaying on the map** - Coordinate checking was failing due to incorrect type definitions
2. **Completed tickets showing on map** - Should only show open, scheduled, and in_progress tickets
3. **Pin sizes not reflecting priority** - Already implemented correctly, but now visible with markers working

## Changes Made

### 1. Fixed Type Definitions

**Files:** `src/components/Mapping/CallMapGoogle.tsx`, `src/components/Mapping/MappingView.tsx`

Added `latitude`, `longitude`, and `place_id` to the customers type definition:

```typescript
type Ticket = Database['public']['Tables']['tickets']['Row'] & {
  customers?: {
    name: string;
    address: string;
    city: string;
    state: string;
    latitude: number | null;   // Added
    longitude: number | null;  // Added
    place_id: string | null;   // Added
  };
  profiles?: { full_name: string };
};
```

**Why this was needed:** The customers join was selecting `latitude`, `longitude`, and `place_id` from the database, but TypeScript didn't know these fields existed, causing the coordinate checking to fail silently.

### 2. Excluded Completed Tickets from Map

**File:** `src/components/Mapping/CallMapGoogle.tsx`

Changed filtering logic to always exclude completed tickets:

```typescript
// Filter tickets: exclude completed tickets, then apply status filter
const activeTickets = tickets.filter((ticket) => {
  // Always exclude completed tickets from the map
  if (ticket.status === 'completed') {
    return false;
  }
  // Apply status filter
  return statusFilter === 'all' || ticket.status === statusFilter;
});
```

**Result:** Map now only shows:
- Open tickets (red pins)
- Scheduled tickets (blue pins)
- In Progress tickets (yellow pins)

### 3. Improved Coordinate Checking

**File:** `src/components/Mapping/CallMapGoogle.tsx`

Made coordinate checking more explicit and robust:

```typescript
const ticketsWithCoords = activeTickets.filter((ticket) => {
  const hasTicketCoords = ticket.latitude !== null && ticket.longitude !== null;
  const hasCustomerCoords = ticket.customers &&
    ticket.customers.latitude !== null &&
    ticket.customers.longitude !== null;
  return hasTicketCoords || hasCustomerCoords;
});
```

**How it works:**
1. First checks if the ticket itself has coordinates
2. Falls back to customer coordinates if ticket coordinates are null
3. Either source of coordinates is valid for displaying the marker

### 4. Enhanced Debug Logging

Added comprehensive console logging to help troubleshoot marker issues:

```typescript
console.log('[Map] Updating markers...');
console.log('[Map] Total active tickets:', activeTickets.length);
console.log('[Map] Tickets with coords:', ticketsWithCoords.length);
console.log('[Map] Tickets without coords:', ticketsWithoutCoords.length);
console.log('[Map] Adding marker for ticket:', ticket.ticket_number, 'at', lat, lng, 'status:', ticket.status, 'priority:', ticket.priority);
console.log('[Map] Created', newMarkers.length, 'markers');
```

**Benefits:**
- Easy to see how many tickets are being processed
- Can verify which tickets have coordinates
- Can see exactly which markers are being created
- Helps identify coordinate or filtering issues

### 5. Updated UI Legend

**Files:** `src/components/Mapping/CallMapGoogle.tsx`, `src/components/Mapping/MappingView.tsx`

- Removed "Completed" from the status color legend (since they don't appear on map)
- Updated counter to show "active tickets" instead of "all tickets"
- Changed from "Showing X of Y tickets" to "Showing X of Y active tickets"

## Pin Size by Priority

The map already implements priority-based pin sizing:

- **Urgent Priority:** 1.5x scale (largest pins)
- **High Priority:** 1.2x scale
- **Normal Priority:** 1.0x scale (standard size)
- **Low Priority:** 0.8x scale (smallest pins)

This is implemented via the `scale` property in the marker icon:

```typescript
const priorityScales: Record<string, number> = {
  urgent: 1.5,
  high: 1.2,
  normal: 1.0,
  low: 0.8,
};

const scale = priorityScales[ticket.priority] || 1.0;

const marker = new google.maps.Marker({
  icon: {
    path: google.maps.SymbolPath.CIRCLE,
    scale: 8 * scale,  // Base size * priority scale
    // ... other properties
  },
});
```

## Status Colors on Map

- **Red:** Open tickets - Requires immediate attention
- **Blue:** Scheduled tickets - Appointment set
- **Yellow:** In Progress tickets - Tech on site
- ~~Green: Completed tickets~~ - **No longer displayed on map**

## Verifying the Fix

To verify markers are displaying correctly:

1. **Open DevTools Console** (F12)
2. **Navigate to Call Map**
3. **Check for console logs:**
   ```
   [Map] Updating markers...
   [Map] Total active tickets: X
   [Map] Tickets with coords: Y
   [Map] Tickets without coords: Z
   [Map] Adding marker for ticket: T-2024-XXX at 32.xxx -89.xxx status: open priority: urgent
   [Map] Created Y markers
   ```

4. **Verify on map:**
   - Pins appear at ticket locations
   - Pin colors match ticket status
   - Pin sizes vary by priority (urgent are noticeably larger than low)
   - No green (completed) pins are visible

## If Markers Still Don't Appear

If you see `[Map] Tickets with coords: 0`, your tickets don't have coordinates yet. You need to:

1. **Check customer records** - Do customers have `latitude` and `longitude` values?
2. **Check ticket records** - Do tickets have `latitude` and `longitude` values?
3. **Geocode addresses** - Use a geocoding service to add coordinates to customer records

### Quick Database Check

Run this query to see which tickets have coordinates:

```sql
SELECT
  t.ticket_number,
  t.status,
  t.priority,
  t.latitude as ticket_lat,
  t.longitude as ticket_lng,
  c.name as customer,
  c.latitude as customer_lat,
  c.longitude as customer_lng
FROM tickets t
LEFT JOIN customers c ON c.id = t.customer_id
WHERE t.status IN ('open', 'scheduled', 'in_progress')
ORDER BY t.created_at DESC
LIMIT 20;
```

Look for rows where either `ticket_lat/ticket_lng` OR `customer_lat/customer_lng` have non-null values.

## No Breaking Changes

- No database schema changes
- No RLS policy changes
- Existing tickets continue to work
- Map functionality preserved
- All other features unaffected

## Files Modified

1. `src/components/Mapping/CallMapGoogle.tsx` - Core map component with marker logic
2. `src/components/Mapping/MappingView.tsx` - Parent view component
3. `MAP_MARKERS_FIX.md` - This documentation file

## Build Status

✅ Build completed successfully with no errors
