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

## Requirements

- Claude Code CLI installed and authenticated (`claude` on your `PATH`).
- A Claude subscription plan (Pro/Max/Team). API-key billing doesn't expose the same
  session/week percentages, in which case the script falls back to printing the raw
  `/usage` output.
