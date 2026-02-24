# Google Maps Integration for Call Map

## Overview

The Call Map feature now uses real Google Maps to display service tickets as interactive markers on an actual map of your service area. This integration provides dispatchers and administrators with a visual overview of all active service calls.

## Features Implemented

### 1. Real Google Maps Display
- Interactive Google Map with zoom, pan, and street view controls
- Smooth map experience with modern UI
- Automatic map bounds adjustment based on ticket locations

### 2. Ticket Markers
- **Status-based colors:**
  - Red: Open tickets (requires immediate attention)
  - Blue: Scheduled tickets
  - Yellow: In Progress tickets
  - Green: Completed tickets

- **Priority-based sizing:**
  - Urgent: Larger markers (1.5x scale)
  - High: Medium-large markers (1.2x scale)
  - Normal: Standard markers (1.0x scale)
  - Low: Smaller markers (0.8x scale)

### 3. Interactive Info Windows
When clicking a marker, you'll see:
- Ticket number and current status
- Ticket title and description
- Customer name and address
- Assigned technician
- Scheduled date/time (if applicable)
- "View Ticket Details" button

### 4. Marker Clustering
- Automatically enables when more than 50 markers are displayed
- Groups nearby markers for better performance and readability
- Expands to show individual markers when zoomed in

## Database Changes (Additive Only)

The following fields were added to the `tickets` table:

```sql
- place_id (TEXT, nullable) - Google Place ID
- latitude (NUMERIC(10,7), nullable) - Latitude coordinate
- longitude (NUMERIC(10,7), nullable) - Longitude coordinate
- geocoded_at (TIMESTAMPTZ, nullable) - When geocoding was performed
- geocode_source (TEXT, nullable) - Source of coordinates (geocoding/places/manual)
```

**Important:** All fields are nullable, so existing tickets continue to work without modification.

## Configuration

### Environment Variables
The Google Maps API key is stored in `.env`:

```
VITE_GOOGLE_MAPS_API_KEY=your_api_key_here
```

The loader uses the `@googlemaps/js-api-loader` package which dynamically loads the Maps JavaScript API with the following parameters:
- `key`: Your API key from the environment variable
- `v`: API version (set to 'weekly' for latest stable release)

The API script is loaded as: `https://maps.googleapis.com/maps/api/js?key=YOUR_KEY&v=weekly&libraries=maps,marker&callback=...`

**Security Note:** For production:
1. Restrict the key in Google Cloud Console by HTTP referrers
2. Enable only required API: Maps JavaScript API
3. Set up billing alerts
4. Never commit API keys to version control

### Default Map Center
Currently defaults to coordinates (32.3547, -89.3985). This can be configured in the `CallMapGoogle.tsx` component or stored in company settings.

## Usage

### For All Users

1. **View the Map:**
   - Navigate to "Call Map" in the sidebar
   - The map loads with all active tickets that have coordinates

2. **Filter Tickets:**
   - Use the status filter dropdown to show specific ticket types
   - Map markers update automatically

3. **View Ticket Details:**
   - Click any marker on the map
   - Review ticket information in the popup
   - Click "View Ticket Details" to open the full ticket view

4. **Add Coordinates:**
   - Tickets without latitude/longitude coordinates won't display on the map
   - Add coordinates manually to customer records to display their tickets on the map

## Technical Implementation

### Components
- `src/lib/googleMapsLoader.ts` - Singleton loader for Google Maps API
- `src/components/Mapping/CallMapGoogle.tsx` - Main map component
- `src/components/Mapping/MappingView.tsx` - Updated to use Google Maps

### Dependencies
- `@googlemaps/js-api-loader` - Official Google Maps loader
- `@googlemaps/markerclusterer` - Marker clustering for performance

### Data Flow
1. Tickets are loaded from Supabase with customer and technician data
2. Tickets with coordinates (latitude/longitude) are filtered
3. Map markers are created for each valid ticket
4. Info windows are dynamically generated with ticket data
5. Marker clustering activates for 50+ markers

## Maintenance & Troubleshooting

### Common Issues

**Map doesn't load:**
- Check that `VITE_GOOGLE_MAPS_API_KEY` is set in `.env`
- Verify the API key is valid in Google Cloud Console
- Check browser console for specific error messages
- **Verify API key is in the request:** Open DevTools Network tab and check the request to `https://maps.googleapis.com/maps/api/js`. The URL should include `?key=YOUR_KEY`
- If you see "NoApiKeys" or "ApiProjectMapError", the API key is missing from the request

**COEP (Cross-Origin-Embedder-Policy) Warnings:**
- Google Maps may generate console warnings about COEP headers
- These warnings reference `googletagmanager.com` and can be safely ignored
- They do not affect map functionality
- If you have strict COEP requirements, you may need to adjust headers in your hosting configuration

**Markers don't appear:**
- Verify tickets have non-null latitude/longitude values
- Check that status filter isn't excluding all tickets
- Add coordinates to customer records if missing

### Performance Considerations
- Marker clustering automatically handles large datasets (50+ tickets)
- Map only loads once per page view (singleton pattern)

## Future Enhancements

Potential improvements for future iterations:

1. **Real-time updates** - WebSocket/polling for live marker updates
2. **Route optimization** - Suggest optimal technician routes
3. **Heat maps** - Show service density by area
4. **Custom markers** - Different icons for different service types
5. **Geofencing** - Alert when techs enter/leave service areas
6. **Offline support** - Cache map tiles for offline viewing
7. **Company profile settings** - Store default map center in database

## No Breaking Changes

This integration was designed to be fully backward compatible:
- All database changes are additive (nullable columns)
- Existing ticket creation/editing flows unchanged
- Tickets work normally without coordinates
- SVG placeholder map removed, but all other features preserved
- No changes to RLS policies or permissions

All existing modules (Tickets, Dispatch, Projects, Accounting, etc.) continue to function exactly as before.
