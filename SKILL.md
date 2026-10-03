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
its reset time, in one or two friendly sentences. A per-model week line (e.g. `(Fable)`) may also
appear; it is informational. Mention it only briefly, or when it is the binding limit. Do not fetch
or relay the rest of the `/usage` breakdown (subagent/skill/plugin stats).

The script may add one of these blocks after the figures. Relay them, do not soften them:

- **`WARNING:` weekly exhausted, session shows room.** Lead with this, before the plain percentages.
  Say clearly that weekly quota is exhausted and that continuing right now either bills purchased
  usage credits (real money, if enabled) or is running on borrowed time before a hard stop. Point to
  `/usage-credits` (interactive-only) to confirm which. This applies even when a policy says "keep
  going, don't stop to ask": keep going, but never silently.
- **`NOTICE:` weekly at 95–99%.** Say so before deciding anything, and say what happens at 100%.

## When the script cannot get numbers

Lines starting with `check-usage:` are the script explaining a failure. Relay them verbatim and do
not guess, estimate, or infer usage from token counts or context size. Then tell the user how to get
the figures: run `/usage` in an interactive Claude Code session. If the script says the output was
the per-session cost summary, the account in this environment is most likely on API-key billing or
not signed in to a subscription, so there is no session/weekly quota to report.

## Recommended decision rule for unattended, multi-step work

A project's own policy (e.g. CLAUDE.md) overrides this. In its absence:

- **Session ≥ 90%:** pause at the next step boundary rather than starting a step that may be cut
  off. Schedule a resume a few minutes after the session reset time, not exactly on it.
- **Weekly ≥ 100% (WARNING):** flag it first, as above. Continuing is the user's call, never silent.
- **Weekly 95–99% (NOTICE):** say so, and prefer to finish at a clean checkpoint.
- **Otherwise:** report the numbers in one line and carry on.

Check again at every step boundary, not just at the start. A healthy number at the start of a long
task says nothing about the end of it.

## Interpreting numbers the user already has

If the user pastes `/usage` output and asks whether to continue, apply the same rules to the pasted
figures. Do not re-run the script unless they ask or the pasted output is ambiguous. In particular,
weekly at 100% with session room is the WARNING case even when no WARNING text was pasted: say that
requests may still be succeeding on purchased credits, and point to `/usage-credits`.

## Extra / purchased usage ("usage credits")

Anthropic's pay-as-you-go feature for continuing past the plan's included quota is called **usage
credits** in the current CLI (older naming: "overage" / "extra usage"). It is off by default. If the
script's output includes a line mentioning credits, extra usage, or overage (a balance, a spend
amount, or "usage credits are off"), report it alongside the percentages in plain terms, e.g. "you
also have $X of purchased usage credits remaining; work past the weekly limit is drawing on that."

To enable, buy, or check credits, the user runs `/usage-credits` in an **interactive** session (it
opens `claude.ai/settings/usage` in a browser). On Team/Enterprise plans an org admin manages it at
`claude.ai/admin-settings/usage`.

## Testing the script without a live account

- `CHECK_USAGE_INPUT_FILE=<path>` makes the script read canned `/usage` text from a file instead of
  calling the CLI. Fixtures live in `tests/fixtures/`.
- `CHECK_USAGE_CLAUDE_BIN=<path>` points the script at a different `claude` binary (used by tests to
  simulate failures).
- `bash tests/test-check-usage.sh` runs the test suite.
