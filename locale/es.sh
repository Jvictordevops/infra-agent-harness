# Record vocabulary: Spanish. Overrides locale/en.sh key by key; read as data, never executed.

# Record and decision lines
VOC_TASK="Tarea"
VOC_CONTEXT="Contexto"
VOC_CONFIDENCE="Confianza"
VOC_CONFIDENCE_LEVELS="alta|media|baja"
VOC_CONFIDENCE_LOW="baja"
VOC_MORE="más"

# Record sections
VOC_QUESTION="Pregunta / Problema"
VOC_FACTS="Hechos"
VOC_PROPOSAL="Propuesta / Resultado"
VOC_DISCARDED="Descartado"
VOC_COST="Coste / Riesgo"
VOC_OPEN="Abierto"

# Decision sections and option outcomes
VOC_OPTIONS="Opciones"
VOC_DECISION="Decisión"
VOC_CONSEQUENCES="Consecuencias"
VOC_OPTION_NAME="Nombre de la opción"
VOC_CHOSEN="elegida"
VOC_REJECTED="descartada"
VOC_REASON="motivo"

# Banners allowed under a committed record's title
VOC_CORRECTED_BY="Corregido por"
VOC_SUPERSEDED_BY="Sustituido por"
VOC_IDS_RENUMBERED_IN="Ids renumerados en"

# Training unit sections checked by check-work (prefix of the heading)
VOC_TU_CASE="1. El caso"
VOC_TU_WALKTHROUGH="2. El recorrido"
VOC_TU_CONCEPTS="4. Conceptos"
VOC_TU_QUESTIONS="7. Preguntas"

# README objectives table
VOC_OBJECTIVE="Objetivo"
VOC_DONE_WHEN="Hecho cuando"

# hooks/confidence-nudge: extra trigger words (ERE alternatives, lower case; English ones always apply)
VOC_NUDGE_WORDS="no funciona|no arranca|no responde|investig|lento|cuelga|falla|caído|caida"
VOC_NUDGE_MESSAGE="Toda conclusión termina con Confianza: alta|media|baja. Si es baja, declara la incertidumbre y propón la verificación más barata."
