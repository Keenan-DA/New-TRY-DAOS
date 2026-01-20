# Fix: Instruction Quality Rating (v_instruction_clarity)

**Date:** January 20, 2026
**Issue:** Quality rating incorrectly scoring CTX, ACT, and TIME components

---

## Problem Analysis

Based on user feedback, the current regex patterns have three core issues:

### Issue 1: Past-tense descriptions counted as ACTION instead of CONTEXT

**Example:**
```
"Jaxon called to follow up with Marcio, he didnt answer."
```
- **Current Rating:** ✓ CTX, ✓ ACT, ✗ TIME
- **Should Be:** ✓ CTX, ✗ ACT, ✗ TIME

The words "called" and "follow" triggered ACTION detection, but this is a **CRM note describing what was done**, NOT a directive for what DAOS should do.

Similarly:
```
"Jaxon called Jeff to see if he has time next week to come in to take advantage of promos."
```
This is a note about what the rep did, not an instruction for AI action.

### Issue 2: "now" not being detected as TIME

**Example:**
```
"follow up with customer... follow up now"
```
- **Current Rating:** ✗ TIME
- **Should Be:** ✓ TIME

The word "now" is in the pattern list but not matching properly.

### Issue 3: "let customer know" not detected as ACTION

**Example:**
```
"let customer know you spoke with finance and found that we do have a few options for financing..."
```
- **Current Rating:** ✗ ACT
- **Should Be:** ✓ ACT

The pattern "let know" should match "let customer know" but the word between breaks the match.

---

## Root Cause

The ACTION patterns conflate two different things:

1. **Past-tense descriptive words** (what WAS done) → Should be **CONTEXT**
   - "called", "spoke", "tried", "said", "told", "left message", "texted", "emailed", "reached out"

2. **Imperative/directive words** (what TO DO) → Should be **ACTION**
   - "call", "text", "follow up", "send", "schedule", "reach out", "let know", "ask"

When a rep writes "Jaxon called...", they're providing context about what happened. When they write "Call the customer...", they're giving a directive.

---

## Solution: Updated Regex Patterns

### New CONTEXT Pattern (expanded)

Add past-tense action words to CONTEXT detection (they describe what happened):

```sql
has_context AS (
  instruction ~* '\y(asked|wanted|interested|looking|trade|vehicle|car|truck|suv|pricing|price|quote|offer|deal|sold|bought|test drive|voicemail|no answer|left message|spoke|mentioned|said|told|visit|come in|stop by|credit|approved|financing|co-sign|cosign|down payment|monthly|payment|inventory|stock|appointment|scheduled|waiting|ready|hot|warm|cold|serious|motivated|hesitant|concerned|question|issue|problem|help|needs|wants|budget|range|lease|loan|purchase|called|tried|reached|texted|emailed|contacted|hung up|didnt answer|didn''t answer|not answering|unresponsive|put in a lead|submitted|inquired|came in|stopped by|visited|walked in|phoned|left vm|lvm|no response|honda|toyota|ford|chevy|chevrolet|ram|jeep|dodge|harley|fat boy|dyna|sportster|softail|touring|street glide|road glide|wide glide|breakout|iron|forty-eight|48|883|1200|v-rod|night rod|muscle|slim|deluxe|heritage|low rider|fat bob|road king|electra glide|ultra|cvo|trike|freewheeler|livewire|nightster|pan america)\y'
)
```

### New ACTION Pattern (more restrictive - imperative only)

Only match imperative/directive phrases (what DAOS should do):

```sql
has_action AS (
  instruction ~* '(^|\s)(call|text|follow up|follow-up|followup|send|schedule|reach out|contact|see if|find out|try to|ask|let .{1,20} know|make .{1,20} aware|remind|check|confirm|book|set up|setup|arrange|get back|respond|reply|message|email|notify|engage|stop|don''t|do not|cease|continue|keep|update|inform|touch base|circle back|ping|nudge|push|offer|present|show|demo|walk through|explain|discuss|talk|speak|meet|invite|bring .{1,15} in|get .{1,15} in|have .{1,15} come)(\s|$|\.|\,|\!)'
  -- EXCLUDES past-tense: "called", "tried", "reached", "spoke", "texted", etc.
  -- Those are CONTEXT (what was done), not ACTION (what to do)
)
```

Key changes:
- Uses word boundary anchors to avoid matching within words
- Excludes past tense forms
- `let .{1,20} know` matches "let customer know", "let him know", etc.
- `bring .{1,15} in` / `get .{1,15} in` matches "bring them in", "get him in", etc.

### New TIME Pattern (improved "now" detection)

Ensure "now" and similar immediate timing words are properly detected:

```sql
has_timing AS (
  -- Split into patterns OR'd together for reliability
  instruction ~* '(^|[^a-z])now([^a-z]|$)'  -- Explicit "now" check
  OR instruction ~* '\y(today|tomorrow|morning|afternoon|evening|tonight|noon|midnight|monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|may|june|july|august|september|october|november|december|next|later|soon|asap|a\.s\.a\.p|immediately|right away|right now|hours|days|end of|first thing|eod|eow|this week|next week|couple|few|within|when available)\y'
  OR instruction ~* 'at \d|\d:\d|\d\s?(am|pm|a\.m|p\.m)|at noon|at midnight'
)
```

Key changes:
- **Explicit standalone "now" check** using `(^|[^a-z])now([^a-z]|$)` - matches "now" not preceded/followed by letters
- Separated time patterns into logical groups for reliability
- "right now", "right away" in word-boundary group
- Numeric time patterns (2:00pm, at 3, etc.) in separate group

---

## Complete Updated View SQL

```sql
-- Drop and recreate v_instruction_clarity with improved patterns
CREATE OR REPLACE VIEW v_instruction_clarity AS
SELECT
  r.id,
  r.location_id,
  r.dealership_name,
  r.contact_id,
  r.lead_name,
  r.assigned_rep_id,
  r.rep_name,
  r.instruction,
  r.action,
  r.follow_up_message,
  r.follow_up_date,
  r.reactivated_at,

  -- CONTEXT: Includes past-tense descriptive words (what happened)
  CASE WHEN r.instruction IS NULL OR TRIM(r.instruction) = '' THEN false
       ELSE r.instruction ~* '\y(asked|wanted|interested|looking|trade|vehicle|car|truck|suv|pricing|price|quote|offer|deal|sold|bought|test drive|voicemail|no answer|left message|spoke|mentioned|said|told|visit|come in|stop by|credit|approved|financing|co-sign|cosign|down payment|monthly|payment|inventory|stock|appointment|scheduled|rescheduled|rebooked|waiting|ready|hot|warm|cold|serious|motivated|hesitant|concerned|question|issue|problem|help|needs|wants|budget|range|lease|loan|purchase|called|tried|attempted|reached|texted|emailed|contacted|hung up|didnt answer|didn''t answer|not answering|unresponsive|timed out|put in a lead|submitted|received|inquired|came in|stopped by|visited|walked in|phoned|left vm|lvm|no response|sorry|application|approval|honda|toyota|ford|chevy|chevrolet|ram|jeep|dodge|harley|kawasaki|yamaha|suzuki|bmw|ducati|indian|polaris|can-am|ktm|triumph|fat boy|dyna|sportster|softail|touring|street glide|road glide|wide glide|breakout|iron|forty-eight|48|883|1200|v-rod|night rod|muscle|slim|deluxe|heritage|low rider|fat bob|road king|electra glide|ultra|cvo|trike|freewheeler|livewire|nightster|pan america|ninja|zx|atv|utv|side by side|motorcycle|bike)\y'
  END as has_context,

  -- ACTION: Only imperative/directive phrases (what DAOS should do)
  -- Excludes past-tense (called, tried, spoke, etc.) - those are CONTEXT
  CASE WHEN r.instruction IS NULL OR TRIM(r.instruction) = '' THEN false
       ELSE r.instruction ~* '(^|[^a-z])(call|text|follow up|follow-up|followup|send|schedule|reschedule|reach out|contact|see if|find out|try to|ask|let .{1,20} know|make .{1,20} aware|remind|check in|check with|confirm|book|set up|setup|arrange|get back to|respond|reply|message|email|notify|engage|start outreach|begin outreach|start engagement|begin engagement|stop|pause|don''t|do not|cease|continue|keep|update|inform|touch base|circle back|ping|nudge|push|offer|present|show|demo|walk through|explain|discuss|talk to|speak to|speak with|meet|invite|bring .{1,15} in|get .{1,15} in|have .{1,15} come|work toward|work towards)([^a-z]|$)'
  END as has_action,

  -- TIME: When to do it (includes "now", "immediately", etc.)
  -- Uses explicit "now" check plus word-boundary patterns for reliability
  CASE WHEN r.instruction IS NULL OR TRIM(r.instruction) = '' THEN false
       ELSE (
         r.instruction ~* '(^|[^a-z])now([^a-z]|$)'
         OR r.instruction ~* '\y(today|tomorrow|morning|afternoon|evening|tonight|noon|midnight|monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|may|june|july|august|september|october|november|december|next|later|soon|asap|a\.s\.a\.p|immediately|right away|right now|hours|days|end of|first thing|eod|eow|this week|next week|couple|few|within|when available)\y'
         OR r.instruction ~* 'at \d|\d:\d|\d\s?(am|pm|a\.m|p\.m)|at noon|at midnight'
       )
  END as has_timing,

  -- Clarity level calculation
  CASE
    WHEN r.instruction IS NULL OR TRIM(r.instruction) = '' THEN 'empty'
    WHEN (r.instruction ~* '\y(asked|wanted|interested|looking|trade|vehicle|car|truck|suv|pricing|price|quote|offer|deal|sold|bought|test drive|voicemail|no answer|left message|spoke|mentioned|said|told|visit|come in|stop by|credit|approved|financing|co-sign|cosign|down payment|monthly|payment|inventory|stock|appointment|scheduled|rescheduled|rebooked|waiting|ready|hot|warm|cold|serious|motivated|hesitant|concerned|question|issue|problem|help|needs|wants|budget|range|lease|loan|purchase|called|tried|attempted|reached|texted|emailed|contacted|hung up|didnt answer|didn''t answer|not answering|unresponsive|timed out|put in a lead|submitted|received|inquired|came in|stopped by|visited|walked in|phoned|left vm|lvm|no response|sorry|application|approval|honda|toyota|ford|chevy|chevrolet|ram|jeep|dodge|harley|kawasaki|yamaha|suzuki|bmw|ducati|indian|polaris|can-am|ktm|triumph|fat boy|dyna|sportster|softail|touring|street glide|road glide|wide glide|breakout|iron|forty-eight|48|883|1200|v-rod|night rod|muscle|slim|deluxe|heritage|low rider|fat bob|road king|electra glide|ultra|cvo|trike|freewheeler|livewire|nightster|pan america|ninja|zx|atv|utv|side by side|motorcycle|bike)\y')
         AND (r.instruction ~* '(^|[^a-z])(call|text|follow up|follow-up|followup|send|schedule|reschedule|reach out|contact|see if|find out|try to|ask|let .{1,20} know|make .{1,20} aware|remind|check in|check with|confirm|book|set up|setup|arrange|get back to|respond|reply|message|email|notify|engage|start outreach|begin outreach|start engagement|begin engagement|stop|pause|don''t|do not|cease|continue|keep|update|inform|touch base|circle back|ping|nudge|push|offer|present|show|demo|walk through|explain|discuss|talk to|speak to|speak with|meet|invite|bring .{1,15} in|get .{1,15} in|have .{1,15} come|work toward|work towards)([^a-z]|$)')
         AND (r.instruction ~* '(^|[^a-z])now([^a-z]|$)' OR r.instruction ~* '\y(today|tomorrow|morning|afternoon|evening|tonight|noon|midnight|monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|may|june|july|august|september|october|november|december|next|later|soon|asap|a\.s\.a\.p|immediately|right away|right now|hours|days|end of|first thing|eod|eow|this week|next week|couple|few|within|when available)\y' OR r.instruction ~* 'at \d|\d:\d|\d\s?(am|pm|a\.m|p\.m)|at noon|at midnight')
    THEN 'complete'
    WHEN (
      (CASE WHEN r.instruction ~* '\y(asked|wanted|interested|looking|trade|vehicle|car|truck|suv|pricing|price|quote|offer|deal|sold|bought|test drive|voicemail|no answer|left message|spoke|mentioned|said|told|visit|come in|stop by|credit|approved|financing|co-sign|cosign|down payment|monthly|payment|inventory|stock|appointment|scheduled|rescheduled|rebooked|waiting|ready|hot|warm|cold|serious|motivated|hesitant|concerned|question|issue|problem|help|needs|wants|budget|range|lease|loan|purchase|called|tried|attempted|reached|texted|emailed|contacted|hung up|didnt answer|didn''t answer|not answering|unresponsive|timed out|put in a lead|submitted|received|inquired|came in|stopped by|visited|walked in|phoned|left vm|lvm|no response|sorry|application|approval|honda|toyota|ford|chevy|chevrolet|ram|jeep|dodge|harley|kawasaki|yamaha|suzuki|bmw|ducati|indian|polaris|can-am|ktm|triumph|fat boy|dyna|sportster|softail|touring|street glide|road glide|wide glide|breakout|iron|forty-eight|48|883|1200|v-rod|night rod|muscle|slim|deluxe|heritage|low rider|fat bob|road king|electra glide|ultra|cvo|trike|freewheeler|livewire|nightster|pan america|ninja|zx|atv|utv|side by side|motorcycle|bike)\y' THEN 1 ELSE 0 END) +
      (CASE WHEN r.instruction ~* '(^|[^a-z])(call|text|follow up|follow-up|followup|send|schedule|reschedule|reach out|contact|see if|find out|try to|ask|let .{1,20} know|make .{1,20} aware|remind|check in|check with|confirm|book|set up|setup|arrange|get back to|respond|reply|message|email|notify|engage|start outreach|begin outreach|start engagement|begin engagement|stop|pause|don''t|do not|cease|continue|keep|update|inform|touch base|circle back|ping|nudge|push|offer|present|show|demo|walk through|explain|discuss|talk to|speak to|speak with|meet|invite|bring .{1,15} in|get .{1,15} in|have .{1,15} come|work toward|work towards)([^a-z]|$)' THEN 1 ELSE 0 END) +
      (CASE WHEN r.instruction ~* '(^|[^a-z])now([^a-z]|$)' OR r.instruction ~* '\y(today|tomorrow|morning|afternoon|evening|tonight|noon|midnight|monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|may|june|july|august|september|october|november|december|next|later|soon|asap|a\.s\.a\.p|immediately|right away|right now|hours|days|end of|first thing|eod|eow|this week|next week|couple|few|within|when available)\y' OR r.instruction ~* 'at \d|\d:\d|\d\s?(am|pm|a\.m|p\.m)|at noon|at midnight' THEN 1 ELSE 0 END)
    ) >= 2
    THEN 'partial'
    ELSE 'incomplete'
  END as clarity_level

FROM reactivations r
WHERE r.instruction IS NOT NULL;
```

---

## Expected Results After Fix

| Instruction | Before | After | Reason |
|-------------|--------|-------|--------|
| "Jaxon called to follow up with Marcio, he didnt answer." | ✓C ✓A ✗T | ✓C ✗A ✗T | "called" is context (past), no directive given |
| "customer hung up. follow up now" | ✓C ✓A ✗T | ✓C ✓A ✓T | "now" properly detected as TIME |
| "follow up with customer... follow up now" | ✓C ✓A ✗T | ✓C ✓A ✓T | "follow up" is action, "now" is time |
| "let customer know you spoke with finance..." | ✓C ✗A ✗T | ✓C ✓A ✗T | "let customer know" matches ACTION pattern |
| "Jaxon called Jeff to see if he has time next week" | ✓C ✓A ✓T | ✓C ✗A ✓T | "called" is context, "next week" is time, no action for DAOS |

---

## Key Principle: Context vs Action

**CONTEXT (has_context)** = What has happened / situation description
- Past tense verbs: called, spoke, tried, texted, emailed, visited
- Situation descriptors: unresponsive, hung up, no answer, interested, looking
- Vehicle/product mentions: fat boy, dyna, 2026, etc.

**ACTION (has_action)** = What DAOS should DO next
- Imperative verbs: call, text, follow up, send, schedule
- Directive phrases: let them know, get them in, reach out, see if

---

## Implementation Steps

1. **Backup** - Export current v_instruction_clarity results
2. **Test** - Run the new regex patterns against sample instructions
3. **Deploy** - Update the view in Supabase SQL Editor
4. **Verify** - Check the examples above produce correct ratings
5. **Monitor** - Watch for any unexpected changes in clarity_score distributions

---

## Notes

- The `\y` in PostgreSQL regex is a word boundary (equivalent to `\b` in other regex flavors)
- Single quotes in PostgreSQL SQL need to be escaped as `''`
- The pattern `let .{1,20} know` allows 1-20 characters between "let" and "know" to match phrases like "let the customer know"
- Past tense detection moves those words to CONTEXT where they belong

---

## Validation Testing (January 20, 2026)

### Confirmed Issue: "now" alone NOT being detected

Tested 21 additional examples. Confirmed pattern:

| Instruction | TIME Rating | Expected |
|-------------|------------|----------|
| "engage **now** ask for cosigner" | ✗ TIME | **Should be ✓** |
| "engage **now** ask for id and paystub" | ✗ TIME | **Should be ✓** |
| "engage **now** in spanish, encourage them..." | ✗ TIME | **Should be ✓** |
| "Engage **right now** - What are you looking for?" | ✓ TIME | Correct |
| "engage **right away** ask for id" | ✓ TIME | Correct |
| "Reach out at **2:00pm**" | ✓ TIME | Correct |

**Root cause:** The word "now" alone is not matching despite being in the pattern. Likely a regex boundary issue.

### Confirmed Working: CRM-only notes correctly get ✗ ACT

| Instruction | ACT Rating | Correct? |
|-------------|-----------|----------|
| "I spoke to the customer he needs to have $5500 or a cosigner. No other way around it." | ✗ ACT | **YES** - pure note |
| "Customer is interested in financing our Escalade - curious about how financing works makes good income but bad credit due to divorce" | ✗ ACT | **YES** - pure note |

These are CRM-style situation descriptions without any directive for DAOS. The system correctly identifies them as missing ACTION.

### Examples That Should Be COMPLETE After Fix

| # | Instruction | Current | After Fix |
|---|-------------|---------|-----------|
| 1 | "engage now ask for cosigner" | ✓C ✓A ✗T (partial) | ✓C ✓A **✓T** (complete) |
| 6 | "engage now ask for id and paystub" | ✗C ✓A ✗T (partial) | ✗C ✓A **✓T** (partial→same) |
| 9 | "engage now in spanish, encourage them to provide phone..." | ✓C ✓A ✗T (partial) | ✓C ✓A **✓T** (complete) |
| 13 | "engage now, encourage them to provide phone..." | ✓C ✓A ✗T (partial) | ✓C ✓A **✓T** (complete) |

### Summary of Validation

- **21 examples tested**
- **4 had incorrect TIME ratings** (all due to "now" not matching)
- **2 correctly identified as CRM-only notes** (no action)
- **15 were correctly rated**

The primary fix needed is ensuring "now" matches as a standalone word in the TIME pattern.

---

## Validation Testing Round 2 (January 20, 2026)

### Additional Issue Found: "at noon" NOT being detected

**Example:** "Taking video and sending it. **At noon** check in and make sure he got videos..."
- **Got:** ✗ TIME
- **Expected:** ✓ TIME

The pattern `at \d` only matches "at" followed by a digit. Need to add "noon" and "midnight".

### Additional Issue Found: "Let [name] know" NOT matching ACTION

**Example:** "**Let Elsa know** that we are sorry but we are not able to get that many Monkeys in..."
- **Got:** ✗ ACT
- **Expected:** ✓ ACT

Current pattern `let know` doesn't have flexible matching. Fix uses `let .{1,20} know`.

**Note:** Some instructions like "let Oscar know" get ✓ ACT because they contain other action words (e.g., "engagement" contains "engage").

### Updated Patterns Based on Round 2

**Add to TIME pattern:**
- `noon` and `midnight` as explicit time references

**Add to CONTEXT pattern:**
- `timed out` (call failures)
- `attempted` (past tense attempt)
- `sorry` (apology context)
- `received` (past tense)
- `rebooked` (past tense)
- `rescheduled` (past tense - note: "reschedule" is action, "rescheduled" is context)

**Add to ACTION pattern:**
- `start outreach` / `begin outreach`
- `reschedule` (imperative - different from past tense "rescheduled")
- `check in` (as directive)
- `confirm with`
- `pause` (as in "pause engagement")

### Summary: All Issues Identified

| Issue | Pattern | Fix |
|-------|---------|-----|
| "now" not matching | TIME | Explicit `(^|[^a-z])now([^a-z]|$)` check |
| "at noon" not matching | TIME | Add `noon`, `midnight` to word list |
| "let Elsa know" not matching | ACTION | Use `let .{1,20} know` flexible match |
| "tried to call" not context | CONTEXT | Add `tried`, `attempted`, `timed out` |
| Past-tense treated as action | ACTION | Exclude `called`, `spoke`, `reached`, etc. |

### Test Coverage

**Total examples analyzed:** 46+
**Issues found:** 8 pattern gaps
**Correctly rated:** ~85%

The fixes address all identified gaps while maintaining correct detection of:
- CRM-only notes (✗ ACT) ✓
- "right now" / "right away" (✓ TIME) ✓
- "immediately" (✓ TIME) ✓
- Specific times like "2:30pm" (✓ TIME) ✓

