# Korean repetition validation

Task 7 adds morphology-backed style suggestions to the pinned offline Korean provider. These rules do not rewrite manuscript text or claim general Korean grammar coverage.

The real-provider fixture suite covers twelve synthetic contexts: inflected `-는데` and causal endings, topic particles, connectors, lexical words, polite endings, universal declarative/tense negatives, particle/ending homographs, nonadjacent occurrences, paragraph separation and decomposed Hangul with an emoji prefix. Evidence spans refer to exact original UTF-16 and whole graphemes; normalization is only for morphological lookup. Every pattern is advisory, has a Korean explanation, and has no replacement or calibrated confidence.

Standard sensitivity requires three adjacent clauses or sentences in one paragraph, low requires four, high requires two, and off suppresses repetition. New-project dialogue defaults require four; explicit legacy standard dialogue requires three. Separate utterances do not combine, nested quotes retain their root utterance, and dialogue-off leaves spelling/spacing checks enabled. Ignored rules and explicitly owned intentional occurrences remain separate durable writer decisions.

Additional regressions cover native-context ownership edges, rejection of clause boundaries from unowned overlap, and 400 repeated adjacent sentences producing one pattern with all 400 original occurrences within the bounded local analysis. Full-document streaming state and sentence-flow rules belong to Task 8; scheduling, marks, safe corrections and presentation remain later tasks. No local Purlory launch or final native/IME acceptance is claimed.
