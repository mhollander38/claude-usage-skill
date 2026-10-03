# check-usage Findings Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `scripts/check-usage.sh` fail loudly instead of silently, make it testable without a live account, widen the skill's triggers to the moments the user actually wants it (task kickoff, step boundaries, resume, pasted output), document the per-model week line, and move the repo to the standard plugin layout.

**Architecture:** The script stays a single bash file with no dependencies. Two environment knobs make it testable: `CHECK_USAGE_INPUT_FILE` (read canned `/usage` text from a file instead of calling the CLI) and `CHECK_USAGE_CLAUDE_BIN` (which `claude` binary to call, default `claude`). A plain-bash test script under `tests/` drives the script through fixture files and a fake `claude` binary. SKILL.md carries the triggers and interpretation rules; the script's own output carries the two critical interpretation lines (WARNING at 100%, NOTICE at ≥95%) so they survive direct Bash runs that bypass SKILL.md. Finally the skill moves under `skills/check-usage/` with a `.claude-plugin/plugin.json`, and `install.sh` symlinks that subdirectory.

**Tech Stack:** bash 3.2+ (macOS default), grep/sed/head/tr. No test framework; `tests/test-check-usage.sh` uses three tiny assert functions and exits non-zero on any failure.

**Spec:** `evals/FINDINGS.md` sections A, B, D. Items: A1 silent failure, A2 undocumented per-model line, A3 guidance only on script run, A4 canned-input hook, B1 under-firing triggers, B2 decision rule, B3 interpretation in script output, D layout.

## Global Constraints

- bash 3.2 compatible: no associative arrays, no `mapfile`, no `${var,,}`. macOS ships bash 3.2 and the script is invoked with `bash`.
- No new runtime dependencies. `timeout`/`gtimeout` is not available on stock macOS; do not use it.
- The eval suite under `evals/` is not modified by this plan. Case graders match `input_match: check-usage`, and the plugin name must remain `claude-usage-skill` so the eval runner keeps namespacing the skill as `claude-usage-skill:check-usage`.
- `~/.claude/skills/check-usage` is a live symlink into this repo. Task 4 moves files, so the symlink must be refreshed in Task 4 itself (run `./install.sh`), never left dangling at a commit boundary.
- Every script exit path prints at least one line to stdout. Silence is the bug being fixed.
- Error and status lines printed by the script start with the literal prefix `check-usage:` so SKILL.md can tell the agent to relay them verbatim.
- Commit after every task. Commit messages end with:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Ub6MrWMjj4X3nxSh8jzwKV`

## Review Focus

1. **`/usage` output with the `(all models)` week line missing but a per-model line present.** Expected: percentages for what is present are printed, no WARNING/NOTICE fires (they key on `(all models)` only), no crash. Test pinned in Task 1 (`fixture: week-permodel-only.txt`).
2. **`claude -p` prints usage lines AND exits non-zero** (e.g. a trailing warning). Expected: treated as failure with the output shown, because the exit code is the signal we trust. Test pinned in Task 2 (`fake claude: lines-then-exit-1`).
3. **Session at exactly 100% with week at 100%.** Expected: no WARNING (the WARNING is for "session shows room"); the lines still print. Test pinned in Task 2 (`fixture: both-100.txt`).
4. **`CHECK_USAGE_INPUT_FILE` set to an unreadable path.** Expected: `check-usage:` error to stdout, exit 2, nothing else attempted. Test pinned in Task 1.
5. **Cost-summary block instead of usage lines (not signed in / API-key billing).** Expected: explicit "no session/week lines" message plus the cost-summary hint, raw block echoed, exit 0. Test pinned in Task 2 (`fixture: cost-summary.txt`).

---

### Task 1: Test harness, fixtures, and the `CHECK_USAGE_INPUT_FILE` hook (A4)

**Files:**
- Create: `tests/test-check-usage.sh`
- Create: `tests/fixtures/normal.txt`
- Create: `tests/fixtures/weekly-exhausted.txt`
- Create: `tests/fixtures/week-permodel-only.txt`
- Modify: `scripts/check-usage.sh` (whole file; it is 22 lines)

**Interfaces:**
- Consumes: nothing.
- Produces: `tests/test-check-usage.sh` with helper functions `assert_contains NAME HAYSTACK NEEDLE`, `assert_not_contains NAME HAYSTACK NEEDLE`, `assert_eq NAME EXPECTED ACTUAL`, and `run_with_file FIXTURE_PATH` (runs the script with `CHECK_USAGE_INPUT_FILE` set, captures stdout+stderr, sets global `rc` to the exit code). Later tasks append tests to this file using these helpers. The script honours `CHECK_USAGE_INPUT_FILE`.

- [ ] **Step 1: Create the fixtures**

`tests/fixtures/normal.txt`:
```
Current session: 23% used · resets Oct 3 at 7:19pm (Europe/London)
Current week (all models): 49% used · resets Oct 4 at 5am (Europe/London)
Current week (Fable): 2% used · resets Oct 4 at 5am (Europe/London)
```

`tests/fixtures/weekly-exhausted.txt`:
```
Current session: 36% used · resets Oct 3 at 4:49pm (Europe/London)
Current week (all models): 100% used · resets Oct 4 at 4:59am (Europe/London)
```

`tests/fixtures/week-permodel-only.txt`:
```
Current session: 12% used · resets Oct 3 at 7:19pm (Europe/London)
Current week (Fable): 2% used · resets Oct 4 at 5am (Europe/London)
```

- [ ] **Step 2: Write the test harness with the first four tests**

`tests/test-check-usage.sh`:
```bash
#!/bin/bash
# Plain-bash tests for scripts/check-usage.sh. Run: bash tests/test-check-usage.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${CHECK_USAGE_SCRIPT:-$ROOT/scripts/check-usage.sh}"
FIX="$ROOT/tests/fixtures"
pass=0
fail=0
rc=0
out=""

assert_contains() { # NAME HAYSTACK NEEDLE
  if printf '%s\n' "$2" | grep -qF -- "$3"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected to find: %s\n  in:\n%s\n\n' "$1" "$3" "$2"
  fi
}

assert_not_contains() { # NAME HAYSTACK NEEDLE
  if printf '%s\n' "$2" | grep -qF -- "$3"; then
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected NOT to find: %s\n  in:\n%s\n\n' "$1" "$3" "$2"
  else
    pass=$((pass + 1))
  fi
}

assert_eq() { # NAME EXPECTED ACTUAL
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n\n' "$1" "$2" "$3"
  fi
}

run_with_file() { # FIXTURE_PATH -> sets out, rc
  out="$(CHECK_USAGE_INPUT_FILE="$1" bash "$SCRIPT" 2>&1)"
  rc=$?
}

# --- A4: canned input ---------------------------------------------------------

run_with_file "$FIX/normal.txt"
assert_eq       "normal: exit 0" 0 "$rc"
assert_contains "normal: session line relayed" "$out" "Current session: 23% used"
assert_contains "normal: week line relayed" "$out" "Current week (all models): 49% used"
assert_contains "normal: per-model line relayed" "$out" "Current week (Fable): 2% used"
assert_not_contains "normal: no WARNING" "$out" "WARNING"

run_with_file "$FIX/weekly-exhausted.txt"
assert_eq       "exhausted: exit 0" 0 "$rc"
assert_contains "exhausted: WARNING fires" "$out" "WARNING: weekly quota is exhausted (100%) but the session limit still shows room (36%)."
assert_contains "exhausted: points to /usage-credits" "$out" "/usage-credits"

run_with_file "$FIX/week-permodel-only.txt"
assert_eq       "permodel-only: exit 0" 0 "$rc"
assert_contains "permodel-only: session relayed" "$out" "Current session: 12% used"
assert_not_contains "permodel-only: no WARNING without all-models line" "$out" "WARNING"

run_with_file "$FIX/does-not-exist.txt"
assert_eq       "unreadable input file: exit 2" 2 "$rc"
assert_contains "unreadable input file: explains" "$out" "check-usage: CHECK_USAGE_INPUT_FILE is set but"

# --- summary ------------------------------------------------------------------

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bash tests/test-check-usage.sh`
Expected: several FAIL lines. The current script ignores `CHECK_USAGE_INPUT_FILE` and calls the real `claude`, so the fixture content never appears and the unreadable-file case does not exit 2. Final line shows a non-zero failed count and the script exits 1.

- [ ] **Step 4: Rewrite the script to honour `CHECK_USAGE_INPUT_FILE`**

Replace `scripts/check-usage.sh` with:
```bash
#!/bin/bash
# Report Claude Code session/weekly usage against subscription limits.
#
# Environment:
#   CHECK_USAGE_INPUT_FILE  read /usage text from this file instead of calling claude (testing, canned output)
set -uo pipefail

if [ -n "${CHECK_USAGE_INPUT_FILE:-}" ]; then
  if [ ! -r "$CHECK_USAGE_INPUT_FILE" ]; then
    echo "check-usage: CHECK_USAGE_INPUT_FILE is set but '$CHECK_USAGE_INPUT_FILE' is not readable."
    exit 2
  fi
  output="$(cat "$CHECK_USAGE_INPUT_FILE")"
else
  output="$(claude -p "/usage" 2>&1)"
fi

matched="$(echo "$output" | grep -iE '^Current (session|week)|credit|extra usage|overage' || true)"

if [ -z "$matched" ]; then
  echo "$output"
  exit 0
fi

echo "$matched"

session_pct="$(echo "$matched" | grep -m1 -i '^Current session' | grep -oE '[0-9]+%' | head -1 | tr -d '%' || true)"
week_pct="$(echo "$matched" | grep -m1 -i '^Current week (all models)' | grep -oE '[0-9]+%' | head -1 | tr -d '%' || true)"

if [ -n "${week_pct:-}" ] && [ -n "${session_pct:-}" ] && [ "$week_pct" -ge 100 ] && [ "$session_pct" -lt 100 ]; then
  echo
  echo "WARNING: weekly quota is exhausted (${week_pct}%) but the session limit still shows room (${session_pct}%)."
  echo "A healthy session percentage does not mean capacity is fine here — if requests are still succeeding,"
  echo "that overflow is either being billed as purchased usage credits (extra usage), or you're in a brief"
  echo "grace window before a hard stop. Run '/usage-credits' in an interactive session to confirm which."
fi
```

Note the only behavioural changes in this step: `set -e` is dropped (Task 2 depends on being able to inspect the exit code), and the input-file branch is added. The WARNING text is unchanged.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/test-check-usage.sh`
Expected: `13 passed, 0 failed`, exit 0.

- [ ] **Step 6: Run the live script once to confirm nothing regressed**

Run: `bash scripts/check-usage.sh`
Expected: three `Current …` lines with real percentages (no WARNING unless the week really is at 100%).

- [ ] **Step 7: Commit**

```bash
git add tests/ scripts/check-usage.sh
git commit -m "Add CHECK_USAGE_INPUT_FILE hook and bash test harness

Lets the script be tested against canned /usage output without a live
account (FINDINGS A4). Drops set -e so later failure handling can
inspect exit codes. WARNING behaviour unchanged and now pinned by tests.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ub6MrWMjj4X3nxSh8jzwKV"
```

---

### Task 2: Loud failures and the near-exhaustion NOTICE (A1, B3)

**Files:**
- Modify: `scripts/check-usage.sh` (the branch between obtaining `output` and computing `matched`, and the tail after the WARNING block)
- Modify: `tests/test-check-usage.sh` (append tests before the summary section)
- Create: `tests/fixtures/cost-summary.txt`
- Create: `tests/fixtures/weekly-near.txt`
- Create: `tests/fixtures/both-100.txt`

**Interfaces:**
- Consumes: `run_with_file`, `assert_*` from Task 1.
- Produces: new env knob `CHECK_USAGE_CLAUDE_BIN` (default `claude`); new helper in tests `run_with_fake_claude BODY` which writes an executable fake `claude` containing `BODY`, runs the script with `CHECK_USAGE_CLAUDE_BIN` pointing at it, sets `out` and `rc`. Exit codes: 0 success or no-match; 1 CLI failed or empty output; 2 bad input file; 127 CLI not found.

- [ ] **Step 1: Create the fixtures**

`tests/fixtures/cost-summary.txt` (what `claude -p "/usage"` prints when not signed in to a subscription):
```
Total cost:            $0.0000
Total duration (API):  0s
Total duration (wall): 1s
Total code changes:    0 lines added, 0 lines removed
Usage:                 0 input, 0 output, 0 cache read, 0 cache write
```

`tests/fixtures/weekly-near.txt`:
```
Current session: 23% used · resets Oct 3 at 7:19pm (Europe/London)
Current week (all models): 97% used · resets Oct 5 at 4:59am (Europe/London)
```

`tests/fixtures/both-100.txt`:
```
Current session: 100% used · resets Oct 3 at 7:19pm (Europe/London)
Current week (all models): 100% used · resets Oct 5 at 4:59am (Europe/London)
```

- [ ] **Step 2: Append the failing tests**

Insert into `tests/test-check-usage.sh` immediately above the `# --- summary` line:
```bash
# --- A1: loud failures --------------------------------------------------------

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

run_with_fake_claude() { # BODY -> sets out, rc. BODY is the fake claude's script body.
  printf '#!/bin/bash\n%s\n' "$1" > "$TMP/claude"
  chmod +x "$TMP/claude"
  out="$(CHECK_USAGE_CLAUDE_BIN="$TMP/claude" bash "$SCRIPT" 2>&1)"
  rc=$?
}

out="$(CHECK_USAGE_CLAUDE_BIN="$TMP/no-such-claude" bash "$SCRIPT" 2>&1)"; rc=$?
assert_eq       "cli missing: exit 127" 127 "$rc"
assert_contains "cli missing: explains" "$out" "check-usage: 'claude' not found"

run_with_fake_claude 'echo "Not logged in. Please run claude login." >&2; exit 1'
assert_eq       "cli fails: exit 1" 1 "$rc"
assert_contains "cli fails: reports exit code" "$out" "check-usage: 'claude -p /usage' failed (exit 1)"
assert_contains "cli fails: shows captured output" "$out" "Not logged in"

run_with_fake_claude 'exit 0'
assert_eq       "cli empty: exit 1" 1 "$rc"
assert_contains "cli empty: explains" "$out" "check-usage: 'claude -p /usage' returned no output"

run_with_fake_claude 'echo "Current session: 5% used"; echo "boom" >&2; exit 3'
assert_eq       "cli lines then nonzero: treated as failure" 1 "$rc"
assert_contains "cli lines then nonzero: reports exit code" "$out" "(exit 3)"

run_with_file "$FIX/cost-summary.txt"
assert_eq       "cost summary: exit 0" 0 "$rc"
assert_contains "cost summary: says no structured lines" "$out" "check-usage: no session/week lines found"
assert_contains "cost summary: hints not signed in" "$out" "per-session cost summary"
assert_contains "cost summary: echoes raw output" "$out" "Total cost:"

# --- B3: NOTICE near exhaustion ----------------------------------------------

run_with_file "$FIX/weekly-near.txt"
assert_eq       "near: exit 0" 0 "$rc"
assert_contains "near: NOTICE fires" "$out" "NOTICE: weekly quota is nearly exhausted (97%)"
assert_contains "near: mentions credits" "$out" "usage credits"
assert_not_contains "near: no WARNING below 100" "$out" "WARNING"

run_with_file "$FIX/both-100.txt"
assert_eq       "both 100: exit 0" 0 "$rc"
assert_not_contains "both 100: no WARNING when session has no room" "$out" "WARNING"
assert_not_contains "both 100: no NOTICE at 100" "$out" "NOTICE"

run_with_file "$FIX/normal.txt"
assert_not_contains "normal: no NOTICE at 49" "$out" "NOTICE"
```

- [ ] **Step 3: Run the tests to verify the new ones fail**

Run: `bash tests/test-check-usage.sh`
Expected: the 13 Task 1 assertions pass; the new A1/B3 assertions fail (the script ignores `CHECK_USAGE_CLAUDE_BIN`, prints nothing on failure, has no NOTICE). Exit 1.

- [ ] **Step 4: Implement the failure handling and NOTICE**

Replace the whole of `scripts/check-usage.sh` with:
```bash
#!/bin/bash
# Report Claude Code session/weekly usage against subscription limits.
#
# Environment:
#   CHECK_USAGE_INPUT_FILE  read /usage text from this file instead of calling claude (testing, canned output)
#   CHECK_USAGE_CLAUDE_BIN  claude binary to call (default: claude)
#
# Exit codes: 0 ok (or no structured lines found); 1 claude failed or returned nothing;
#             2 CHECK_USAGE_INPUT_FILE unreadable; 127 claude not found.
set -uo pipefail

claude_bin="${CHECK_USAGE_CLAUDE_BIN:-claude}"

if [ -n "${CHECK_USAGE_INPUT_FILE:-}" ]; then
  if [ ! -r "$CHECK_USAGE_INPUT_FILE" ]; then
    echo "check-usage: CHECK_USAGE_INPUT_FILE is set but '$CHECK_USAGE_INPUT_FILE' is not readable."
    exit 2
  fi
  output="$(cat "$CHECK_USAGE_INPUT_FILE")"
  status=0
else
  if ! command -v "$claude_bin" >/dev/null 2>&1; then
    echo "check-usage: 'claude' not found (looked for '$claude_bin'). Usage figures are unavailable."
    exit 127
  fi
  output="$("$claude_bin" -p "/usage" 2>&1)"
  status=$?
fi

if [ "$status" -ne 0 ]; then
  echo "check-usage: 'claude -p /usage' failed (exit $status). Usage figures are unavailable. Output was:"
  echo "$output" | head -20
  exit 1
fi

if [ -z "$(echo "$output" | tr -d '[:space:]')" ]; then
  echo "check-usage: 'claude -p /usage' returned no output (exit 0). Usage figures are unavailable."
  echo "Likely causes: not signed in to a subscription in this environment, or /usage output format changed."
  exit 1
fi

matched="$(echo "$output" | grep -iE '^Current (session|week)|credit|extra usage|overage' || true)"

if [ -z "$matched" ]; then
  echo "check-usage: no session/week lines found in /usage output, so structured percentages are not available."
  if echo "$output" | grep -qE '^Total cost:'; then
    echo "check-usage: this is the per-session cost summary, which /usage prints when the CLI is not signed in to a"
    echo "subscription here (API-key billing, or an isolated config dir). There is no session/weekly quota to report."
  fi
  echo "Raw output follows:"
  echo "$output"
  exit 0
fi

echo "$matched"

session_pct="$(echo "$matched" | grep -m1 -i '^Current session' | grep -oE '[0-9]+%' | head -1 | tr -d '%' || true)"
week_pct="$(echo "$matched" | grep -m1 -i '^Current week (all models)' | grep -oE '[0-9]+%' | head -1 | tr -d '%' || true)"

if [ -n "${week_pct:-}" ] && [ -n "${session_pct:-}" ] && [ "$week_pct" -ge 100 ] && [ "$session_pct" -lt 100 ]; then
  echo
  echo "WARNING: weekly quota is exhausted (${week_pct}%) but the session limit still shows room (${session_pct}%)."
  echo "A healthy session percentage does not mean capacity is fine here — if requests are still succeeding,"
  echo "that overflow is either being billed as purchased usage credits (extra usage), or you're in a brief"
  echo "grace window before a hard stop. Run '/usage-credits' in an interactive session to confirm which."
elif [ -n "${week_pct:-}" ] && [ "$week_pct" -ge 95 ] && [ "$week_pct" -lt 100 ]; then
  echo
  echo "NOTICE: weekly quota is nearly exhausted (${week_pct}%). Once it reaches 100%, further requests either"
  echo "bill purchased usage credits (real money, if enabled) or stop. Flag this before continuing multi-step work,"
  echo "and prefer to pause at a step boundary rather than mid-step."
fi
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/test-check-usage.sh`
Expected: `34 passed, 0 failed`, exit 0. (If your count differs by one or two, check you appended every assertion; the point is zero failures.)

- [ ] **Step 6: Run the live script and the not-signed-in reproduction**

Run: `bash scripts/check-usage.sh`
Expected: three `Current …` lines with real numbers, exit 0.

Run: `CLAUDE_CONFIG_DIR="$(mktemp -d)" bash scripts/check-usage.sh; echo "exit=$?"`
Expected: either the `check-usage: no session/week lines found` message with the cost-summary hint and `exit=0`, or `check-usage: 'claude -p /usage' failed (exit N)` with `exit=1`. Either way, at least one explanatory line. Silence is a failure of this task.

- [ ] **Step 7: Commit**

```bash
git add tests/ scripts/check-usage.sh
git commit -m "Fail loudly when /usage cannot be read; add near-exhaustion NOTICE

Every exit path now prints a check-usage: line explaining what happened
(CLI missing, CLI failed with exit code and output, empty output, or no
structured lines with a not-signed-in hint). Adds CHECK_USAGE_CLAUDE_BIN
for tests. Prints a NOTICE at 95-99% weekly so direct Bash runs that
bypass SKILL.md still see the interpretation (FINDINGS A1, B3).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ub6MrWMjj4X3nxSh8jzwKV"
```

---

### Task 3: SKILL.md triggers, interpretation rules, and README docs (A2, A3, B1, B2, A4 docs)

**Files:**
- Modify: `SKILL.md` (whole file)
- Modify: `README.md` sections "What it reports", "How it works", add "Testing" and "Environment variables"

**Interfaces:**
- Consumes: script output formats from Tasks 1–2 (`check-usage:` prefix lines, `WARNING:`, `NOTICE:`, env vars).
- Produces: nothing code-level. The eval suite's case 03 depends on this SKILL.md firing on pasted-output prompts.

- [ ] **Step 1: Replace SKILL.md**

```markdown
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
```

- [ ] **Step 2: Update README.md**

In "What it reports", replace the two-line example block and the paragraph after it with:
```markdown
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

Keep the existing WARNING example block and the paragraph after it ("This matters because…") unchanged.

After the "How it works" bullets, add:
```markdown
## When it cannot get numbers

Every failure prints a line starting with `check-usage:` saying what happened, and the script exits
non-zero where the figures are unavailable:

| situation | output | exit |
|---|---|---|
| `claude` not on PATH | `check-usage: 'claude' not found …` | 127 |
| `claude -p "/usage"` exits non-zero | `check-usage: 'claude -p /usage' failed (exit N)…` plus its output | 1 |
| it exits 0 with no output | `check-usage: 'claude -p /usage' returned no output…` | 1 |
| output has no session/week lines (e.g. the per-session cost summary when not signed in to a subscription, or API-key billing) | `check-usage: no session/week lines found…` plus the raw output | 0 |

## Testing

```bash
bash tests/test-check-usage.sh
```

The tests never call the real CLI. Two environment variables make that possible and are also handy
for trying the skill's behaviour by hand:

- `CHECK_USAGE_INPUT_FILE=<path>` reads canned `/usage` text from a file (see `tests/fixtures/`).
- `CHECK_USAGE_CLAUDE_BIN=<path>` calls a different `claude` binary.

```bash
CHECK_USAGE_INPUT_FILE=tests/fixtures/weekly-exhausted.txt bash scripts/check-usage.sh
```
```

- [ ] **Step 3: Sanity-check the frontmatter and rendering**

Run: `head -4 SKILL.md | sed -n '1,4p' && awk 'NR==3' SKILL.md | wc -c`
Expected: `---`, `name: check-usage`, a one-line `description: …`, `---`. The description line is under 1024 characters (the printed count is well below 1024).

Run: `grep -c '^## ' SKILL.md README.md`
Expected: SKILL.md 7 sections; README.md count increases by 2 compared to before the edit.

- [ ] **Step 4: Run the tests (docs change must not break anything)**

Run: `bash tests/test-check-usage.sh`
Expected: `… 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add SKILL.md README.md
git commit -m "Widen check-usage triggers and document interpretation rules

Description now covers task kickoff, step boundaries, resume after reset,
and pasted /usage output, and drops the /compact clause (context is not
quota). Documents the per-model week line, the check-usage: failure
lines, a recommended decision rule, and the test hooks (FINDINGS A2, A3,
B1, B2, A4).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ub6MrWMjj4X3nxSh8jzwKV"
```

---

### Task 4: Standard plugin layout (D)

**Files:**
- Create: `.claude-plugin/plugin.json`
- Move: `SKILL.md` → `skills/check-usage/SKILL.md`
- Move: `scripts/check-usage.sh` → `skills/check-usage/scripts/check-usage.sh`
- Modify: `install.sh` (the `SRC` line)
- Modify: `tests/test-check-usage.sh` (the `SCRIPT=` default)
- Modify: `README.md` "How it works" paths and the Testing example path

**Interfaces:**
- Consumes: everything above.
- Produces: plugin manifest named `claude-usage-skill`; `~/.claude/skills/check-usage` → `<repo>/skills/check-usage`.

- [ ] **Step 1: Move the files with git**

```bash
mkdir -p skills/check-usage .claude-plugin
git mv SKILL.md skills/check-usage/SKILL.md
git mv scripts skills/check-usage/scripts
```

- [ ] **Step 2: Create the manifest**

`.claude-plugin/plugin.json`:
```json
{
  "name": "claude-usage-skill",
  "description": "Reports live Claude Code session and weekly usage against subscription limits, with reset times, so long-running sessions can pace themselves.",
  "version": "0.2.0",
  "author": {
    "name": "mhollander38",
    "url": "https://github.com/mhollander38/claude-usage-skill"
  }
}
```

- [ ] **Step 3: Point install.sh and the tests at the new location**

In `install.sh`, change
```bash
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```
to
```bash
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO/skills/check-usage"
```

In `tests/test-check-usage.sh`, change
```bash
SCRIPT="${CHECK_USAGE_SCRIPT:-$ROOT/scripts/check-usage.sh}"
```
to
```bash
SCRIPT="${CHECK_USAGE_SCRIPT:-$ROOT/skills/check-usage/scripts/check-usage.sh}"
```

- [ ] **Step 4: Update README paths**

In "How it works", change the three bullets to:
```markdown
- `skills/check-usage/SKILL.md` — instructions telling Claude to run the bundled script and how to
  report and interpret what it prints.
- `skills/check-usage/scripts/check-usage.sh` — runs `claude -p "/usage"`, extracts the session and
  week lines, and adds a `NOTICE`/`WARNING` block when the week is nearly or fully exhausted.
- `install.sh` — symlinks `skills/check-usage` into `~/.claude/skills/check-usage`.
- `.claude-plugin/plugin.json` — plugin manifest, so the repo can also be installed as a plugin or
  run under `claude plugin eval`.
```

In the Testing section, change `bash scripts/check-usage.sh` to `bash skills/check-usage/scripts/check-usage.sh`.

- [ ] **Step 5: Run tests, then refresh the live symlink**

Run: `bash tests/test-check-usage.sh`
Expected: `… 0 failed`, exit 0.

Run: `./install.sh && ls -l ~/.claude/skills/check-usage && test -f ~/.claude/skills/check-usage/SKILL.md && echo SKILL_OK`
Expected: `Linked /Users/…/.claude/skills/check-usage -> …/claude-usage-skill/skills/check-usage`, the `ls` shows the symlink target ending in `/skills/check-usage`, and `SKILL_OK`.

Run: `bash ~/.claude/skills/check-usage/scripts/check-usage.sh`
Expected: real usage lines, exit 0.

- [ ] **Step 6: Commit**

```bash
git add -A .claude-plugin skills install.sh tests README.md
git commit -m "Move to standard plugin layout

SKILL.md and the script now live under skills/check-usage/, with a
.claude-plugin/plugin.json manifest. install.sh symlinks the skill
subdirectory so the existing ~/.claude/skills/check-usage install keeps
working after re-running it (FINDINGS D).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ub6MrWMjj4X3nxSh8jzwKV"
```

---

### Task 5: Verify against the eval suite and close out FINDINGS

**Files:**
- Modify: `evals/FINDINGS.md` (add a `Status` line under each item in A, B, D)

**Interfaces:**
- Consumes: the full suite under `evals/`, unchanged.
- Produces: a pilot result under `evals/results/` (gitignored) and status notes in FINDINGS.

- [ ] **Step 1: Run the unit tests one final time**

Run: `bash tests/test-check-usage.sh`
Expected: `… 0 failed`, exit 0.

- [ ] **Step 2: Run the eval pilot**

Run (from the repo root, takes 5–7 minutes, about $3.50):
```bash
claude plugin eval . --runs 1 --ablation with-without --no-scaffold --no-publish --judge-model sonnet --allow-tools "Bash(bash:*)" 2>&1 | tail -14
```
Expected: a table of six cases. Check specifically:
- The runner printed no `⚠ case … cannot pass with the granted tools`.
- `01-direct-question` and `02-task-kickoff` with-arm still score 1.00 and `skill-fired` shows `Skill called 1x`. Their final replies should now quote a `check-usage:` line (the script explains itself) rather than "the script printed nothing".
- `03-week-exhausted` with-arm: look at whether `skill-fired` is now `1x` and whether `points-to-usage-credits` passes. A positive Δ here means A3/B1 worked; Δ 0 with the skill still not firing means the description still does not trigger on pasted output, which is recorded, not hidden.
- `05-neg-*` and `06-neg-*`: `skill-not-fired` still `0x` in both arms. If the wider description now fires the skill on the negatives, that is a regression to fix in SKILL.md's description before committing Task 5.

- [ ] **Step 3: Confirm the plugin loaded in the pilot**

Run:
```bash
python3 -c "import json,glob; a=json.load(open(sorted(glob.glob('evals/results/*/aggregate-result.json'))[-1])); print(a['suite']['plugins']); print(round(a['costUsd'],2))"
```
Expected: one entry named `claude-usage-skill` with no `problem` key, and a cost figure near $3.50.

- [ ] **Step 4: Record status in FINDINGS.md**

Under each heading in sections A, B and D, add one line in this form, filling in the real commit hashes from `git log --oneline -5`:
```markdown
**Status (2026-10-03):** resolved in `<hash>` — <one clause on what changed>.
```
For B2, write `**Status (2026-10-03):** partially addressed in <hash> — SKILL.md now carries a recommended decision rule; CLAUDE.md policy still overrides.` For C-section items, leave as they are (known limitations) except C1: append `A4 is now implemented; a future eval case can use CHECK_USAGE_INPUT_FILE with a fixture to cover the WARNING branch end to end.`

Also append a line to section C2 with the pilot's actual per-case Δ from Step 2.

- [ ] **Step 5: Commit**

```bash
git add evals/FINDINGS.md
git commit -m "Record resolution status for eval findings

Adds status lines for FINDINGS A, B and D after the fixes, with the
post-fix pilot deltas.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ub6MrWMjj4X3nxSh8jzwKV"
```

- [ ] **Step 6: Push**

```bash
git push origin main
```
Expected: `main -> main` fast-forward.
