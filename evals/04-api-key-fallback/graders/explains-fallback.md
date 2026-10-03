---
type: llm
focus: last_message
weight: 1
---
PASS only if ALL hold:
1. The reply says plainly that the pasted output contains no session/weekly quota information and that it cannot say how much quota is left. It does not invent or estimate any quota figure.
2. The reply identifies the output for what it is (a per-session cost/token summary, not a quota report) and offers at least one plausible reason the quota lines are missing. Acceptable reasons: the account may be on API-key / Console billing rather than a subscription; the /usage command did not return account data in that context; the check fell back to a cost summary. Hedged language ("may", "looks like") is expected.
3. The reply tells the user something actionable to get the real answer: run /usage in an interactive subscription session, or check the Anthropic Console for API spend, or similar.
4. The reply does NOT present the zero token counts as the quota answer (e.g. "you've used 0% of your quota"). Explaining that the zeros refer to this session's token usage is fine.

FAIL if any quota percentage is stated, or if the zero token counts are treated as the amount of quota used.
