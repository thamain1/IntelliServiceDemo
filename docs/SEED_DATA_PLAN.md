# Seed Data Plan for Testing

This document outlines the plan to create mock data for comprehensive testing of reports and features.

---

## Overview

Create realistic historical data spanning 6-12 months to populate reports and enable thorough testing across all modules.

## Recommended Approach: SQL Seed Script

A single SQL file to be run in Supabase SQL Editor that generates all test data at once.

---

## Data to Generate

### Customers & Locations
| Item | Quantity | Notes |
|------|----------|-------|
| Customers | 20-30 | Mix of residential and commercial |
| Customer Locations | 30-50 | Some customers with multiple locations |
| Equipment | 50-100 | HVAC units at customer locations |

### Service Operations
| Item | Quantity | Notes |
|------|----------|-------|
| Tickets | 100-200 | Spread over 6-12 months, various statuses |
| Ticket Time Entries | 200-400 | Labor hours for completed tickets |
| Parts Used on Tickets | 100-200 | Parts consumed during service |

### Financials
| Item | Quantity | Notes |
|------|----------|-------|
| Invoices | 50-100 | Generated from tickets, various statuses |
| Invoice Line Items | 150-300 | Labor, parts, travel charges |
| Payments | 30-70 | Partial and full payments for AR aging |

### Projects
| Item | Quantity | Notes |
|------|----------|-------|
| Projects | 5-10 | Various statuses and sizes |
| Project Phases | 20-40 | 3-5 phases per project |
| Project Tasks | 50-100 | Tasks within phases |

### Inventory & Vendors
| Item | Quantity | Notes |
|------|----------|-------|
| Parts | 30-50 | Various HVAC parts |
| Vendors | 10-15 | Suppliers |
| Purchase Orders | 20-30 | Orders to vendors |
| Inventory Transactions | 50-100 | Stock movements |
| Serialized Parts | 20-30 | Parts with serial numbers |

### Contracts & Estimates
| Item | Quantity | Notes |
|------|----------|-------|
| Service Contracts | 10-20 | Active and expiring contracts |
| Estimates | 15-25 | Various statuses |
| Estimate Line Items | 50-100 | Detailed quotes |

### Time & Warranty
| Item | Quantity | Notes |
|------|----------|-------|
| Time Clock Entries | 100-200 | Technician clock in/out |
| Warranty Claims | 5-10 | Various statuses |

---

## Key Requirements

### Use Existing Data
- Reference existing technicians from `profiles` table
- Use existing contract plans from `contract_plans` table
- Maintain referential integrity with all foreign keys

### Realistic Distributions
- **Dates**: Spread over 6-12 months, weighted toward recent months
- **Statuses**: Mix of open, in_progress, completed, cancelled
- **Amounts**: Realistic pricing for HVAC industry
- **Priorities**: Mostly normal, some high/urgent

### Reports to Support
- Financial Reports (Revenue, AR Aging, DSO)
- Labor Efficiency Report
- Technician Metrics
- Project Margins
- Customer Value Analysis
- Inventory Reports

---

## Implementation Steps

1. **Query existing data** - Get IDs of existing technicians, customers, parts
2. **Create base data** - Customers, locations, equipment, vendors
3. **Create operational data** - Tickets with time entries and parts
4. **Create financial data** - Invoices, payments
5. **Create project data** - Projects with phases and tasks
6. **Create inventory data** - Transactions, purchase orders
7. **Create contract data** - Service contracts, estimates

---

## Execution

Run the SQL script in Supabase SQL Editor:
1. Go to https://app.supabase.com/project/uuarbdrzfakvlhlrnwgc
2. Navigate to SQL Editor
3. Paste and run the seed script
4. Verify data in Table Editor

---

## Notes

- Script should be idempotent (can be run multiple times safely)
- Include cleanup section to remove seed data if needed
- Tag seed data with identifiable patterns for easy identification

---

## Status

**Pending** - Will implement when ready to test reports.
