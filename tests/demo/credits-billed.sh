#!/bin/bash
# Demo: canned /usage output with weekly exhausted and usage credits ON (used amount unknown).
# Used by eval case 08 and handy for trying the skill's interpretation rules by hand.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
export CHECK_USAGE_INPUT_FILE="$root/tests/fixtures/weekly-exhausted.txt"
export CHECK_USAGE_CACHE_FILE="$root/tests/fixtures/cache-credits-on-null.json"
export CHECK_USAGE_CACHE_MAX_AGE=999999999
export CHECK_USAGE_CLAUDE_BIN=/nonexistent
exec bash "$root/skills/check-usage/scripts/check-usage.sh"
