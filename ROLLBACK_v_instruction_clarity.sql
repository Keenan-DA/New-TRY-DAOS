-- ROLLBACK: Restore original v_instruction_clarity view
-- Run this if the new view broke things

DROP VIEW IF EXISTS v_instruction_clarity;

CREATE VIEW v_instruction_clarity AS
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

  -- CONTEXT (original patterns)
  CASE WHEN r.instruction IS NULL OR TRIM(r.instruction) = '' THEN false
       ELSE r.instruction ~* '\y(asked|wanted|interested|looking|trade|vehicle|car|truck|suv|pricing|price|quote|offer|deal|sold|bought|test drive|called|voicemail|no answer|left message|spoke|mentioned|said|told|visit|come in|stop by|credit|approved|financing|co-sign|cosign|down payment|monthly|payment|inventory|stock|appointment|scheduled|waiting|ready|hot|warm|cold|serious|motivated|hesitant|concerned|question|issue|problem|help|needs|wants|budget|range|lease|loan|purchase|honda|toyota|ford|chevy|chevrolet|ram|jeep|dodge|harley|fat boy|dyna|sportster|softail|touring|street glide|road glide|wide glide|breakout|iron|forty-eight|48|883|1200|v-rod|night rod|muscle|slim|deluxe|heritage|low rider|fat bob|road king|electra glide|ultra|cvo|trike|freewheeler|livewire|nightster|pan america)\y'
  END as has_context,

  -- ACTION (original patterns)
  CASE WHEN r.instruction IS NULL OR TRIM(r.instruction) = '' THEN false
       ELSE r.instruction ~* '\y(call|text|follow|send|schedule|reach|contact|see if|find out|try to|ask|let know|make aware|remind|check|confirm|book|set up|arrange|get back|respond|reply|message|email|notify|engage|stop|don''t|do not|cease|continue|keep|update|inform|touch base|circle back|ping|nudge|push|offer|present|show|demo|walk through|explain|discuss|talk|speak|meet|visit|invite|bring in|get in|have come)\y'
  END as has_action,

  -- TIME (original patterns)
  CASE WHEN r.instruction IS NULL OR TRIM(r.instruction) = '' THEN false
       ELSE r.instruction ~* '\y(today|tomorrow|morning|afternoon|evening|tonight|week|monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|may|june|july|august|september|october|november|december|next|later|soon|asap|now|immediately|hours|days|end of|first thing|eod|eow|this week|next week|couple|few|within|right away|when available)\y|\d:\d|\d\s?(am|pm)'
  END as has_timing,

  -- Clarity level
  CASE
    WHEN r.instruction IS NULL OR TRIM(r.instruction) = '' THEN 'empty'
    WHEN (r.instruction ~* '\y(asked|wanted|interested|looking|trade|vehicle|car|truck|suv|pricing|price|quote|offer|deal|sold|bought|test drive|called|voicemail|no answer|left message|spoke|mentioned|said|told|visit|come in|stop by|credit|approved|financing|co-sign|cosign|down payment|monthly|payment|inventory|stock|appointment|scheduled|waiting|ready|hot|warm|cold|serious|motivated|hesitant|concerned|question|issue|problem|help|needs|wants|budget|range|lease|loan|purchase|honda|toyota|ford|chevy|chevrolet|ram|jeep|dodge|harley|fat boy|dyna|sportster|softail|touring|street glide|road glide|wide glide|breakout|iron|forty-eight|48|883|1200|v-rod|night rod|muscle|slim|deluxe|heritage|low rider|fat bob|road king|electra glide|ultra|cvo|trike|freewheeler|livewire|nightster|pan america)\y')
         AND (r.instruction ~* '\y(call|text|follow|send|schedule|reach|contact|see if|find out|try to|ask|let know|make aware|remind|check|confirm|book|set up|arrange|get back|respond|reply|message|email|notify|engage|stop|don''t|do not|cease|continue|keep|update|inform|touch base|circle back|ping|nudge|push|offer|present|show|demo|walk through|explain|discuss|talk|speak|meet|visit|invite|bring in|get in|have come)\y')
         AND (r.instruction ~* '\y(today|tomorrow|morning|afternoon|evening|tonight|week|monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|may|june|july|august|september|october|november|december|next|later|soon|asap|now|immediately|hours|days|end of|first thing|eod|eow|this week|next week|couple|few|within|right away|when available)\y|\d:\d|\d\s?(am|pm)')
    THEN 'complete'
    WHEN (
      (CASE WHEN r.instruction ~* '\y(asked|wanted|interested|looking|trade|vehicle|car|truck|suv|pricing|price|quote|offer|deal|sold|bought|test drive|called|voicemail|no answer|left message|spoke|mentioned|said|told|visit|come in|stop by|credit|approved|financing|co-sign|cosign|down payment|monthly|payment|inventory|stock|appointment|scheduled|waiting|ready|hot|warm|cold|serious|motivated|hesitant|concerned|question|issue|problem|help|needs|wants|budget|range|lease|loan|purchase|honda|toyota|ford|chevy|chevrolet|ram|jeep|dodge|harley|fat boy|dyna|sportster|softail|touring|street glide|road glide|wide glide|breakout|iron|forty-eight|48|883|1200|v-rod|night rod|muscle|slim|deluxe|heritage|low rider|fat bob|road king|electra glide|ultra|cvo|trike|freewheeler|livewire|nightster|pan america)\y' THEN 1 ELSE 0 END) +
      (CASE WHEN r.instruction ~* '\y(call|text|follow|send|schedule|reach|contact|see if|find out|try to|ask|let know|make aware|remind|check|confirm|book|set up|arrange|get back|respond|reply|message|email|notify|engage|stop|don''t|do not|cease|continue|keep|update|inform|touch base|circle back|ping|nudge|push|offer|present|show|demo|walk through|explain|discuss|talk|speak|meet|visit|invite|bring in|get in|have come)\y' THEN 1 ELSE 0 END) +
      (CASE WHEN r.instruction ~* '\y(today|tomorrow|morning|afternoon|evening|tonight|week|monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|may|june|july|august|september|october|november|december|next|later|soon|asap|now|immediately|hours|days|end of|first thing|eod|eow|this week|next week|couple|few|within|right away|when available)\y|\d:\d|\d\s?(am|pm)' THEN 1 ELSE 0 END)
    ) >= 2
    THEN 'partial'
    ELSE 'incomplete'
  END as clarity_level

FROM reactivations r
WHERE r.instruction IS NOT NULL;
