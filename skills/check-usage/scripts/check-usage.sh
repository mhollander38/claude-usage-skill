#!/bin/bash
# Report Claude Code session/weekly usage against subscription limits.
#
# Environment:
#   CHECK_USAGE_INPUT_FILE  read /usage text from this file instead of calling claude (testing, canned output)
#   CHECK_USAGE_CLAUDE_BIN  claude binary to call (default: claude)
#   CHECK_USAGE_CACHE_FILE  Claude Code config JSON to read plan/credits from (default in live mode:
#                           ${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json; canned mode reads none unless set)
#   CHECK_USAGE_NO_CACHE    set to anything non-empty to skip the plan/credits lines
#   CHECK_USAGE_PYTHON      python interpreter for the plan/credits lines (default: python3; optional)
#
# Exit codes: 0 ok (or no structured lines found); 1 claude failed or returned nothing;
#             2 CHECK_USAGE_INPUT_FILE unreadable; 127 claude not found.
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
  output="$("$claude_bin" -p "/usage" 2>&1)"
  status=$?
fi

if [ "$status" -ne 0 ]; then
  echo "check-usage: 'claude -p /usage' failed (exit $status). Usage figures are unavailable. Output was (first 20 lines):"
  echo "$output" | head -20
  exit 1
fi

if [ -z "$(echo "$output" | tr -d '[:space:]')" ]; then
  echo "check-usage: 'claude -p /usage' returned no output (exit 0). Usage figures are unavailable."
  echo "Likely causes: not signed in to a subscription in this environment, or /usage output format changed."
  exit 1
fi

matched="$(echo "$output" | grep -iE '^Current (session|week)|credit|extra usage|overage' || true)"

structured="$(echo "$output" | grep -iE '^Current (session|week)' || true)"

if [ -z "$structured" ]; then
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

# Best-effort plan/credits lines from Claude Code's local usage cache (refreshed by the
# /usage call above). Silent when python3, the cache, or a fresh same-account entry is missing.
enrich=""
if [ -z "${CHECK_USAGE_NO_CACHE:-}" ] && command -v "$python_bin" >/dev/null 2>&1; then
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
  echo "$enrich"
fi

session_pct="$(echo "$matched" | grep -m1 -i '^Current session' | grep -oE '[0-9]+%' | head -1 | tr -d '%' || true)"
week_pct="$(echo "$matched" | grep -m1 -i '^Current week (all models)' | grep -oE '[0-9]+%' | head -1 | tr -d '%' || true)"

if [ -n "${week_pct:-}" ] && [ -n "${session_pct:-}" ] && [ "$week_pct" -ge 100 ] && [ "$session_pct" -lt 100 ]; then
  echo
  echo "WARNING: weekly quota is exhausted (${week_pct}%) but the session limit still shows room (${session_pct}%)."
  echo "A healthy session percentage does not mean capacity is fine here — if requests are still succeeding,"
  echo "that overflow is either being billed as purchased usage credits (extra usage), or you're in a brief"
  echo "grace window before a hard stop. Run '/usage-credits' in an interactive session to confirm which."
  if echo "$enrich" | grep -q '^Usage credits: ON ·'; then
    echo "Credits check: usage credits are enabled, so work past 100% is being billed at API rates."
  elif echo "$enrich" | grep -q '^Usage credits:'; then
    echo "Credits check: usage credits are unavailable (see the Usage credits line), so this is a hard stop, not a bill."
  fi
elif [ -n "${week_pct:-}" ] && [ "$week_pct" -ge 95 ] && [ "$week_pct" -lt 100 ]; then
  echo
  echo "NOTICE: weekly quota is nearly exhausted (${week_pct}%). Once it reaches 100%, further requests either"
  echo "bill purchased usage credits (real money, if enabled) or stop. Flag this before continuing multi-step work,"
  echo "and prefer to pause at a step boundary rather than mid-step."
fi
