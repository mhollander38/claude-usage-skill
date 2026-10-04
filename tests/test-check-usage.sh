#!/bin/bash
# Plain-bash tests for skills/check-usage/scripts/check-usage.sh. Run: bash tests/test-check-usage.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${CHECK_USAGE_SCRIPT:-$ROOT/skills/check-usage/scripts/check-usage.sh}"
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
  out="$(CHECK_USAGE_INPUT_FILE="$1" CHECK_USAGE_CLAUDE_BIN="$TMP/sentinel" bash "$SCRIPT" 2>&1)"
  rc=$?
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
printf '#!/bin/bash\necho SENTINEL-CALLED; exit 99\n' > "$TMP/sentinel"
chmod +x "$TMP/sentinel"
# Isolate from the real environment: a stray HOME or config dir must never be read.
mkdir -p "$TMP/home"
export HOME="$TMP/home"
unset CLAUDE_CONFIG_DIR
unset CHECK_USAGE_CACHE_FILE CHECK_USAGE_NO_CACHE CHECK_USAGE_PYTHON CHECK_USAGE_CACHE_MAX_AGE CHECK_USAGE_NOW_MS CHECK_USAGE_INPUT_FILE CHECK_USAGE_CLAUDE_BIN CHECK_USAGE_CLI_VERSION CHECK_USAGE_DEBUG

# --- A4: canned input ---------------------------------------------------------

run_with_file "$FIX/normal.txt"
assert_eq       "normal: exit 0" 0 "$rc"
assert_contains "normal: session line relayed" "$out" "Current session: 23% used"
assert_contains "normal: week line relayed" "$out" "Current week (all models): 49% used"
assert_contains "normal: per-model line relayed" "$out" "Current week (Fable): 2% used"
assert_not_contains "normal: no WARNING" "$out" "WARNING"
assert_contains "normal: canned marker" "$out" "check-usage: reading canned /usage output"

run_with_file "$FIX/weekly-exhausted.txt"
assert_eq       "exhausted: exit 0" 0 "$rc"
assert_contains "exhausted: WARNING fires" "$out" "WARNING: weekly quota is exhausted (100%) but the session limit still shows room (36%)."
assert_contains "exhausted: points to /usage-credits" "$out" "/usage-credits"

run_with_file "$FIX/week-permodel-only.txt"
assert_eq       "permodel-only: exit 0" 0 "$rc"
assert_contains "permodel-only: session relayed" "$out" "Current session: 12% used"
assert_not_contains "permodel-only: no WARNING without all-models line" "$out" "WARNING"
assert_contains "permodel-only: per-model line relayed" "$out" "Current week (Fable): 100% used"
assert_not_contains "permodel-only: no NOTICE without all-models line" "$out" "NOTICE"

run_with_file "$FIX/does-not-exist.txt"
assert_eq       "unreadable input file: exit 2" 2 "$rc"
assert_contains "unreadable input file: explains" "$out" "check-usage: CHECK_USAGE_INPUT_FILE is set but"
assert_not_contains "unreadable input file: CLI not called" "$out" "SENTINEL-CALLED"

run_with_file "$TMP"
assert_eq       "directory input file: exit 2" 2 "$rc"

# --- A1: loud failures --------------------------------------------------------

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
assert_contains "cli lines then nonzero: shows partial output" "$out" "Current session: 5% used"
assert_contains "cli lines then nonzero: shows stderr" "$out" "boom"

run_with_file "$FIX/cost-summary.txt"
assert_eq       "cost summary: exit 0" 0 "$rc"
assert_contains "cost summary: says no structured lines" "$out" "check-usage: no session/week lines found"
assert_contains "cost summary: hints not signed in" "$out" "per-session cost summary"
assert_contains "cost summary: echoes raw output" "$out" "Total cost:"

run_with_file "$FIX/credits-only.txt"
assert_eq       "credits only: exit 0" 0 "$rc"
assert_contains "credits only: explains no structured lines" "$out" "check-usage: no session/week lines found"
assert_contains "credits only: cost summary hint" "$out" "per-session cost summary"
assert_contains "credits only: raw echoed" "$out" "Usage credits are off"

# --- B3: NOTICE near exhaustion ----------------------------------------------

run_with_file "$FIX/weekly-near.txt"
assert_eq       "near: exit 0" 0 "$rc"
assert_contains "near: NOTICE fires" "$out" "NOTICE: weekly quota is nearly exhausted (97%)"
assert_contains "near: mentions credits" "$out" "usage credits"
assert_not_contains "near: no WARNING below 100" "$out" "WARNING"

run_with_file "$FIX/both-100.txt"
assert_eq       "both 100: exit 0" 0 "$rc"
assert_contains "both 100: session line still printed" "$out" "Current session: 100% used"
assert_contains "both 100: week line still printed" "$out" "Current week (all models): 100% used"
assert_not_contains "both 100: no WARNING when session has no room" "$out" "WARNING"
assert_not_contains "both 100: no NOTICE at 100" "$out" "NOTICE"

run_with_file "$FIX/normal.txt"
assert_not_contains "normal: no NOTICE at 49" "$out" "NOTICE"

run_with_file "$FIX/weekly-95.txt"
assert_contains "weekly 95: NOTICE fires" "$out" "NOTICE: weekly quota is nearly exhausted (95%)"

run_with_file "$FIX/weekly-99.txt"
assert_contains "weekly 99: NOTICE fires" "$out" "NOTICE: weekly quota is nearly exhausted (99%)"

run_with_file "$FIX/weekly-decimal-near.txt"
assert_eq       "decimal near: exit 0" 0 "$rc"
assert_contains "decimal near: NOTICE shows original" "$out" "NOTICE: weekly quota is nearly exhausted (99.5%)"
assert_not_contains "decimal near: no WARNING" "$out" "WARNING"

run_with_file "$FIX/weekly-decimal-exhausted.txt"
assert_eq       "decimal exhausted: exit 0" 0 "$rc"
assert_contains "decimal exhausted: WARNING shows original" "$out" "WARNING: weekly quota is exhausted (100%) but the session limit still shows room (36.4%)."

# --- Enrichment helper (usage-cache.py) -------------------------------------

NOW_MS=1791094954300   # 30 s after the fixtures' fetchedAtMs
CACHE_PY="$(dirname "$SCRIPT")/usage-cache.py"

if command -v python3 >/dev/null 2>&1; then
  run_cache_py() { # CACHE_FILE [NOW_MS] [VAR=value ...] -> sets out, rc
    local cf="$1" now="${2:-$NOW_MS}"
    shift
    [ $# -gt 0 ] && shift
    out="$(env CHECK_USAGE_NOW_MS="$now" "$@" python3 "$CACHE_PY" "$cf" 2>&1)"
    rc=$?
  }

  run_cache_py "$FIX/cache-max5x.json"
  assert_eq       "cache max5x: exit 0" 0 "$rc"
  assert_contains "cache max5x: plan" "$out" "Plan: Max 5x"
  assert_contains "cache max5x: binding limit" "$out" "Binding limit: session 84%"
  assert_contains "cache max5x: out of credits" "$out" "Usage credits: ON but out of credits (balance £0.00), so work stops when a plan limit is hit"
  assert_contains "cache max5x: cloud credit" "$out" "Cloud session credit (cloud sessions only): \$103.13 of \$250.00 left · expires Nov 5"
  assert_not_contains "cache max5x: no obfuscated key" "$out" "iguana"
  assert_not_contains "cache max5x: no email" "$out" "example.com"
  assert_not_contains "cache max5x: no uuid" "$out" "00000000-"

  run_cache_py "$FIX/cache-credits-on.json" "" CHECK_USAGE_DEBUG=1
  assert_contains "cache credits on: pro plan note" "$out" "Plan: Pro (Fable models are not included; they always use usage credits)"
  assert_contains "cache credits on: weekly binding" "$out" "Binding limit: weekly (all models) 100%"
  assert_contains "cache credits on: billed" "$out" "Usage credits: ON · £12.60 used of £25.00 monthly limit (work past a plan limit is billed at API rates)"

  assert_contains "cache credits on: state billed" "$out" "Credits state: billed"

  run_cache_py "$FIX/cache-credits-on-null.json" "" CHECK_USAGE_DEBUG=1
  assert_contains "cache credits on null used: billed line" "$out" "Usage credits: ON (work past a plan limit is billed at API rates)"
  assert_contains "cache credits on null used: state billed" "$out" "Credits state: billed"

  run_cache_py "$FIX/cache-max5x.json" "" CHECK_USAGE_DEBUG=1
  assert_contains "cache max5x: state stop" "$out" "Credits state: stop"
  assert_eq "cache max5x: state is last line" "Credits state: stop" "$(printf '%s\n' "$out" | tail -1)"

  run_cache_py "$FIX/cache-unknown-bucket.json" "" CHECK_USAGE_DEBUG=1
  assert_contains     "cache unknown bucket: listed" "$out" "Included credit: \$20.00 of \$20.00 left"
  assert_contains     "cache unknown bucket: state stop" "$out" "Credits state: stop"
  assert_not_contains "cache unknown bucket: no local note" "$out" "Local included credit available"
  assert_not_contains "cache unknown bucket: no codename" "$out" "mystery"

  run_cache_py "$FIX/cache-user-disabled.json" "" CHECK_USAGE_DEBUG=1
  assert_contains "cache user disabled: line" "$out" "Usage credits: OFF (turned off in settings), so work stops when a plan limit is hit"
  assert_contains "cache user disabled: state stop" "$out" "Credits state: stop"
  assert_not_contains "cache user disabled: not out of credits" "$out" "out of credits"

  run_cache_py "$FIX/cache-no-currency.json" "" CHECK_USAGE_DEBUG=1
  assert_contains     "cache no currency: line" "$out" "Usage credits: ON but out of credits, so work stops when a plan limit is hit"
  assert_not_contains "cache no currency: no balance" "$out" "balance"

  run_cache_py "$FIX/cache-org-disabled.json" "" CHECK_USAGE_DEBUG=1
  assert_contains "cache org disabled: known reason" "$out" "Usage credits: OFF (org_level_disabled), so work stops when a plan limit is hit"

  run_cache_py "$FIX/cache-max5x.json" 1791095524300   # 600 s later
  assert_eq "cache stale: exit 0" 0 "$rc"
  assert_eq "cache stale: no output" "" "$out"

  run_cache_py "$FIX/cache-max5x.json" 1791094000000   # cache 15 min in the future
  assert_eq "cache future: no output" "" "$out"

  run_cache_py "$FIX/cache-other-account.json"
  assert_eq "cache other account: no output" "" "$out"

  run_cache_py "$FIX/cache-malformed.json"
  assert_eq "cache malformed: exit 0" 0 "$rc"
  assert_eq "cache malformed: no output" "" "$out"

  run_cache_py "$FIX/cache-partial.json"
  assert_eq "cache partial: exit 0" 0 "$rc"
  assert_not_contains "cache partial: no traceback" "$out" "Traceback"
  assert_eq "cache partial: no output" "" "$out"

  run_cache_py "$FIX/cache-bad-scope.json"
  assert_contains "cache bad scope: plan" "$out" "Plan: Max 5x"
  assert_contains "cache bad scope: credits" "$out" "Usage credits: ON but out of credits"
  assert_contains "cache bad scope: binding" "$out" "Binding limit: weekly (scoped) 100%"

  run_cache_py "$FIX/cache-no-account.json"
  assert_eq "cache no cache account: no output" "" "$out"

  run_cache_py "$FIX/cache-local-credit.json" "" CHECK_USAGE_DEBUG=1
  assert_contains     "cache local credit: state local" "$out" "Credits state: local"
  assert_contains     "cache local credit: bucket" "$out" "Claude Code and Cowork credit: \$50.00 of \$50.00 left"
  assert_contains     "cache local credit: note" "$out" "Local included credit available"
  assert_not_contains "cache local credit: no obfuscated key" "$out" "cinder"

  run_cache_py "$FIX/cache-spend-cap.json" "" CHECK_USAGE_DEBUG=1
  assert_contains "cache spend cap: line" "$out" "Usage credits: ON but monthly spend limit reached (£25.00 of £25.00)"

  run_cache_py "$FIX/cache-odd-values.json" "" CHECK_USAGE_DEBUG=1
  assert_contains     "cache odd: tier" "$out" "Plan: unrecognised tier"
  assert_contains     "cache odd: binding" "$out" "Binding limit: another limit 50%"
  assert_contains     "cache odd: off" "$out" "Usage credits: OFF, so work stops when a plan limit is hit"
  assert_not_contains "cache odd: no kind" "$out" "otter"
  assert_not_contains "cache odd: no reason" "$out" "zebra"
  assert_not_contains "cache odd: no tier id" "$out" "some_new_tier"

  run_cache_py "$TMP/does-not-exist.json"
  assert_eq "cache missing: exit 0" 0 "$rc"
  assert_eq "cache missing: no output" "" "$out"

  WRAP='Wrap-up allowance: if the 5-hour limit is reached mid-response, Claude Code may keep working briefly to a stopping point ("Usage limit reached · wrapping up"). It counts toward the weekly limit and never covers starting new work.'
  run_cache_py "$FIX/cache-max5x.json" "" CHECK_USAGE_CLI_VERSION=2.1.289 CHECK_USAGE_DEBUG=1
  assert_contains "wrap-up max: line" "$out" "$WRAP"
  assert_not_contains "wrap-up max: no pro note" "$out" "once per weekly period"
  assert_not_contains "wrap-up max: no credits-after sentence" "$out" "the wrap-up is used first"

  run_cache_py "$FIX/cache-max5x.json" "" CHECK_USAGE_CLI_VERSION=2.1.276 CHECK_USAGE_DEBUG=1
  assert_not_contains "wrap-up old version: no line" "$out" "Wrap-up allowance"

  run_cache_py "$FIX/cache-max5x.json" "" CHECK_USAGE_CLI_VERSION=2.1.277 CHECK_USAGE_DEBUG=1
  assert_contains "wrap-up exact min version: line" "$out" "Wrap-up allowance:"

  run_cache_py "$FIX/cache-max5x.json" "" CHECK_USAGE_DEBUG=1
  assert_not_contains "wrap-up no version: no line" "$out" "Wrap-up allowance"

  run_cache_py "$FIX/cache-max5x.json" "" CHECK_USAGE_CLI_VERSION=garbage CHECK_USAGE_DEBUG=1
  assert_not_contains "wrap-up bad version: no line" "$out" "Wrap-up allowance"

  run_cache_py "$FIX/cache-pro-near-session.json" "" CHECK_USAGE_CLI_VERSION=2.1.289 CHECK_USAGE_DEBUG=1
  assert_contains "wrap-up pro: once per week" "$out" "On Pro it is available up to once per weekly period."
  assert_contains "wrap-up pro: credits after" "$out" "With usage credits on, the wrap-up is used first, then credits."

  run_cache_py "$FIX/cache-max5x-low-session.json" "" CHECK_USAGE_CLI_VERSION=2.1.289 CHECK_USAGE_DEBUG=1
  assert_not_contains "wrap-up low session: no line" "$out" "Wrap-up allowance"

  # Spend-cap case at session 85% (the fixture is at 40%): credits are ON but capped.
  sed 's/"percent": 40/"percent": 85/; s/"percent": 100/"percent": 50/' "$FIX/cache-spend-cap.json" > "$TMP/spend-cap-85.json"
  run_cache_py "$TMP/spend-cap-85.json" "" CHECK_USAGE_CLI_VERSION=2.1.289 CHECK_USAGE_DEBUG=1
  assert_contains     "wrap-up spend cap: line" "$out" "Wrap-up allowance:"
  assert_not_contains "wrap-up spend cap: no credits-after sentence" "$out" "the wrap-up is used first"

  run_cache_py "$FIX/cache-max5x-session80.json" "" CHECK_USAGE_CLI_VERSION=2.1.289 CHECK_USAGE_DEBUG=1
  assert_contains "wrap-up session exactly 80: line" "$out" "Wrap-up allowance:"

  run_cache_py "$FIX/cache-max5x-session85-week100.json" "" CHECK_USAGE_CLI_VERSION=2.1.289 CHECK_USAGE_DEBUG=1
  assert_not_contains "wrap-up weekly exhausted: no line" "$out" "Wrap-up allowance"

  run_cache_py "$FIX/cache-team.json" "" CHECK_USAGE_CLI_VERSION=2.1.289 CHECK_USAGE_DEBUG=1
  assert_contains     "wrap-up team: plan line" "$out" "Plan: Team"
  assert_not_contains "wrap-up team: no line" "$out" "Wrap-up allowance"
else
  echo "SKIP: python3 not found; enrichment helper tests skipped"
fi

# --- Enrichment wiring --------------------------------------------------------

run_with_cache() { # FIXTURE CACHE_FILE [VAR=value ...] -> sets out, rc
  local fx="$1" cf="$2"
  shift 2
  out="$(env CHECK_USAGE_INPUT_FILE="$fx" CHECK_USAGE_CLAUDE_BIN="$TMP/sentinel" \
    CHECK_USAGE_CACHE_FILE="$cf" CHECK_USAGE_NOW_MS="$NOW_MS" "$@" bash "$SCRIPT" 2>&1)"
  rc=$?
}

if command -v python3 >/dev/null 2>&1; then
  run_with_cache "$FIX/weekly-exhausted.txt" "$FIX/cache-max5x.json"
  assert_eq       "wired out-of-credits: exit 0" 0 "$rc"
  assert_contains "wired out-of-credits: WARNING kept" "$out" "WARNING: weekly quota is exhausted (100%)"
  assert_contains "wired out-of-credits: plan line" "$out" "Plan: Max 5x"
  assert_contains "wired out-of-credits: credits check stop" "$out" "Credits check: usage credits are unavailable (see the Usage credits line), so this is a hard stop, not a bill."

  run_with_cache "$FIX/weekly-exhausted.txt" "$FIX/cache-credits-on.json"
  assert_contains "wired credits on: credits check billed" "$out" "Credits check: usage credits are enabled, so work past 100% is being billed at API rates."
  assert_not_contains "wired credits on: no internal state line" "$out" "Credits state:"

  run_with_cache "$FIX/weekly-exhausted.txt" "$FIX/cache-credits-on-null.json"
  assert_contains     "wired credits on null used: billed check" "$out" "Credits check: usage credits are enabled, so work past 100% is being billed at API rates."
  assert_not_contains "wired credits on null used: not hard stop" "$out" "so this is a hard stop, not a bill."

  run_with_cache "$FIX/weekly-exhausted.txt" "$FIX/cache-unknown-bucket.json"
  assert_contains     "wired unknown bucket: WARNING" "$out" "WARNING: weekly quota is exhausted"
  assert_contains     "wired unknown bucket: hard stop" "$out" "so this is a hard stop, not a bill."
  assert_not_contains "wired unknown bucket: no codename" "$out" "mystery"

  run_with_cache "$FIX/weekly-exhausted.txt" "$FIX/cache-org-disabled.json"
  assert_contains "wired org disabled: line" "$out" "Usage credits: OFF (org_level_disabled), so work stops when a plan limit is hit"
  assert_contains "wired org disabled: hard stop" "$out" "so this is a hard stop, not a bill."

  run_with_cache "$FIX/weekly-decimal-exhausted.txt" "$FIX/cache-max5x.json"
  assert_contains "wired decimal exhausted: hard stop" "$out" "so this is a hard stop, not a bill."

  run_with_cache "$FIX/weekly-exhausted.txt" "$FIX/cache-local-credit.json"
  assert_contains "wired local credit: credits check" "$out" "Credits check: an included credit may cover work past 100%"

  run_with_cache "$FIX/weekly-exhausted.txt" "$FIX/cache-spend-cap.json"
  assert_contains "wired spend cap: credits check stop" "$out" "Credits check: usage credits are unavailable (see the Usage credits line), so this is a hard stop, not a bill."

  run_with_cache "$FIX/weekly-exhausted.txt" "$FIX/cache-max5x.json" CHECK_USAGE_NOW_MS=1791095524300
  assert_contains     "wired stale: WARNING kept" "$out" "WARNING: weekly quota is exhausted"
  assert_not_contains "wired stale: no plan line" "$out" "Plan:"
  assert_not_contains "wired stale: no credits check" "$out" "Credits check:"

  run_with_cache "$FIX/normal.txt" "$FIX/cache-max5x.json" CHECK_USAGE_NO_CACHE=1
  assert_not_contains "wired no-cache flag: no plan line" "$out" "Plan:"

  run_with_cache "$FIX/normal.txt" "$FIX/cache-max5x.json" CHECK_USAGE_PYTHON="$TMP/no-such-python"
  assert_eq           "wired python missing: exit 0" 0 "$rc"
  assert_not_contains "wired python missing: no plan line" "$out" "Plan:"
  assert_contains     "wired python missing: figures still printed" "$out" "Current session: 23% used"

  # The /usage text (23% session) and the cache (84% session) intentionally disagree:
  # this test only checks wiring (helper lines appear, no Credits check without WARNING).
  run_with_cache "$FIX/normal.txt" "$FIX/cache-max5x.json"
  assert_not_contains "wired normal: no credits check without WARNING" "$out" "Credits check:"
  assert_not_contains "wired normal: no internal state line" "$out" "Credits state:"
  assert_contains     "wired normal: binding limit line" "$out" "Binding limit: session 84%"

  # Canned mode must not read the real config even when HOME holds a valid cache.
  mkdir -p "$TMP/home-canned"
  cp "$FIX/cache-max5x.json" "$TMP/home-canned/.claude.json"
  out="$(env -u CLAUDE_CONFIG_DIR HOME="$TMP/home-canned" CHECK_USAGE_INPUT_FILE="$FIX/normal.txt" \
    CHECK_USAGE_CLAUDE_BIN="$TMP/sentinel" CHECK_USAGE_NOW_MS="$NOW_MS" bash "$SCRIPT" 2>&1)"
  assert_not_contains "canned mode ignores HOME cache" "$out" "Plan:"

  run_with_cache "$FIX/normal.txt" "$FIX/cache-max5x.json" CHECK_USAGE_CLI_VERSION=2.1.289
  assert_contains "wired wrap-up: line" "$out" "Wrap-up allowance:"

  # shellcheck disable=SC2016  # ${1:-} belongs to the generated fake script
  printf '#!/bin/bash\nif [ "${1:-}" = "--version" ]; then echo "2.1.290 (Claude Code)"; exit 0; fi\ncat "%s"\n' "$FIX/normal.txt" > "$TMP/fakeclaude-ver"
  chmod +x "$TMP/fakeclaude-ver"
  out="$(env -u CHECK_USAGE_INPUT_FILE CHECK_USAGE_CLAUDE_BIN="$TMP/fakeclaude-ver" CHECK_USAGE_CACHE_FILE="$FIX/cache-max5x.json" CHECK_USAGE_NOW_MS="$NOW_MS" bash "$SCRIPT" 2>&1)"
  assert_contains "live wrap-up: version detected" "$out" "Wrap-up allowance:"
else
  echo "SKIP: python3 not found; enrichment wiring tests skipped"
fi

# --- Plan shapes --------------------------------------------------------------

run_with_file "$FIX/pro-two-line.txt"
assert_eq           "pro two-line: exit 0" 0 "$rc"
assert_contains     "pro two-line: week relayed" "$out" "Current week (all models): 62% used"
assert_not_contains "pro two-line: no WARNING" "$out" "WARNING"

run_with_file "$FIX/max-sonnet-only.txt"
assert_contains     "sonnet-only: per-model line relayed" "$out" "Current week (Sonnet only): 100% used"
assert_not_contains "sonnet-only: per-model 100% is not a WARNING" "$out" "WARNING"
assert_not_contains "sonnet-only: per-model 100% is not a NOTICE" "$out" "NOTICE"

# --- summary ------------------------------------------------------------------

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
