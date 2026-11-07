# Record vocabulary: English (default). One KEY="value" per line; read as data, never executed.
# Every other locale overrides these keys; a key it leaves out keeps the English value.
# Used by bin/render-template (templates/*.md), bin/hooks/prepare-commit-msg and check-work.

# Record and decision lines
VOC_TASK="Task"
VOC_CONTEXT="Context"
VOC_CONFIDENCE="Confidence"
VOC_CONFIDENCE_LEVELS="high|medium|low"
VOC_CONFIDENCE_LOW="low"
VOC_MORE="more"

# Record sections
VOC_QUESTION="Question / Problem"
VOC_FACTS="Facts"
VOC_PROPOSAL="Proposal / Result"
VOC_DISCARDED="Discarded"
VOC_COST="Cost / Risk"
VOC_OPEN="Open"

# Decision sections and option outcomes
VOC_OPTIONS="Options"
VOC_DECISION="Decision"
VOC_CONSEQUENCES="Consequences"
VOC_OPTION_NAME="Option name"
VOC_CHOSEN="chosen"
VOC_REJECTED="rejected"
VOC_REASON="reason"

# Banners allowed under a committed record's title
VOC_CORRECTED_BY="Corrected by"
VOC_SUPERSEDED_BY="Superseded by"
VOC_IDS_RENUMBERED_IN="Ids renumbered in"

# Training unit sections checked by check-work (prefix of the heading)
VOC_TU_CASE="1. The case"
VOC_TU_WALKTHROUGH="2. The walkthrough"
VOC_TU_CONCEPTS="4. Concepts"
VOC_TU_QUESTIONS="7. Questions"

# README objectives table
VOC_OBJECTIVE="Objective"
VOC_DONE_WHEN="Done when"

# hooks/confidence-nudge: extra trigger words (ERE alternatives, lower case; English ones always apply)
VOC_NUDGE_WORDS=""
VOC_NUDGE_MESSAGE="Every conclusion ends with Confidence: high|medium|low. If low, state the uncertainty and propose the cheapest check."
