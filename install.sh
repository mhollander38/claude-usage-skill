#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO/skills/check-usage"
DEST="$HOME/.claude/skills/check-usage"

mkdir -p "$HOME/.claude/skills"

if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  echo "Error: $DEST exists and is not a symlink. Remove it manually first." >&2
  exit 1
fi

ln -sfn "$SRC" "$DEST"
echo "Linked $DEST -> $SRC"
