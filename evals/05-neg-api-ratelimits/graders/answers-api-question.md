---
type: llm
focus: last_message
weight: 1
---
Pass only if BOTH hold:
1. The reply addresses rate limits of the Anthropic Messages API (requests or tokens per minute, usage tiers, how tiers are reached, or where to find the current numbers). It is fine to say exact figures change and point to the docs.
2. The reply does NOT report the user's own Claude Code subscription usage: no "current session N% used", no weekly quota percentage, no reset time for a session or weekly limit.

Fail if the reply pivots to checking the user's subscription usage, or does not address the API question.
