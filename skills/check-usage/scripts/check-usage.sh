#!/bin/bash
# Report Claude Code session/weekly usage against subscription limits.
#
# Environment:
#   CHECK_USAGE_INPUT_FILE  read /usage text from this file instead of calling claude (testing, canned output)
#   CHECK_USAGE_CLAUDE_BIN  claude binary to call (default: claude)
#   CHECK_USAGE_CACHE_FILE  Claude Code config JSON to read plan/credits from (default in live mode:
#                           ${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json; canned mode reads none unless set)
#   CHECK_USAGE_NO_CACHE    set to anything non-empty to skip the plan/credits lines
#   CHECK_USAGE_CLI_VERSION Claude Code version (e.g. 2.1.289) for the wrap-up allowance line (live mode:
#                           detected from `claude --version` unless set; canned mode: only if set)
#   CHECK_USAGE_PYTHON      python interpreter for the plan/credits lines (default: python3; optional)
#   CHECK_USAGE_CACHE_MAX_AGE  maximum cache age in seconds (default 180)
#   CHECK_USAGE_NOW_MS      current time in epoch milliseconds (tests)
#   CHECK_USAGE_DEBUG       non-empty: usage-cache.py raises instead of staying silent (tests)
#
# Exit codes: 0 ok (or no structured lines found); 1 claude failed or returned nothing;
#             2 CHECK_USAGE_INPUT_FILE unreadable or not a file; 127 claude not found.
set -uo pipefail

claude_bin="${CHECK_USAGE_CLAUDE_BIN:-claude}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python_bin="${CHECK_USAGE_PYTHON:-python3}"

if [ -n "${CHECK_USAGE_INPUT_FILE:-}" ]; then
  if [ ! -f "$CHECK_USAGE_INPUT_FILE" ] || [ ! -r "$CHECK_USAGE_INPUT_FILE" ]; then
    echo "check-usage: CHECK_USAGE_INPUT_FILE is set but '$CHECK_USAGE_INPUT_FILE' is not readable."
    exit 2
  fi
  output="$(cat "$CHECK_USAGE_INPUT_FILE")"
  echo "check-usage: reading canned /usage output from '$CHECK_USAGE_INPUT_FILE' (not live)."
  status=0
else
  if ! command -v "$claude_bin" >/dev/null 2>&1; then
    echo "check-usage: 'claude' not found (looked for '$claude_bin'). Usage figures are unavailable."
    exit 127
  fi
  if [ -z "${CHECK_USAGE_CLI_VERSION:-}" ]; then
    CHECK_USAGE_CLI_VERSION="$("$claude_bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  fi
  export CHECK_USAGE_CLI_VERSION
  output="$("$claude_bin" -p "/usage" 2>&1)"
  status=$?
fi

if [ "$status" -ne 0 ]; then
  echo "check-usage: 'claude -p /usage' failed (exit $status). Usage figures are unavailable. Output was (first 20 lines):"
  printf '%s\n' "$output" | head -20
  exit 1
fi

if [ -z "$(printf '%s\n' "$output" | tr -d '[:space:]')" ]; then
  echo "check-usage: 'claude -p /usage' returned no output (exit 0). Usage figures are unavailable."
  echo "Likely causes: not signed in to a subscription in this environment, or /usage output format changed."
  exit 1
fi

matched="$(printf '%s\n' "$output" | grep -iE '^Current (session|week)|credit|extra usage|overage' || true)"

structured="$(printf '%s\n' "$output" | grep -iE '^Current (session|week)' || true)"

if [ -z "$structured" ]; then
  echo "check-usage: no session/week lines found in /usage output, so structured percentages are not available."
  if printf '%s\n' "$output" | grep -qE '^Total cost:'; then
    echo "check-usage: this is the per-session cost summary, which /usage prints when the CLI is not signed in to a"
    echo "subscription here (API-key billing, or an isolated config dir). There is no session/weekly quota to report."
  fi
  echo "Raw output follows:"
  printf '%s\n' "$output"
  exit 0
fi

printf '%s\n' "$matched"

# Best-effort plan/credits lines from Claude Code's local usage cache (refreshed by the
# /usage call above). Silent when python3, the cache, or a fresh same-account entry is missing.
enrich=""
if [ -z "${CHECK_USAGE_NO_CACHE:-}" ] && command -v "$python_bin" >/dev/null 2>&1 \
  && "$python_bin" -c '' >/dev/null 2>&1; then
  if [ -n "${CHECK_USAGE_CACHE_FILE:-}" ]; then
    cache_file="$CHECK_USAGE_CACHE_FILE"
  elif [ -z "${CHECK_USAGE_INPUT_FILE:-}" ]; then
    cache_file="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
  else
    cache_file=""
  fi
  if [ -n "$cache_file" ] && [ -f "$cache_file" ]; then
    enrich="$("$python_bin" "$script_dir/usage-cache.py" "$cache_file" 2>/dev/null || true)"
  fi
fi
if [ -n "$enrich" ]; then
  echo
  # "Credits state:" is an internal marker for the checks below; never shown.
  printf '%s\n' "$enrich" | grep -v '^Credits state:' || true
fi

# Percentages may be decimal (e.g. 99.5%). Thresholds use the integer part; messages
# print the original text.
session_pct="$(printf '%s\n' "$matched" | grep -m1 -i '^Current session' | grep -oE '[0-9]+(\.[0-9]+)?%' | head -1 | tr -d '%' || true)"
week_pct="$(printf '%s\n' "$matched" | grep -m1 -i '^Current week (all models)' | grep -oE '[0-9]+(\.[0-9]+)?%' | head -1 | tr -d '%' || true)"
session_int="${session_pct%%.*}"
week_int="${week_pct%%.*}"

if [ -n "${week_pct:-}" ] && [ -n "${session_pct:-}" ] && [ "$week_int" -ge 100 ] && [ "$session_int" -lt 100 ]; then
  echo
  echo "WARNING: weekly quota is exhausted (${week_pct}%) but the session limit still shows room (${session_pct}%)."
  echo "A healthy session percentage does not mean capacity is fine here — if requests are still succeeding,"
  echo "that overflow is either being billed as purchased usage credits (extra usage), or you're in a brief"
  echo "grace window before a hard stop. Run '/usage-credits' in an interactive session to confirm which."
  case "$enrich" in
    *"Credits state: local"*)
      echo "Credits check: an included credit may cover work past 100% before it stops (see the credit lines)."
      ;;
    *"Credits state: billed"*)
      echo "Credits check: usage credits are enabled, so work past 100% is being billed at API rates."
      ;;
    *"Credits state: stop"*)
      echo "Credits check: usage credits are unavailable (see the Usage credits line), so this is a hard stop, not a bill."
      ;;
  esac
elif [ -n "${week_pct:-}" ] && [ "$week_int" -ge 95 ] && [ "$week_int" -lt 100 ]; then
  echo
  echo "NOTICE: weekly quota is nearly exhausted (${week_pct}%). Once it reaches 100%, further requests either"
  echo "bill purchased usage credits (real money, if enabled) or stop. Flag this before continuing multi-step work,"
  echo "and prefer to pause at a step boundary rather than mid-step."
fi
