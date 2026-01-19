# DRIVE AI - INBOUND DATA SOURCES (COMPLETE REFERENCE)
## Complete Reference for Data Flowing Into Supabase with Exact n8n Node Configurations

**Version:** 7.0.1
**Updated:** January 19, 2026
**Purpose:** Map every data source, when it fires, what it should populate, and EXACT node configurations

---

## TABLE OF CONTENTS

1. [Quick Reference: Data Source → Table Map](#1-quick-reference)
2. [Drive AI 7.0 Workflow - Overview](#2-drive-ai-70-workflow)
3. [Drive AI 7.0 - Remove Path (Exact Node)](#3-drive-ai-70---remove-path)
4. [Drive AI 7.0 - Appointment Path (Exact Nodes)](#4-drive-ai-70---appointment-path)
5. [Drive AI 7.0 - Task Path (Exact Nodes)](#5-drive-ai-70---task-path)
6. [Reactivate Drive Workflow - Overview](#6-reactivate-drive-workflow)
7. [Reactivate Drive - Follow-up Path (Exact Node)](#7-reactivate-drive---follow-up-path)
8. [Reactivate Drive - Appointment Path (Exact Node)](#8-reactivate-drive---appointment-path)
9. [Reactivate Drive - Remove Path (Exact Node)](#9-reactivate-drive---remove-path)
10. [GHL Webhooks (Edge Functions)](#10-ghl-webhooks)
11. [Verification Queries](#11-verification-queries)
12. [Data Relationships & Red Flags](#12-data-relationships--red-flags)
13. [Full Workflow JSON Reference](#13-full-workflow-json-reference)

---

## 1. QUICK REFERENCE

### Data Source → Table Map

| Source | Trigger | RPC Function | Table(s) Populated |
|--------|---------|--------------|-------------------|
| **Drive AI 7.0** - Remove | AI detects opt-out | `insert_ai_decision` | `ai_decisions` |
| **Drive AI 7.0** - Appointment (Primary) | AI books on primary calendar | `insert_appointment` | `appointments` |
| **Drive AI 7.0** - Appointment (Backup) | AI books on backup calendar | `insert_appointment` | `appointments` |
| **Drive AI 7.0** - Task (Primary) | AI creates task | `upsert_task` | `tasks` |
| **Drive AI 7.0** - Task (Backup) | AI creates backup task | `upsert_task` | `tasks` |
| **Reactivate Drive** - Follow-up | Rep instructs follow-up | `insert_reactivation` | `reactivations` + closes `tasks` |
| **Reactivate Drive** - Appointment | Rep instructs appointment | `insert_reactivation` | `reactivations` + `appointments` + closes `tasks` |
| **Reactivate Drive** - Remove | Rep instructs removal | `insert_reactivation` | `reactivations` + closes `tasks` |
| **GHL Webhook** - Lead Created | New contact in GHL | `insert_lead_from_ghl` | `leads` |
| **GHL Webhook** - Outbound Sent | First AI message | `update_lead_outbound_ghl` | `leads` (update) |
| **GHL Webhook** - Response | Lead replies | `update_lead_response_ghl` | `leads` (update) |

---

## 2. DRIVE AI 7.0 WORKFLOW

### Workflow Overview

**Name:** Drive AI 7.0  
**Trigger:** Webhook POST (inbound message received in GHL)  
**Webhook Path:** `17ea8cfc-a0ba-40e5-8683-9b0e399a9d7b`

### Decision Flow

```
Webhook (Message Received)
         │
         ▼
    AI Analyzes Conversation
    (OpenAI GPT-5-mini)
         │
         ├──────────────────┬──────────────────┬──────────────────┐
         ▼                  ▼                  ▼                  ▼
      REMOVE           APPOINTMENT          TASK             FOLLOW_UP
         │                  │                  │                  │
         ▼                  ▼                  ▼                  │
  Log AI Remove     Supabase: Appt      Supabase: Task         (no DB)
  (ai_decisions)    (appointments)      (tasks)
```

### Key Upstream Nodes Referenced

| Node Name | Purpose | Data Provided |
|-----------|---------|---------------|
| `W` | Webhook data alias | All contact/location data |
| `Create Appointment (Primary)` | GHL appointment creation | `id`, `traceId`, `calendarId`, `title`, `status`, `appoinmentStatus` |
| `Create Appointment (Backup)` | Backup calendar booking | Same as Primary |
| `Create Task` | GHL task creation | `traceId`, `task.id`, `task.title`, `task.body`, `task.dueDate` |
| `Create Task1` | Backup task creation | Same as Create Task |
| `Appointment Planner` | AI appointment planning | `message.content.appointmentType`, `appointmenttime`, `appointmentSummary`, `apptvalid` |
| `Action Guard` | Decision routing | `action`, `alsoTask` |
| `Decision: Action Only` | AI decision output | `message.content.language` |

---

## 3. DRIVE AI 7.0 - REMOVE PATH

### When It Fires
AI detects the lead has opted out, requested removal, or is no longer workable.

### Exact n8n Node Configuration

```json
{
  "nodes": [
    {
      "parameters": {
        "method": "POST",
        "url": "https://gamwimamcvgakcetdypm.supabase.co/rest/v1/rpc/insert_ai_decision",
        "sendHeaders": true,
        "headerParameters": {
          "parameters": [
            {
              "name": "apikey",
              "value": "sb_publishable_1prVZrYhMgR-cvRLuiKnqw_bFet_YV1"
            },
            {
              "name": "Content-Type",
              "value": "application/json"
            }
          ]
        },
        "sendBody": true,
        "specifyBody": "json",
        "jsonBody": "={{ JSON.stringify({\n  \"p_execution_id\": $execution.id,\n  \"p_trace_id\": $execution.id,\n  \"p_location_id\": $('W').item.json.location_id,\n  \"p_dealership_name\": $('W').item.json.DealerName,\n  \"p_contact_id\": $('W').item.json.contact_id,\n  \"p_lead_name\": $('W').item.json.full_name,\n  \"p_lead_phone\": $('W').item.json.phone,\n  \"p_action\": \"remove\",\n  \"p_reason\": \"Lead opted out or requested removal\",\n  \"p_lead_source\": $('W').item.json.lead_source || $('W').item.json.source || '',\n  \"p_trigger_message\": $('W').item.json.lead_response || $('W').item.json.last_message || ''\n}) }}",
        "options": {}
      },
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 4.2,
      "position": [18608, 3552],
      "id": "28ed59a9-4c8d-4ba6-8191-59908946e56f",
      "name": "Log AI Remove",
      "onError": "continueRegularOutput"
    }
  ]
}
```

### Parameter Mapping

| RPC Parameter | n8n Expression | Source |
|---------------|----------------|--------|
| `p_execution_id` | `$execution.id` | n8n execution ID |
| `p_trace_id` | `$execution.id` | n8n execution ID |
| `p_location_id` | `$('W').item.json.location_id` | Webhook payload |
| `p_dealership_name` | `$('W').item.json.DealerName` | Webhook payload |
| `p_contact_id` | `$('W').item.json.contact_id` | Webhook payload |
| `p_lead_name` | `$('W').item.json.full_name` | Webhook payload |
| `p_lead_phone` | `$('W').item.json.phone` | Webhook payload |
| `p_action` | `"remove"` | Hardcoded |
| `p_reason` | `"Lead opted out or requested removal"` | Hardcoded |
| `p_lead_source` | `$('W').item.json.lead_source \|\| $('W').item.json.source \|\| ''` | Webhook payload (fallback chain) |
| `p_trigger_message` | `$('W').item.json.lead_response \|\| $('W').item.json.last_message \|\| ''` | Webhook payload (fallback chain) |

### Table: `ai_decisions`

| Column | Expected Value |
|--------|----------------|
| `action` | `'remove'` |
| `contact_id` | GHL contact ID |
| `location_id` | GHL location ID |
| `reason` | `'Lead opted out or requested removal'` |
| `initiated_by` | `'ai'` (set by RPC) |

---

## 4. DRIVE AI 7.0 - APPOINTMENT PATH

### When It Fires
AI determines the customer has confirmed an appointment time and books it.

### PRIMARY Appointment Node

```json
{
  "nodes": [
    {
      "parameters": {
        "method": "POST",
        "url": "https://gamwimamcvgakcetdypm.supabase.co/rest/v1/rpc/insert_appointment",
        "sendHeaders": true,
        "headerParameters": {
          "parameters": [
            {
              "name": "apikey",
              "value": "sb_publishable_1prVZrYhMgR-cvRLuiKnqw_bFet_YV1"
            },
            {
              "name": "Content-Type",
              "value": "application/json"
            }
          ]
        },
        "sendBody": true,
        "specifyBody": "json",
        "jsonBody": "={{ JSON.stringify({ p_ghl_appointment_id: $('Create Appointment (Primary)').item.json.id, p_trace_id: $('Create Appointment (Primary)').item.json.traceId, p_calendar_id: $('Create Appointment (Primary)').item.json.calendarId, p_location_id: $('W').item.json.location_id, p_dealership_name: $('W').item.json.DealerName, p_dealership_address: $('W').item.json.location_fullAddress, p_dealership_hours: $('W').item.json.DealerHours, p_dealership_timezone: $('W').item.json.TimeZone, p_contact_id: $('W').item.json.contact_id, p_lead_name: $('W').item.json.full_name, p_lead_first_name: $('W').item.json.first_name, p_lead_phone: $('W').item.json.phone, p_lead_email: $('W').item.json.email, p_assigned_rep_id: $('W').item.json.AssignedUserId, p_assigned_rep_name: (($('W').item.json.user_firstName || '') + ' ' + ($('W').item.json.user_lastName || '')).trim(), p_title: $('Create Appointment (Primary)').item.json.title, p_appointment_type: $('Appointment Planner').item.json.message?.content?.appointmentType, p_appointment_time: $('Appointment Planner').item.json.message?.content?.appointmenttime, p_appointment_summary: $('Appointment Planner').item.json.message?.content?.appointmentSummary, p_appt_valid: $('Appointment Planner').item.json.message?.content?.apptvalid === 'Yes', p_status: $('Create Appointment (Primary)').item.json.status, p_appointment_status: $('Create Appointment (Primary)').item.json.appoinmentStatus, p_created_source: 'ai_automated', p_source_workflow: 'drive_ai_7' }) }}",
        "options": {}
      },
      "id": "0fe7346d-4778-4775-aea0-ea282c4f36ca",
      "name": "Supabase: Appt (Primary)",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 4.2,
      "position": [19104, 3648],
      "onError": "continueErrorOutput"
    }
  ]
}
```

### BACKUP Appointment Node

```json
{
  "nodes": [
    {
      "parameters": {
        "method": "POST",
        "url": "https://gamwimamcvgakcetdypm.supabase.co/rest/v1/rpc/insert_appointment",
        "sendHeaders": true,
        "headerParameters": {
          "parameters": [
            {
              "name": "apikey",
              "value": "sb_publishable_1prVZrYhMgR-cvRLuiKnqw_bFet_YV1"
            },
            {
              "name": "Content-Type",
              "value": "application/json"
            }
          ]
        },
        "sendBody": true,
        "specifyBody": "json",
        "jsonBody": "={{ JSON.stringify({ p_ghl_appointment_id: $('Create Appointment (Backup)').item.json.id, p_trace_id: $('Create Appointment (Backup)').item.json.traceId, p_calendar_id: $('Create Appointment (Backup)').item.json.calendarId, p_location_id: $('W').item.json.location_id, p_dealership_name: $('W').item.json.DealerName, p_dealership_address: $('W').item.json.location_fullAddress, p_dealership_hours: $('W').item.json.DealerHours, p_dealership_timezone: $('W').item.json.TimeZone, p_contact_id: $('W').item.json.contact_id, p_lead_name: $('W').item.json.full_name, p_lead_first_name: $('W').item.json.first_name, p_lead_phone: $('W').item.json.phone, p_lead_email: $('W').item.json.email, p_assigned_rep_id: $('W').item.json.AssignedUserId, p_assigned_rep_name: (($('W').item.json.user_firstName || '') + ' ' + ($('W').item.json.user_lastName || '')).trim(), p_title: $('Create Appointment (Backup)').item.json.title, p_appointment_type: $('Appointment Planner').item.json.message?.content?.appointmentType, p_appointment_time: $('Appointment Planner').item.json.message?.content?.appointmenttime, p_appointment_summary: $('Appointment Planner').item.json.message?.content?.appointmentSummary, p_appt_valid: $('Appointment Planner').item.json.message?.content?.apptvalid === 'Yes', p_status: $('Create Appointment (Backup)').item.json.status, p_appointment_status: $('Create Appointment (Backup)').item.json.appoinmentStatus, p_created_source: 'ai_automated', p_source_workflow: 'drive_ai_7' }) }}",
        "options": {}
      },
      "id": "fe900b90-04ad-4659-912f-5584ecf12ced",
      "name": "Supabase: Appt (Backup)",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 4.2,
      "position": [19328, 3840],
      "onError": "continueErrorOutput"
    }
  ]
}
```

### Parameter Mapping (Both Primary & Backup)

| RPC Parameter | n8n Expression | Source |
|---------------|----------------|--------|
| `p_ghl_appointment_id` | `$('Create Appointment (Primary/Backup)').item.json.id` | GHL API response |
| `p_trace_id` | `$('Create Appointment (Primary/Backup)').item.json.traceId` | GHL API response |
| `p_calendar_id` | `$('Create Appointment (Primary/Backup)').item.json.calendarId` | GHL API response |
| `p_location_id` | `$('W').item.json.location_id` | Webhook payload |
| `p_dealership_name` | `$('W').item.json.DealerName` | Webhook payload |
| `p_dealership_address` | `$('W').item.json.location_fullAddress` | Webhook payload |
| `p_dealership_hours` | `$('W').item.json.DealerHours` | Webhook payload |
| `p_dealership_timezone` | `$('W').item.json.TimeZone` | Webhook payload |
| `p_contact_id` | `$('W').item.json.contact_id` | Webhook payload |
| `p_lead_name` | `$('W').item.json.full_name` | Webhook payload |
| `p_lead_first_name` | `$('W').item.json.first_name` | Webhook payload |
| `p_lead_phone` | `$('W').item.json.phone` | Webhook payload |
| `p_lead_email` | `$('W').item.json.email` | Webhook payload |
| `p_assigned_rep_id` | `$('W').item.json.AssignedUserId` | Webhook payload |
| `p_assigned_rep_name` | `(($('W').item.json.user_firstName \|\| '') + ' ' + ($('W').item.json.user_lastName \|\| '')).trim()` | Concatenated from webhook |
| `p_title` | `$('Create Appointment (Primary/Backup)').item.json.title` | GHL API response |
| `p_appointment_type` | `$('Appointment Planner').item.json.message?.content?.appointmentType` | AI Planner output |
| `p_appointment_time` | `$('Appointment Planner').item.json.message?.content?.appointmenttime` | AI Planner output |
| `p_appointment_summary` | `$('Appointment Planner').item.json.message?.content?.appointmentSummary` | AI Planner output |
| `p_appt_valid` | `$('Appointment Planner').item.json.message?.content?.apptvalid === 'Yes'` | AI Planner output (boolean) |
| `p_status` | `$('Create Appointment (Primary/Backup)').item.json.status` | GHL API response |
| `p_appointment_status` | `$('Create Appointment (Primary/Backup)').item.json.appoinmentStatus` | GHL API response (note typo) |
| `p_created_source` | `'ai_automated'` | **HARDCODED - CRITICAL** |
| `p_source_workflow` | `'drive_ai_7'` | Hardcoded |

### Table: `appointments`

| Column | Expected Value |
|--------|----------------|
| `created_source` | `'ai_automated'` ← **KEY IDENTIFIER** |
| `source_workflow` | `'drive_ai_7'` |
| `outcome_status` | `'pending'` (default) |

---

## 5. DRIVE AI 7.0 - TASK PATH

### When It Fires
AI determines human intervention is needed (pricing question, call request, trade evaluation, etc.)

### PRIMARY Task Node

```json
{
  "nodes": [
    {
      "parameters": {
        "method": "POST",
        "url": "https://gamwimamcvgakcetdypm.supabase.co/rest/v1/rpc/upsert_task",
        "sendHeaders": true,
        "headerParameters": {
          "parameters": [
            {
              "name": "apikey",
              "value": "sb_publishable_1prVZrYhMgR-cvRLuiKnqw_bFet_YV1"
            },
            {
              "name": "Content-Type",
              "value": "application/json"
            }
          ]
        },
        "sendBody": true,
        "specifyBody": "json",
        "jsonBody": "={{ JSON.stringify({ p_task_id: $('Create Task').item.json.traceId, p_ghl_task_id: $('Create Task').item.json.task?.id, p_location_id: $('W').item.json.location_id, p_dealership_name: $('W').item.json.DealerName, p_dealership_address: $('W').item.json.location_fullAddress, p_dealership_hours: $('W').item.json.DealerHours, p_dealership_timezone: $('W').item.json.TimeZone, p_contact_id: $('W').item.json.contact_id, p_lead_name: $('W').item.json.full_name, p_lead_first_name: $('W').item.json.first_name, p_lead_phone: $('W').item.json.phone, p_lead_email: $('W').item.json.email, p_lead_tags: $('W').item.json.tags, p_title: $('Create Task').item.json.task?.title || 'Task', p_description: $('Create Task').item.json.task?.body, p_due_date: $('Create Task').item.json.task?.dueDate, p_assigned_rep_id: $('W').item.json.AssignedUserId, p_assigned_rep_name: (($('W').item.json.user_firstName || '') + ' ' + ($('W').item.json.user_lastName || '')).trim(), p_trigger_action: $('Action Guard').item.json.action || 'task', p_also_task: $('Action Guard').item.json.alsoTask === 'yes', p_lead_language: $('Decision: Action Only').item.json.message?.content?.language, p_lead_last_message: $('W').item.json.lead_response, p_drive_context: $('W').item.json.DriveContext }) }}",
        "options": {}
      },
      "id": "dca38aaa-c55c-4db1-b49f-04bfa6c62a48",
      "name": "Supabase: Task (Primary)",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 4.2,
      "position": [19104, 4416],
      "onError": "continueErrorOutput"
    }
  ]
}
```

### BACKUP Task Node

```json
{
  "nodes": [
    {
      "parameters": {
        "method": "POST",
        "url": "https://gamwimamcvgakcetdypm.supabase.co/rest/v1/rpc/upsert_task",
        "sendHeaders": true,
        "headerParameters": {
          "parameters": [
            {
              "name": "apikey",
              "value": "sb_publishable_1prVZrYhMgR-cvRLuiKnqw_bFet_YV1"
            },
            {
              "name": "Content-Type",
              "value": "application/json"
            }
          ]
        },
        "sendBody": true,
        "specifyBody": "json",
        "jsonBody": "={{ JSON.stringify({ p_task_id: $('Create Task1').item.json.traceId, p_ghl_task_id: $('Create Task1').item.json.task?.id, p_location_id: $('W').item.json.location_id, p_dealership_name: $('W').item.json.DealerName, p_dealership_address: $('W').item.json.location_fullAddress, p_dealership_hours: $('W').item.json.DealerHours, p_dealership_timezone: $('W').item.json.TimeZone, p_contact_id: $('W').item.json.contact_id, p_lead_name: $('W').item.json.full_name, p_lead_first_name: $('W').item.json.first_name, p_lead_phone: $('W').item.json.phone, p_lead_email: $('W').item.json.email, p_lead_tags: $('W').item.json.tags, p_title: $('Create Task1').item.json.task?.title || 'Task', p_description: $('Create Task1').item.json.task?.body, p_due_date: $('Create Task1').item.json.task?.dueDate, p_assigned_rep_id: $('W').item.json.AssignedUserId, p_assigned_rep_name: (($('W').item.json.user_firstName || '') + ' ' + ($('W').item.json.user_lastName || '')).trim(), p_trigger_action: $('Action Guard').item.json.action || 'task', p_also_task: $('Action Guard').item.json.alsoTask === 'yes', p_lead_language: $('Decision: Action Only').item.json.message?.content?.language, p_lead_last_message: $('W').item.json.lead_response, p_drive_context: $('W').item.json.DriveContext }) }}",
        "options": {}
      },
      "id": "c125bf98-de04-4279-b11f-1210da58a3b6",
      "name": "Supabase: Task (Backup)",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 4.2,
      "position": [20800, 3936],
      "onError": "continueErrorOutput"
    }
  ]
}
```

### Parameter Mapping (Both Primary & Backup)

| RPC Parameter | n8n Expression | Source |
|---------------|----------------|--------|
| `p_task_id` | `$('Create Task/Task1').item.json.traceId` | GHL API response |
| `p_ghl_task_id` | `$('Create Task/Task1').item.json.task?.id` | GHL API response |
| `p_location_id` | `$('W').item.json.location_id` | Webhook payload |
| `p_dealership_name` | `$('W').item.json.DealerName` | Webhook payload |
| `p_dealership_address` | `$('W').item.json.location_fullAddress` | Webhook payload |
| `p_dealership_hours` | `$('W').item.json.DealerHours` | Webhook payload |
| `p_dealership_timezone` | `$('W').item.json.TimeZone` | Webhook payload |
| `p_contact_id` | `$('W').item.json.contact_id` | Webhook payload |
| `p_lead_name` | `$('W').item.json.full_name` | Webhook payload |
| `p_lead_first_name` | `$('W').item.json.first_name` | Webhook payload |
| `p_lead_phone` | `$('W').item.json.phone` | Webhook payload |
| `p_lead_email` | `$('W').item.json.email` | Webhook payload |
| `p_lead_tags` | `$('W').item.json.tags` | Webhook payload |
| `p_title` | `$('Create Task/Task1').item.json.task?.title \|\| 'Task'` | GHL API response with fallback |
| `p_description` | `$('Create Task/Task1').item.json.task?.body` | GHL API response |
| `p_due_date` | `$('Create Task/Task1').item.json.task?.dueDate` | GHL API response |
| `p_assigned_rep_id` | `$('W').item.json.AssignedUserId` | Webhook payload |
| `p_assigned_rep_name` | `(($('W').item.json.user_firstName \|\| '') + ' ' + ($('W').item.json.user_lastName \|\| '')).trim()` | Concatenated |
| `p_trigger_action` | `$('Action Guard').item.json.action \|\| 'task'` | AI decision |
| `p_also_task` | `$('Action Guard').item.json.alsoTask === 'yes'` | AI decision (boolean) |
| `p_lead_language` | `$('Decision: Action Only').item.json.message?.content?.language` | AI output |
| `p_lead_last_message` | `$('W').item.json.lead_response` | Webhook payload |
| `p_drive_context` | `$('W').item.json.DriveContext` | Webhook payload |

### Table: `tasks`

| Column | Expected Value |
|--------|----------------|
| `completed` | `false` (default) |
| `completed_by_reactivation_id` | `NULL` (until closed) |

---

## 6. REACTIVATE DRIVE WORKFLOW

### Workflow Overview

**Name:** Reactivate Drive  
**Trigger:** Webhook POST (rep submits "Close the Loop" form)  
**Purpose:** Process rep instructions and close open tasks

### Decision Flow

```
Webhook (Rep Instruction Submitted)
         │
         ▼
    AI Analyzes Instruction
    (Decision: Action Only)
         │
         ├──────────────────┬──────────────────┐
         ▼                  ▼                  ▼
    FOLLOW_UP          APPOINTMENT          REMOVE
         │                  │                  │
         ▼                  ▼                  ▼
  Follow-up Planner   Appointment Planner   Direct to DB
         │                  │                  │
         ▼                  ▼                  ▼
  Supabase:           Supabase:           Supabase:
  Reactivation        Reactivation        Reactivation
  (Follow-up)         (Appointment)       (Remove)
```

### Key Upstream Nodes Referenced

| Node Name | Purpose | Data Provided |
|-----------|---------|---------------|
| `Webhook` | Form submission data | `body.location.id`, `body.contact_id`, `body.full_name`, `body['Dealer Name']`, `body['Customer Notes']`, `body['Drive Context']` |
| `Find Spec. Values` | Location config | `dealerHours` |
| `Finalize Payload` | Processed payload | `body.customData['Assigned User ID']` |
| `Get User Name` | Rep lookup | `name` |
| `Clean Note` | Processed instruction | `cleanedNote`, `rawNote` |
| `Decision: Action Only` | AI action decision | `message.content.action` |
| `Follow-up Planner` | AI follow-up details | `message.content.followUpMessage`, `message.content.followUpDate` |
| `Appointment Planner` | AI appointment details | `message.content.appointmentType`, `message.content.appointmenttime`, `message.content.appointmentSummary` |

---

## 7. REACTIVATE DRIVE - FOLLOW-UP PATH

### When It Fires
Rep instructs AI to follow up with the lead at a specific time.

### Exact n8n Node Configuration

```json
{
  "nodes": [
    {
      "parameters": {
        "method": "POST",
        "url": "https://gamwimamcvgakcetdypm.supabase.co/rest/v1/rpc/insert_reactivation",
        "sendHeaders": true,
        "headerParameters": {
          "parameters": [
            {
              "name": "apikey",
              "value": "sb_publishable_1prVZrYhMgR-cvRLuiKnqw_bFet_YV1"
            },
            {
              "name": "Content-Type",
              "value": "application/json"
            }
          ]
        },
        "sendBody": true,
        "specifyBody": "json",
        "jsonBody": "={{ JSON.stringify({ p_execution_id: $execution.id, p_location_id: $('Webhook').item.json.body.location?.id, p_dealership_name: $('Webhook').item.json.body['Dealer Name'], p_dealership_hours: $('Find Spec. Values').item.json.dealerHours, p_contact_id: $('Webhook').item.json.body.contact_id, p_lead_name: $('Webhook').item.json.body.full_name, p_lead_first_name: $('Webhook').item.json.body.first_name, p_lead_phone: $('Webhook').item.json.body.phone, p_lead_email: $('Webhook').item.json.body.email, p_assigned_rep_id: $('Finalize Payload').item.json.body.customData?.['Assigned User ID'], p_rep_name: $('Get User Name').item.json.name, p_instruction: $('Clean Note').item.json.cleanedNote, p_instruction_raw: $('Clean Note').item.json.rawNote, p_action: $('Decision: Action Only').item.json.message?.content?.action, p_follow_up_message: $('Follow-up Planner').item.json.message?.content?.followUpMessage, p_follow_up_date: $('Follow-up Planner').item.json.message?.content?.followUpDate, p_drive_context: $('Webhook').item.json.body['Drive Context'] }) }}",
        "options": {}
      },
      "id": "9e185034-9326-4e4c-81e1-d9e49807be99",
      "name": "Supabase: Reactivation (Follow-up)",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 4.2,
      "position": [8192, -256],
      "onError": "continueErrorOutput"
    }
  ]
}
```

### Parameter Mapping

| RPC Parameter | n8n Expression | Source |
|---------------|----------------|--------|
| `p_execution_id` | `$execution.id` | n8n execution ID |
| `p_location_id` | `$('Webhook').item.json.body.location?.id` | Form submission |
| `p_dealership_name` | `$('Webhook').item.json.body['Dealer Name']` | Form submission |
| `p_dealership_hours` | `$('Find Spec. Values').item.json.dealerHours` | Location config |
| `p_contact_id` | `$('Webhook').item.json.body.contact_id` | Form submission |
| `p_lead_name` | `$('Webhook').item.json.body.full_name` | Form submission |
| `p_lead_first_name` | `$('Webhook').item.json.body.first_name` | Form submission |
| `p_lead_phone` | `$('Webhook').item.json.body.phone` | Form submission |
| `p_lead_email` | `$('Webhook').item.json.body.email` | Form submission |
| `p_assigned_rep_id` | `$('Finalize Payload').item.json.body.customData?.['Assigned User ID']` | Processed payload |
| `p_rep_name` | `$('Get User Name').item.json.name` | GHL user lookup |
| `p_instruction` | `$('Clean Note').item.json.cleanedNote` | Processed instruction |
| `p_instruction_raw` | `$('Clean Note').item.json.rawNote` | Raw instruction |
| `p_action` | `$('Decision: Action Only').item.json.message?.content?.action` | AI decision (should be `'follow_up'`) |
| `p_follow_up_message` | `$('Follow-up Planner').item.json.message?.content?.followUpMessage` | AI-generated message |
| `p_follow_up_date` | `$('Follow-up Planner').item.json.message?.content?.followUpDate` | AI-determined date |
| `p_drive_context` | `$('Webhook').item.json.body['Drive Context']` | Form submission |

### Table: `reactivations`

| Column | Expected Value |
|--------|----------------|
| `action` | `'follow_up'` |
| `follow_up_message` | AI-generated message |
| `follow_up_date` | Scheduled date/time |
| `instruction` | Rep's cleaned instruction |
| `instruction_length` | Calculated by RPC |
| `instruction_word_count` | Calculated by RPC |

---

## 8. REACTIVATE DRIVE - APPOINTMENT PATH

### When It Fires
Rep instructs AI to book an appointment.

### Exact n8n Node Configuration

```json
{
  "nodes": [
    {
      "parameters": {
        "method": "POST",
        "url": "https://gamwimamcvgakcetdypm.supabase.co/rest/v1/rpc/insert_reactivation",
        "sendHeaders": true,
        "headerParameters": {
          "parameters": [
            {
              "name": "apikey",
              "value": "sb_publishable_1prVZrYhMgR-cvRLuiKnqw_bFet_YV1"
            },
            {
              "name": "Content-Type",
              "value": "application/json"
            }
          ]
        },
        "sendBody": true,
        "specifyBody": "json",
        "jsonBody": "={{ JSON.stringify({ p_execution_id: $execution.id, p_location_id: $('Webhook').item.json.body.location?.id, p_dealership_name: $('Webhook').item.json.body['Dealer Name'], p_dealership_hours: $('Find Spec. Values').item.json.dealerHours, p_contact_id: $('Webhook').item.json.body.contact_id, p_lead_name: $('Webhook').item.json.body.full_name, p_lead_first_name: $('Webhook').item.json.body.first_name, p_lead_phone: $('Webhook').item.json.body.phone, p_lead_email: $('Webhook').item.json.body.email, p_assigned_rep_id: $('Finalize Payload').item.json.body.customData?.['Assigned User ID'], p_rep_name: $('Get User Name').item.json.name, p_instruction: $('Clean Note').item.json.cleanedNote, p_instruction_raw: $('Clean Note').item.json.rawNote, p_action: $('Decision: Action Only').item.json.message?.content?.action, p_appointment_type: $('Appointment Planner').item.json.message?.content?.appointmentType, p_appointment_time: $('Appointment Planner').item.json.message?.content?.appointmenttime, p_appointment_summary: $('Appointment Planner').item.json.message?.content?.appointmentSummary, p_drive_context: $('Webhook').item.json.body['Drive Context'] }) }}",
        "options": {}
      },
      "id": "cfa50b13-c21b-47f6-b6b8-55d9da02a05b",
      "name": "Supabase: Reactivation (Appointment)",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 4.2,
      "position": [9440, -944],
      "onError": "continueErrorOutput"
    }
  ]
}
```

### Parameter Mapping

| RPC Parameter | n8n Expression | Source |
|---------------|----------------|--------|
| `p_execution_id` | `$execution.id` | n8n execution ID |
| `p_location_id` | `$('Webhook').item.json.body.location?.id` | Form submission |
| `p_dealership_name` | `$('Webhook').item.json.body['Dealer Name']` | Form submission |
| `p_dealership_hours` | `$('Find Spec. Values').item.json.dealerHours` | Location config |
| `p_contact_id` | `$('Webhook').item.json.body.contact_id` | Form submission |
| `p_lead_name` | `$('Webhook').item.json.body.full_name` | Form submission |
| `p_lead_first_name` | `$('Webhook').item.json.body.first_name` | Form submission |
| `p_lead_phone` | `$('Webhook').item.json.body.phone` | Form submission |
| `p_lead_email` | `$('Webhook').item.json.body.email` | Form submission |
| `p_assigned_rep_id` | `$('Finalize Payload').item.json.body.customData?.['Assigned User ID']` | Processed payload |
| `p_rep_name` | `$('Get User Name').item.json.name` | GHL user lookup |
| `p_instruction` | `$('Clean Note').item.json.cleanedNote` | Processed instruction |
| `p_instruction_raw` | `$('Clean Note').item.json.rawNote` | Raw instruction |
| `p_action` | `$('Decision: Action Only').item.json.message?.content?.action` | AI decision (should be `'appointment'`) |
| `p_appointment_type` | `$('Appointment Planner').item.json.message?.content?.appointmentType` | AI planner |
| `p_appointment_time` | `$('Appointment Planner').item.json.message?.content?.appointmenttime` | AI planner |
| `p_appointment_summary` | `$('Appointment Planner').item.json.message?.content?.appointmentSummary` | AI planner |
| `p_drive_context` | `$('Webhook').item.json.body['Drive Context']` | Form submission |

### Table: `reactivations`

| Column | Expected Value |
|--------|----------------|
| `action` | `'appointment'` |
| `appointment_type` | AI-determined type |
| `appointment_time` | Scheduled date/time |
| `appointment_summary` | AI-generated summary |

### Also Creates: `appointments` table

| Column | Expected Value |
|--------|----------------|
| `created_source` | `'rep_instructed'` ← **KEY IDENTIFIER** |
| `reactivation_id` | Links to reactivation record |

---

## 9. REACTIVATE DRIVE - REMOVE PATH

### When It Fires
Rep instructs AI to stop working a lead.

### Exact n8n Node Configuration

```json
{
  "nodes": [
    {
      "parameters": {
        "method": "POST",
        "url": "https://gamwimamcvgakcetdypm.supabase.co/rest/v1/rpc/insert_reactivation",
        "sendHeaders": true,
        "headerParameters": {
          "parameters": [
            {
              "name": "apikey",
              "value": "sb_publishable_1prVZrYhMgR-cvRLuiKnqw_bFet_YV1"
            },
            {
              "name": "Content-Type",
              "value": "application/json"
            }
          ]
        },
        "sendBody": true,
        "specifyBody": "json",
        "jsonBody": "={{ JSON.stringify({ p_execution_id: $execution.id, p_location_id: $('Webhook').item.json.body.location?.id, p_dealership_name: $('Webhook').item.json.body['Dealer Name'], p_dealership_hours: $('Find Spec. Values').item.json.dealerHours, p_contact_id: $('Webhook').item.json.body.contact_id, p_lead_name: $('Webhook').item.json.body.full_name, p_lead_first_name: $('Webhook').item.json.body.first_name, p_lead_phone: $('Webhook').item.json.body.phone, p_lead_email: $('Webhook').item.json.body.email, p_assigned_rep_id: $('Finalize Payload').item.json.body.customData?.['Assigned User ID'], p_rep_name: $('Get User Name').item.json.name, p_instruction: $('Clean Note').item.json.cleanedNote, p_instruction_raw: $('Clean Note').item.json.rawNote, p_action: 'remove', p_drive_context: $('Webhook').item.json.body['Drive Context'] }) }}",
        "options": {}
      },
      "id": "bd970238-b5bb-4151-8c37-ecf72f585548",
      "name": "Supabase: Reactivation (Remove)",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 4.2,
      "position": [7392, -1232],
      "onError": "continueErrorOutput"
    }
  ]
}
```

### Sample Response (from pinData)

```json
{
  "success": true,
  "reactivation_id": "e31266c0-4222-45c7-a5d2-20af56abcce6",
  "tasks_completed": 0,
  "instruction_length": 4,
  "instruction_word_count": 1,
  "action": "remove",
  "lead_type": null
}
```

### Parameter Mapping

| RPC Parameter | n8n Expression | Source |
|---------------|----------------|--------|
| `p_execution_id` | `$execution.id` | n8n execution ID |
| `p_location_id` | `$('Webhook').item.json.body.location?.id` | Form submission |
| `p_dealership_name` | `$('Webhook').item.json.body['Dealer Name']` | Form submission |
| `p_dealership_hours` | `$('Find Spec. Values').item.json.dealerHours` | Location config |
| `p_contact_id` | `$('Webhook').item.json.body.contact_id` | Form submission |
| `p_lead_name` | `$('Webhook').item.json.body.full_name` | Form submission |
| `p_lead_first_name` | `$('Webhook').item.json.body.first_name` | Form submission |
| `p_lead_phone` | `$('Webhook').item.json.body.phone` | Form submission |
| `p_lead_email` | `$('Webhook').item.json.body.email` | Form submission |
| `p_assigned_rep_id` | `$('Finalize Payload').item.json.body.customData?.['Assigned User ID']` | Processed payload |
| `p_rep_name` | `$('Get User Name').item.json.name` | GHL user lookup |
| `p_instruction` | `$('Clean Note').item.json.cleanedNote` | Processed instruction |
| `p_instruction_raw` | `$('Clean Note').item.json.rawNote` | Raw instruction |
| `p_action` | `'remove'` | **HARDCODED** |
| `p_drive_context` | `$('Webhook').item.json.body['Drive Context']` | Form submission |

### Table: `reactivations`

| Column | Expected Value |
|--------|----------------|
| `action` | `'remove'` |
| `tasks_completed_count` | Number of tasks closed |

### ⚠️ IMPORTANT: AI Remove vs Rep Remove

| Type | Table | How to Identify |
|------|-------|-----------------|
| **AI Remove** | `ai_decisions` | `action = 'remove'` |
| **Rep Remove** | `reactivations` | `action = 'remove'` |

**They are NOT the same!** Different tables, different sources.

---

## 10. GHL WEBHOOKS

### Edge Function URLs

| Webhook | URL |
|---------|-----|
| Lead Created | `https://gamwimamcvgakcetdypm.supabase.co/functions/v1/ghl-lead-webhook` |
| Outbound Sent | `https://gamwimamcvgakcetdypm.supabase.co/functions/v1/ghl-outbound-webhook` |
| Response Received | `https://gamwimamcvgakcetdypm.supabase.co/functions/v1/ghl-response-webhook` |
| Appointment Outcome | `https://gamwimamcvgakcetdypm.supabase.co/functions/v1/ghl-appointment-webhook` |

### Required GHL Headers

```
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdhbXdpbWFtY3ZnYWtjZXRkeXBtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcwNDM0NzAsImV4cCI6MjA4MjYxOTQ3MH0.CuhNBluIOX6bMukLuvnmtd6gCq1k8fTVAL-xRDcUbis
Content-Type: application/json
```

### Webhook 1: Lead Created

**Trigger:** GHL "Contact Created"  
**RPC:** `insert_lead_from_ghl(payload JSONB)`

**Table:** `leads` (INSERT)

| Column | Source |
|--------|--------|
| `contact_id` | GHL contact ID |
| `location_id` | GHL location ID |
| `lead_type` | Classified from tags |
| `lead_source` | Raw source |
| `lead_source_normalized` | Cleaned source |
| `lead_name` | Full name |
| `lead_phone` | Phone |
| `lead_email` | Email |
| `lead_date` | Timestamp |

### Webhook 2: First Outbound Sent

**Trigger:** GHL "Message Sent" (first only)  
**RPC:** `update_lead_outbound_ghl(payload JSONB)`

**Table:** `leads` (UPDATE)

| Column | Value |
|--------|-------|
| `first_outbound_at` | Timestamp |
| `first_outbound_type` | Channel (sms/email/chat) |
| `speed_to_lead_seconds` | Calculated |

### Webhook 3: First Response Received

**Trigger:** GHL "Message Received" (first only)
**RPC:** `update_lead_response_ghl(payload JSONB)`

**Table:** `leads` (UPDATE)

| Column | Value |
|--------|-------|
| `first_response_at` | Timestamp |
| `responded` | `true` |
| `time_to_response_minutes` | Calculated |

**⚠️ IMPORTANT: GHL Status Field Conflict (Fixed Jan 19, 2026)**

Raw GHL payloads contain a `status` field with values like `"new"`, `"open"`, `"won"`, `"lost"`, etc. However, the `leads.status` column has a CHECK constraint (`chk_leads_status`) that only allows: `'active'`, `'converted'`, `'removed'`.

**The Fix:** The `update_lead_response_ghl` RPC function was updated to:
1. **Only update response-related fields** (`first_response_at`, `responded`, `time_to_response_minutes`)
2. **Never touch the `status` column** - prevents constraint violations
3. **Skip if already responded** - only tracks first response

**RPC Function Logic:**
```sql
-- Only update response-related fields (NEVER touch status)
UPDATE leads
SET
    first_response_at = COALESCE(first_response_at, NOW()),
    responded = true,
    time_to_response_minutes = CASE
        WHEN first_response_at IS NULL AND first_outbound_at IS NOT NULL
        THEN EXTRACT(EPOCH FROM (NOW() - first_outbound_at)) / 60
        ELSE time_to_response_minutes
    END,
    updated_at = NOW()
WHERE contact_id = v_contact_id
  AND first_response_at IS NULL;  -- Only update if not already responded
```

---

## 11. VERIFICATION QUERIES

### Master Count Query

```sql
SELECT 
  -- AI Decisions by type
  (SELECT COUNT(*) FROM ai_decisions WHERE action = 'task') as ai_decision_tasks,
  (SELECT COUNT(*) FROM ai_decisions WHERE action = 'appointment') as ai_decision_appointments,
  (SELECT COUNT(*) FROM ai_decisions WHERE action = 'remove') as ai_decision_removes,
  (SELECT COUNT(*) FROM ai_decisions WHERE action = 'follow_up') as ai_decision_followups,
  
  -- Reactivations by type
  (SELECT COUNT(*) FROM reactivations WHERE action = 'follow_up') as reactivation_followups,
  (SELECT COUNT(*) FROM reactivations WHERE action = 'appointment') as reactivation_appointments,
  (SELECT COUNT(*) FROM reactivations WHERE action = 'remove') as reactivation_removes,
  
  -- Tasks
  (SELECT COUNT(*) FROM tasks) as total_tasks,
  (SELECT COUNT(*) FROM tasks WHERE completed = true) as completed_tasks,
  (SELECT COUNT(*) FROM tasks WHERE completed = false) as pending_tasks,
  
  -- Appointments by source
  (SELECT COUNT(*) FROM appointments WHERE created_source = 'ai_automated') as ai_booked_appointments,
  (SELECT COUNT(*) FROM appointments WHERE created_source = 'rep_instructed') as rep_booked_appointments,
  
  -- Leads
  (SELECT COUNT(*) FROM leads) as total_leads,
  (SELECT COUNT(*) FROM leads WHERE first_outbound_at IS NOT NULL) as leads_with_outbound,
  (SELECT COUNT(*) FROM leads WHERE responded = true) as leads_responded;
```

### Recent Activity by Source

```sql
-- Recent AI decisions
SELECT action, COUNT(*), MAX(decided_at) as latest
FROM ai_decisions
WHERE decided_at > NOW() - INTERVAL '24 hours'
GROUP BY action;

-- Recent reactivations
SELECT action, COUNT(*), MAX(reactivated_at) as latest
FROM reactivations
WHERE reactivated_at > NOW() - INTERVAL '24 hours'
GROUP BY action;

-- Recent appointments by source
SELECT created_source, COUNT(*), MAX(created_at) as latest
FROM appointments
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY created_source;
```

---

## 12. DATA RELATIONSHIPS & RED FLAGS

### Expected Relationships

| Check | Expected |
|-------|----------|
| `ai_decisions` WHERE action='task' | ≈ `tasks` count |
| `ai_decisions` WHERE action='appointment' | ≈ `appointments` WHERE created_source='ai_automated' |
| `reactivations` WHERE action='appointment' | ≈ `appointments` WHERE created_source='rep_instructed' |
| `tasks` WHERE completed=true | = `task_completions` count |

### Red Flags

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| `ai_decisions` empty | Supabase node not firing in Drive AI 7.0 | Check workflow execution logs |
| `tasks` exist but no `ai_decisions` | Missing `insert_ai_decision` call | Add node before task creation |
| Appointments have wrong `created_source` | Hardcoded value incorrect | Verify `'ai_automated'` vs `'rep_instructed'` |
| `reactivations` empty | Reactivate Drive not sending to Supabase | Check workflow |
| `leads` but no `first_outbound_at` | GHL outbound webhook not configured | Configure webhook in GHL |
| No `speed_to_lead_seconds` | Edge function calculation issue | Check RPC function |
| Tasks not completing | `insert_reactivation` not linking tasks | Verify `contact_id` matching |

---

## 13. FULL WORKFLOW JSON REFERENCE

### Drive AI 7.0 Workflow Metadata

```json
{
  "name": "Drive AI 7.0",
  "webhook_path": "17ea8cfc-a0ba-40e5-8683-9b0e399a9d7b",
  "supabase_nodes": [
    {
      "name": "Log AI Remove",
      "id": "28ed59a9-4c8d-4ba6-8191-59908946e56f",
      "rpc": "insert_ai_decision",
      "position": [18608, 3552]
    },
    {
      "name": "Supabase: Appt (Primary)",
      "id": "0fe7346d-4778-4775-aea0-ea282c4f36ca",
      "rpc": "insert_appointment",
      "position": [19104, 3648]
    },
    {
      "name": "Supabase: Appt (Backup)",
      "id": "fe900b90-04ad-4659-912f-5584ecf12ced",
      "rpc": "insert_appointment",
      "position": [19328, 3840]
    },
    {
      "name": "Supabase: Task (Primary)",
      "id": "dca38aaa-c55c-4db1-b49f-04bfa6c62a48",
      "rpc": "upsert_task",
      "position": [19104, 4416]
    },
    {
      "name": "Supabase: Task (Backup)",
      "id": "c125bf98-de04-4279-b11f-1210da58a3b6",
      "rpc": "upsert_task",
      "position": [20800, 3936]
    }
  ],
  "key_data_nodes": [
    "W (Webhook alias)",
    "Create Appointment (Primary)",
    "Create Appointment (Backup)",
    "Create Task",
    "Create Task1",
    "Appointment Planner",
    "Action Guard",
    "Decision: Action Only"
  ]
}
```

### Reactivate Drive Workflow Metadata

```json
{
  "name": "Reactivate Drive",
  "supabase_nodes": [
    {
      "name": "Supabase: Reactivation (Follow-up)",
      "id": "9e185034-9326-4e4c-81e1-d9e49807be99",
      "rpc": "insert_reactivation",
      "position": [8192, -256]
    },
    {
      "name": "Supabase: Reactivation (Appointment)",
      "id": "cfa50b13-c21b-47f6-b6b8-55d9da02a05b",
      "rpc": "insert_reactivation",
      "position": [9440, -944]
    },
    {
      "name": "Supabase: Reactivation (Remove)",
      "id": "bd970238-b5bb-4151-8c37-ecf72f585548",
      "rpc": "insert_reactivation",
      "position": [7392, -1232]
    }
  ],
  "key_data_nodes": [
    "Webhook",
    "Find Spec. Values",
    "Finalize Payload",
    "Get User Name",
    "Clean Note",
    "Decision: Action Only",
    "Follow-up Planner",
    "Appointment Planner"
  ]
}
```

---

## SUMMARY: WHAT MUST BE FLOWING

| Source | Node Name | RPC Function | Key Identifier |
|--------|-----------|--------------|----------------|
| Drive AI 7.0 | Log AI Remove | `insert_ai_decision` | `action = 'remove'` |
| Drive AI 7.0 | Supabase: Appt (Primary/Backup) | `insert_appointment` | `created_source = 'ai_automated'` |
| Drive AI 7.0 | Supabase: Task (Primary/Backup) | `upsert_task` | `completed = false` |
| Reactivate Drive | Supabase: Reactivation (Follow-up) | `insert_reactivation` | `action = 'follow_up'` |
| Reactivate Drive | Supabase: Reactivation (Appointment) | `insert_reactivation` | `action = 'appointment'` |
| Reactivate Drive | Supabase: Reactivation (Remove) | `insert_reactivation` | `action = 'remove'` |
| GHL Webhook | Edge Function | `insert_lead_from_ghl` | `lead_date` populated |
| GHL Webhook | Edge Function | `update_lead_outbound_ghl` | `speed_to_lead_seconds` calculated |
| GHL Webhook | Edge Function | `update_lead_response_ghl` | `responded = true` |

---

*This document contains the exact n8n node configurations as of January 19, 2026. Any changes to the workflows should be reflected here to maintain accurate documentation.*

---

## CHANGELOG

### v7.0.1 (January 19, 2026)
- **Fixed:** `update_lead_response_ghl` RPC function to prevent `chk_leads_status` constraint violations
- **Issue:** GHL payloads contain `status` values like "new", "open", "won" which conflict with leads table constraint (only allows 'active', 'converted', 'removed')
- **Solution:** Updated RPC to only update response-related fields, never touching the `status` column
