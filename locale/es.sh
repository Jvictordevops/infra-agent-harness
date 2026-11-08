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

# Training unit (templates/training-unit.md): title, header labels and section headings
VOC_TU_UNIT="Unidad"
VOC_TU_WHAT_FOR="Para qué"
VOC_TU_LOAD="Carga"
VOC_TU_HOW_MADE="Cómo se hizo"
VOC_TU_VERSIONS="Versiones"
VOC_TU_H1="1. El caso que seguimos"
VOC_TU_H2="2. El recorrido, paso a paso"
VOC_TU_H3="3. Por qué cada pieza está en nuestra arquitectura"
VOC_TU_H4="4. Conceptos"
VOC_TU_H5="5. Lecturas oficiales (en orden)"
VOC_TU_H6="6. Ejercicio en kind"
VOC_TU_H7="7. Preguntas para comprobarte"
VOC_TU_H8="8. Qué podrás ratificar al terminar"
# Sections check-work requires in a unit (prefix of the heading)
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
