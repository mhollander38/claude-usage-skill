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
