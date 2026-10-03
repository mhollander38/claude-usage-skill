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

# --- summary ------------------------------------------------------------------

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
