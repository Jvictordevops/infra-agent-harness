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

# Training unit (templates/training-unit.md): title, header labels and section headings
VOC_TU_UNIT="Unit"
VOC_TU_WHAT_FOR="What for"
VOC_TU_LOAD="Load"
VOC_TU_HOW_MADE="How it was made"
VOC_TU_VERSIONS="Versions"
VOC_TU_H1="1. The case we follow"
VOC_TU_H2="2. The walkthrough, step by step"
VOC_TU_H3="3. Why each piece is in our architecture"
VOC_TU_H4="4. Concepts"
VOC_TU_H5="5. Official reading (in order)"
VOC_TU_H6="6. Exercise in kind"
VOC_TU_H7="7. Questions to check yourself"
VOC_TU_H8="8. What you can ratify when done"
# Sections check-work requires in a unit (prefix of the heading)
VOC_TU_CASE="1. The case"
VOC_TU_WALKTHROUGH="2. The walkthrough"
VOC_TU_CONCEPTS="4. Concepts"
VOC_TU_QUESTIONS="7. Questions"

# Marker word for a task delegated to the executor (two-machine module): '⇢ <word>' in the ROADMAP
VOC_EXECUTOR="executor"

# README objectives table
VOC_OBJECTIVE="Objective"
VOC_DONE_WHEN="Done when"

# hooks/confidence-nudge: extra trigger words (ERE alternatives, lower case; English ones always apply)
VOC_NUDGE_WORDS=""
VOC_NUDGE_MESSAGE="Every conclusion ends with Confidence: high|medium|low. If low, state the uncertainty and propose the cheapest check."
