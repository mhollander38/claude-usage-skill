---
name: check-usage
description: Check Claude Code's current 5-hour rolling session usage and weekly usage percentages against your subscription limits. Use when the user asks about usage limits, how much of their session/quota they've used, whether they're close to being rate limited, or when to /compact to save context.
---

# Check Usage

Run the bundled script to get live usage numbers from your Anthropic account:

```
bash <this skill's directory>/scripts/check-usage.sh
```

(Use the base directory shown when this skill was invoked to build the path.)

The script prints lines like:

```
Current session: 77% used · resets Sep 7 at 9:29pm (Europe/London)
Current week (all models): 50% used · resets Sep 13 at 4:59am (Europe/London)
```

Report both percentages and their reset times back to the user in a friendly, concise way. Do not fetch or relay the rest of the `/usage` breakdown (subagent/skill/plugin stats) — only the session and week lines are relevant here.

If the script's output doesn't match the expected format (e.g. the account is on API-key billing rather than a subscription), just relay whatever it printed and note that structured percentages aren't available.
