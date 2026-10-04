# claude-usage-skill

A [Claude Code](https://claude.com/claude-code) skill that reports your live, actual usage
against your subscription limits — the current 5-hour rolling session percentage and the
current weekly percentage — so a Claude Code session can check how much runway it has left
before starting a long task.

Unlike approaches that estimate usage from local token logs, this skill reads the real
number straight from your Anthropic account via `claude -p "/usage"`, the same data the
interactive `/usage` command shows you.

## What it reports

```
Current session: 77% used · resets Sep 7 at 9:29pm (Europe/London)
Current week (all models): 50% used · resets Sep 13 at 4:59am (Europe/London)
Current week (Fable): 4% used · resets Sep 13 at 4:59am (Europe/London)
```

The `(all models)` line is the weekly figure that matters. A per-model line (here `Fable`) may also
appear; it is informational.

Two situations get an extra block so they are not missed, even when the script is run directly from
Bash without the skill's instructions in context:

- **Weekly at 95–99%** adds a `NOTICE:` saying the week is nearly gone and what happens at 100%.
- **Weekly at 100% while session still shows room** adds a `WARNING:`:

```
WARNING: weekly quota is exhausted (100%) but the session limit still shows room (0%).
A healthy session percentage does not mean capacity is fine here — if requests are still succeeding,
that overflow is either being billed as purchased usage credits (extra usage), or you're in a brief
grace window before a hard stop. Run '/usage-credits' in an interactive session to confirm which.
```

After the figures, the script adds best-effort lines from Claude Code's local usage cache when
`python3` is available and the cache is fresh (it is refreshed by the same `/usage` call):

```
Plan: Max 5x
Binding limit: weekly (all models) 89%
Usage credits: ON but out of credits (balance £0.00), so work stops when a plan limit is hit
Cloud session credit (cloud sessions only): $103.13 of $250.00 left · expires Nov 5
```

On Pro and Max with Claude Code 2.1.277 or later, once the session is at 80% or more and weekly is
below 100%, it also adds a `Wrap-up allowance:` line: a response already running when the five-hour
limit hits may finish briefly (on Pro, up to once per week).

Under a WARNING it also adds a `Credits check:` line saying whether work past 100% is being billed
or will stop. The cache is undocumented, so these lines may disappear after a Claude Code update;
the figures above them never depend on it. See `docs/research/2026-10-03-plan-limits-and-credits.md`
for how session, weekly, per-model limits and the different credits interact.

This matters because a naive check that only watches session usage (e.g. "pause above ~90%
session used") will happily keep running once weekly is spent, silently burning purchased
usage credits (real money) — or riding a grace window that ends without warning.

## Install

```bash
git clone https://github.com/mhollander38/claude-usage-skill.git
cd claude-usage-skill
./install.sh
```

This symlinks `skills/check-usage` into `${CLAUDE_CONFIG_DIR:-~/.claude}/skills/check-usage` (a previous `~/.claude/skills` symlink is left in place when `CLAUDE_CONFIG_DIR` is set), so pulling updates in the repo
updates the installed skill automatically. Start a new Claude Code session afterwards —
skills are loaded at session start.

## Use

Ask Claude Code about usage limits, or invoke it directly:

```
/check-usage
```

## How it works

- `skills/check-usage/SKILL.md` — instructions telling Claude to run the bundled script and how to
  report and interpret what it prints.
- `skills/check-usage/scripts/check-usage.sh` — runs `claude -p "/usage"`, extracts the session and
  week lines, and adds a `NOTICE`/`WARNING` block when the week is nearly or fully exhausted.
- `skills/check-usage/scripts/usage-cache.py` — optional helper that reads the plan, binding limit,
  credits and wrap-up lines from Claude Code's local usage cache.
- `install.sh` — symlinks `skills/check-usage` into `${CLAUDE_CONFIG_DIR:-~/.claude}/skills/check-usage` (a previous `~/.claude/skills` symlink is left in place when `CLAUDE_CONFIG_DIR` is set).
- `.claude-plugin/plugin.json` — plugin manifest, so the repo can also be installed as a plugin or
  run under `claude plugin eval`.

## When it cannot get numbers

Every failure prints a line starting with `check-usage:` saying what happened, and the script exits
non-zero where the figures are unavailable:

| situation | output | exit |
|---|---|---|
| `claude` not on PATH | `check-usage: 'claude' not found …` | 127 |
| `claude -p "/usage"` exits non-zero | `check-usage: 'claude -p /usage' failed (exit N)…` plus its output | 1 |
| it exits 0 with no output | `check-usage: 'claude -p /usage' returned no output…` | 1 |
| `CHECK_USAGE_INPUT_FILE` unreadable or not a file | `check-usage: CHECK_USAGE_INPUT_FILE is set but … is not readable.` | 2 |
| output has no session/week lines (e.g. the per-session cost summary when not signed in to a subscription, or API-key billing) | `check-usage: no session/week lines found…` plus the raw output | 0 |

## Testing

```bash
bash tests/test-check-usage.sh
```

The tests never call the real CLI. Two environment variables make that possible and are also handy
for trying the skill's behaviour by hand:

- `CHECK_USAGE_INPUT_FILE=<path>` reads canned `/usage` text from a file (see `tests/fixtures/`).
- `CHECK_USAGE_CLAUDE_BIN=<path>` calls a different `claude` binary.
- `CHECK_USAGE_CACHE_FILE=<path>` reads plan/credits from this config JSON (canned mode reads none
  unless this is set). `CHECK_USAGE_NO_CACHE=1` turns the lines off. `CHECK_USAGE_PYTHON` picks the
  interpreter. `CHECK_USAGE_CLI_VERSION=<x.y.z>` sets the Claude Code version for the wrap-up line
  (live mode detects it from `claude --version`; canned mode uses it only if set).
- `CHECK_USAGE_CACHE_MAX_AGE=<seconds>` (default 180), `CHECK_USAGE_NOW_MS=<epoch ms>` and
  `CHECK_USAGE_DEBUG=1` (let the helper raise instead of staying silent) are for tests and tuning.

When `CHECK_USAGE_INPUT_FILE` is set the script prints a `check-usage: reading canned /usage output … (not live)` line first, so canned figures are never mistaken for live ones.

```bash
CHECK_USAGE_INPUT_FILE=tests/fixtures/weekly-exhausted.txt bash skills/check-usage/scripts/check-usage.sh
```

## Suggested usage: running autonomously across usage limits

This skill is most useful as a scheduling check for long, multi-step, unattended work —
letting Claude keep going for as long as possible instead of stopping to ask permission
every time capacity gets tight. A suggested pattern:

1. **Before starting any non-trivial task** (multi-step, involves deploys/migrations, or
   can't be abandoned partway without leaving a mess), invoke this skill and check
   remaining capacity.
2. **At every safe step boundary**, check again. If session usage is climbing toward the
   limit (say, above ~90%), pause there rather than starting a step that might get cut off
   mid-way. Check weekly too — a fine session percentage doesn't mean capacity is fine if
   weekly is exhausted (see the `WARNING` case above); don't let that pass unmentioned even
   if you decide to keep going.
3. **Commit after every step**, so an interrupted run can only ever stop *between* steps,
   never mid-edit.
4. **When capacity runs out, schedule a resume** for a few minutes *after* the reset time
   shown by this skill (avoid scheduling exactly on the reset mark). Pass along everything
   the resumed run needs to pick up cleanly: the plan, the branch, and the step to start
   from. Claude Code's own scheduling tools (e.g. a cron-style wake-up) work well for this;
   an OS-level `cron`/`launchd`/`at` job is a fallback if the session itself won't stay
   resident.
5. **Report the pause and the scheduled resume time**, then stop cleanly rather than
   waiting idle — repeat across as many reset windows as the work takes.
6. **Only stop for a genuine human gate** — something that truly needs a person: dashboard
   actions, secrets to create, deploys/migrations to actually run, device builds, an
   irreversible or outward-facing action, or a decision the plan doesn't already settle.

Running an agent this unattended goes further with a more permissive permission mode
(auto-accepting routine tool calls) so it isn't blocked waiting on approvals it can't
receive while unsupervised — weigh that against the blast radius of what the task can do
before turning it on.

**Caveat:** in-session scheduling (like Claude Code's cron-style wake-ups) is typically
session-only — in memory, and gone if the session exits. A run that needs to span a reset
window needs that terminal/session left open and idle throughout, or the resume needs to be
handed to something more durable (a real OS cron job, CI, etc.). A silently-dead scheduled
job looks identical to one that just hasn't fired yet, so say so plainly whenever you set
one up.

## Extra / purchased usage ("usage credits")

Claude Code has a pay-as-you-go feature for continuing past your plan's included quota,
currently called **usage credits** in the CLI (you may also see it referred to as "overage"
or "extra usage" in older or internal messages — same feature). It's off by default; you
turn it on, buy credits, and set a monthly spend limit or auto-reload via `/usage-credits`,
which is interactive-only — it opens `claude.ai/settings/usage` in a browser. On Team/
Enterprise plans an org admin manages it instead, at `claude.ai/admin-settings/usage`.

Usage-credit status is not in the `/usage` text (`claude -p "/usage" --output-format json` returns
the same plain-text block as the interactive command, wrapped in a JSON envelope), so the script
reads it best-effort from Claude Code's local cache (the `Usage credits:` line above). When usage
credits are active, Claude Code may also show extra rows in `/usage` (credit balance, spend, or an
"off" hint) alongside the session/week percentages, so the script opportunistically greps for
credit/extra-usage/overage keywords too. Whether those rows appear in the headless `-p`
render depends on account/plan eligibility, so treat that part as best-effort — the plain-text
`/usage` output on this repo's own test account never printed a credit line either way, even
while its weekly quota sat at 100% and requests kept succeeding (see the `WARNING` case above),
which is itself indirect evidence that *something* — credits or a grace window — was covering
the overflow without the CLI saying so explicitly.

## Requirements

- Claude Code CLI installed and authenticated (`claude` on your `PATH`).
- A Claude subscription plan (Pro/Max/Team). API-key billing doesn't expose the same
  session/week percentages, in which case the script falls back to printing the raw
  `/usage` output.
- python3 3.7 or later (optional) for the plan and credits lines. The macOS python3 stub (shown
  when the Command Line Tools are not installed) is detected and skipped.
- `claude -p "/usage"` has no timeout, so a hung CLI hangs the check.
