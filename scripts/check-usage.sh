#!/bin/bash
set -euo pipefail

output="$(claude -p "/usage" 2>&1)"
matched="$(echo "$output" | grep -E '^Current (session|week)' || true)"

if [ -n "$matched" ]; then
  echo "$matched"
else
  echo "$output"
fi
