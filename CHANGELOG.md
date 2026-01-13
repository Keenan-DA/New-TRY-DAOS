# Changelog

All notable changes to the DA-OS project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Planned
- Materialized views for slow queries
- Archival strategy for old records
- Triggers to auto-maintain count columns

---

## [7.1.0] - 2026-01-13

### Added
- **Appointment webhook consolidation** - Single endpoint handles both creation and status updates
- **`rep_manual` appointment source** - Tracks appointments booked directly in GHL calendar
- **Deduplication logic** - Prevents duplicate appointments when n8n and webhook fire simultaneously
- **CHECK constraints** - Enforces valid values for `outcome_status`, `created_source`, `status`, `lead_type`
- **Performance indexes** - Added compound indexes for common query patterns
- **Developer documentation** - Comprehensive onboarding guide and data dictionary

### Changed
- `insert_appointment()` now uses `ON CONFLICT DO UPDATE` (authoritative)
- `upsert_appointment_from_webhook()` checks existence first (passive)
- Views updated to include `rep_manual` in human booking counts
- Repository reorganized for clarity

### Fixed
- Missing indexes on `lead_source_dictionary` causing slow lookups
- Invalid data normalized before adding CHECK constraints
- Division by zero potential in compounding rate views

### Security
- Added NOT NULL constraints on `leads.contact_id` and `leads.location_id`

---

## [7.0.5] - 2026-01-12

### Added
- Initial repository structure
- Core documentation (SCHEMA, ARCHITECTURE, DASHBOARD_BLUEPRINT)
- Basic webhook endpoints

---

## Migration Guide

### Upgrading to 7.1.0

1. **Run migrations in order:**
   ```sql
   -- supabase/migrations/002_appointment_upsert.sql
   -- supabase/migrations/003_critical_fixes.sql
   ```

2. **Deploy edge function:**
   ```bash
   supabase functions deploy ghl-appointment-webhook
   ```

3. **Update GHL webhooks:**
   - Add "Appointment Created" trigger → same endpoint
   - Keep "Appointment Status Changed" trigger → same endpoint

4. **Verify:**
   ```sql
   SELECT created_source, COUNT(*)
   FROM appointments
   GROUP BY created_source;
   ```

---

## File Changes by Version

### 7.1.0
```
Added:
  docs/DEVELOPER_GUIDE.md
  docs/DATA_DICTIONARY.md
  supabase/migrations/002_appointment_upsert.sql
  supabase/migrations/003_critical_fixes.sql
  supabase/functions/ghl-appointment-webhook/index.ts
  CHANGELOG.md
  .gitignore

Renamed:
  SUPABASE_SCHEMA (2).md → docs/SCHEMA.md
  INBOUND-DATA-SOURCES.md → docs/ARCHITECTURE.md
  CS_DASHBOARD_BLUEPRINT_V2 (1).md → docs/DASHBOARD_BLUEPRINT.md
  DA-OS (4).html → docs/diagrams/data-flow.html

Removed:
  Sub-Accounts List-2026-01-12.csv (moved to data/, gitignored)
```
