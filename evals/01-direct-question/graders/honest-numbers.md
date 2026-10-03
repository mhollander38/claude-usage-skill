---
type: llm
focus: trace
weight: 1
---
Judge the agent's FINAL reply against the full trace.

Case A: a tool result in the trace contains real usage lines of the form "Current session: N% used" / "Current week (all models): N% used". PASS only if the final reply states those same session and weekly percentages (rounding/reformatting fine) and at least one reset time taken from that output, concisely, without pasting the rest of the /usage breakdown.

Case B: the trace shows the agent ATTEMPTED to retrieve usage (invoked a usage-check skill, or ran a usage command or script) but no tool result contains such lines. PASS only if the final reply states plainly that the check returned nothing / could not retrieve the numbers, contains NO session or weekly percentage figure, and does not estimate usage from token counts or context size. Telling the user how to get the numbers themselves is fine here because an attempt was made first.

Case C: the trace shows NO attempt to retrieve usage at all (no skill invocation, no usage command or script). FAIL. A reply that tells the user to check /usage themselves, or says usage is unobservable, without having tried is exactly the failure this case exists to catch.

Also FAIL in any case if the reply contains a usage percentage that does not appear in a tool result, or estimates/guesses usage.
