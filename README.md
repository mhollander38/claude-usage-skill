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
```

It also flags a scenario that's easy to miss: a healthy session percentage doesn't mean
capacity is actually fine if weekly is exhausted. If weekly is at/near 100% while session
still shows room, the script adds a warning:

```
WARNING: weekly quota is exhausted (100%) but the session limit still shows room (0%).
A healthy session percentage does not mean capacity is fine here — if requests are still succeeding,
that overflow is either being billed as purchased usage credits (extra usage), or you're in a brief
grace window before a hard stop. Run '/usage-credits' in an interactive session to confirm which.
```

This matters because a naive check that only watches session usage (e.g. "pause above ~90%
session used") will happily keep running once weekly is spent, silently burning purchased
usage credits (real money) — or riding a grace window that ends without warning.

## Install

```bash
git clone https://github.com/mhollander38/claude-usage-skill.git
cd claude-usage-skill
./install.sh
```

This symlinks the repo into `~/.claude/skills/check-usage`, so pulling updates in the repo
updates the installed skill automatically. Start a new Claude Code session afterwards —
skills are loaded at session start.

## Use

Ask Claude Code about usage limits, or invoke it directly:

```
/check-usage
```

## How it works

- `SKILL.md` — instructions telling Claude to run the bundled script and report the two
  percentages back conversationally.
- `scripts/check-usage.sh` — runs `claude -p "/usage"` and extracts just the session and
  week lines, discarding the rest of the (unrelated) usage breakdown.
- `install.sh` — symlinks this repo into `~/.claude/skills/check-usage`.

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

As of Claude Code 2.1.269, there's no dedicated flag or JSON field exposing usage-credit
status — `claude -p "/usage" --output-format json` returns the same plain-text block as
the interactive command, just wrapped in a JSON envelope. When usage credits are active,
Claude Code shows extra rows in `/usage` (credit balance, spend, or an "off" hint) alongside
the session/week percentages, so this skill's script opportunistically greps for
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
