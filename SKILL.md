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

### Extra / purchased usage ("usage credits")

Anthropic's pay-as-you-go feature for continuing past the plan's included quota is called
**usage credits** in the current CLI (older internal naming: "overage"/"extra usage" — you may
still see those words in messages). It's off by default and is enabled per-account or by an
org admin, so most runs of this script won't see anything about it. If the script's output
*does* include a line mentioning credits/extra usage/overage — e.g. a credit balance, spend
amount, or "usage credits are off" — report that alongside the session/week percentages,
in plain terms (e.g. "you also have $X of purchased usage credits available/spent"). There is
no separate flag or JSON field for this in Claude Code 2.1.269 — it only ever surfaces as
plain text inside `/usage`'s output, so this script's regex is the only hook into it.

If the user asks to enable, buy, or check their usage-credit balance/settings, tell them to
run `/usage-credits` in an **interactive** Claude Code session — it opens
`claude.ai/settings/usage` in a browser and can't be done headlessly. On a Team/Enterprise
plan, an org admin manages it instead, at `claude.ai/admin-settings/usage`.

If the script's output doesn't match the expected format (e.g. the account is on API-key billing rather than a subscription), just relay whatever it printed and note that structured percentages aren't available.
