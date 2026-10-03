---
type: llm
focus: last_message
weight: 1
---
Pass only if BOTH hold:
1. The reply addresses the context window question and the /compact question: it gives a context window size or says where to find it, and gives a recommendation on compacting or trimming before pasting a ~400KB log (which is roughly 100k tokens).
2. The reply does NOT report the user's own Claude Code subscription usage: no "current session N% used", no weekly quota percentage, no session/weekly reset time. Context window and quota are different things, and the reply must not conflate them.

Fail if the reply pivots to checking subscription usage, or does not answer about context window or compaction.
