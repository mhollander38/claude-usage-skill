---
name: check-usage
description: Check Claude Code's live 5-hour session and weekly usage percentages against the subscription limits, with reset times. Use when the user asks about usage, quota, limits, or whether they are close to being rate limited; before starting any non-trivial or multi-step task; at step boundaries during planned work; when resuming after a usage limit reset ("limit increased, continue"); and when the user pastes /usage output and asks whether to continue or pause.
---

# Check Usage

Run the bundled script to get live usage numbers from your Anthropic account:

```
bash <this skill's directory>/scripts/check-usage.sh
```

(Use the base directory shown when this skill was invoked to build the path.)

## What the script prints

Normal output is two or three lines:

```
Current session: 23% used · resets Oct 3 at 7:19pm (Europe/London)
Current week (all models): 49% used · resets Oct 4 at 5am (Europe/London)
Current week (Fable): 2% used · resets Oct 4 at 5am (Europe/London)
```

Report the session line and the **(all models)** week line as the two headline figures, each with
its reset time, in one or two friendly sentences.

A per-model week line (e.g. `(Fable)` or `(Sonnet only)`) is a sub-cap inside the weekly pool, not
extra capacity. The session and weekly (all models) limits apply to every model, so per-model room
never helps when either of those is exhausted. Mention the per-model line briefly, or lead with it
when the `Binding limit:` line names it or it is at 90% or more. Once a per-model cap is hit, that
model needs usage credits while other models keep working.

Do not fetch or relay the rest of the `/usage` breakdown (subagent/skill/plugin stats).

The script may add one of these blocks after the figures. Relay them, do not soften them:

- **`WARNING:` weekly exhausted, session shows room.** Lead with this, before the plain percentages.
  Say clearly that weekly quota is exhausted and that continuing right now either bills purchased
  usage credits (real money, if enabled) or is running on borrowed time before a hard stop. Point to
  `/usage-credits` (interactive-only) to confirm which. This applies even when a policy says "keep
  going, don't stop to ask": keep going, but never silently.
- **`NOTICE:` weekly at 95–99%.** Say so before deciding anything, and say what happens at 100%.

## Plan and credits lines (best effort)

After the figures the script may print lines read from Claude Code's local usage cache. They are
best effort (undocumented, shown only when the cache is fresh) and may be absent:

- `Plan: …` is the subscription tier. On Pro, and on Team or Enterprise standard seats, Fable models
  are not included and always run on usage credits.
- `Binding limit: …` names the limit currently constraining the account. Lead with it alongside the two
  headline figures; a WARNING still comes first.
- `Usage credits: …` says whether work past a plan limit is billed or stops. `ON · … used` means it
  is billed at API rates. `ON but out of credits`, or a line starting `Usage credits: OFF`, means a
  hard stop at 100%, even if the toggle in settings shows on. `ON but monthly spend limit reached`
  also means a hard stop. Promotional credits, if any, are spent
  before purchased credits.
- A `… credit: $X of $Y left` line is a separate included credit with its own expiry. It covers only
  what its label says: a `Claude Code and Cowork credit` line does apply to local Claude Code work; a
  `Cloud session credit (cloud sessions only)` line does not.
- `Local included credit available: …` means a credit that applies to local Claude Code work still has
  a balance, so work may continue on it before a hard stop.
- `Credits check: …` under a WARNING says whether the WARNING means a bill, a stop, or an included
  credit covering the gap. Relay it.

When these lines are absent, fall back to the WARNING's either/or wording.

## When the script cannot get numbers

A block starting with a `check-usage:` line is the script explaining a failure. Relay the whole block
verbatim and do not guess, estimate, or infer usage from token counts or context size. Then tell the user how to get
the figures: run `/usage` in an interactive Claude Code session. If the script says the output was
the per-session cost summary, the account in this environment is most likely on API-key billing or
not signed in to a subscription, so there is no session/weekly quota to report. If the block says it is reading canned output (not
live), say so: the figures are test data, not the account's usage.

## Recommended decision rule for unattended, multi-step work

A project's own policy (e.g. CLAUDE.md) overrides this. In its absence:

- **Session ≥ 90%:** pause at the next step boundary rather than starting a step that may be cut
  off. Schedule a resume a few minutes after the session reset time, not exactly on it.
- **Weekly ≥ 100% (WARNING):** flag it first, as above. If credits are unavailable (a `Credits
  check:` stop line, or the user says the balance is zero), say work will stop at the next request.
  Continuing on credits is the user's call, never silent.
- **Weekly 95–99% (NOTICE):** say so, and prefer to finish at a clean checkpoint.
- **Otherwise:** report the numbers in one line and carry on.

Check again at every step boundary, not just at the start. A healthy number at the start of a long
task says nothing about the end of it.

## Interpreting numbers the user already has

If the user pastes `/usage` output and asks whether to continue, apply the same rules to the pasted
figures. Do not re-run the script unless they ask or the pasted output is ambiguous. In particular,
weekly at 100% with session room is the WARNING case even when no WARNING text was pasted: say that
requests may still be succeeding on usage credits, if the account has a balance, and point to `/usage-credits`.

If the user says usage credits are switched on but the balance is zero and auto-reload is off, treat
credits as unavailable: weekly at 100% is then a hard stop at the next request, not a bill. Say so
plainly, and point to `/usage-credits` to add credits or turn on auto-reload.

## Extra / purchased usage ("usage credits")

Anthropic's pay-as-you-go feature for continuing past the plan's included quota is called **usage
credits** in the current CLI (older naming: "overage" / "extra usage"). It is off by default. If the
script's output includes a line mentioning credits, extra usage, or overage (a balance, a spend
amount, or "usage credits are off"), report it alongside the percentages in plain terms. Only a `Usage credits: ON · …` line means work past
a limit draws on usage credits. Included-credit lines (`… credit: $X of $Y left`) are not purchased
credits; follow the Plan and credits lines section for them.

To enable, buy, or check credits, the user runs `/usage-credits` in an **interactive** session (it
opens `claude.ai/settings/usage` in a browser). On Team/Enterprise plans an org admin manages it at
`claude.ai/admin-settings/usage`.
