#!/usr/bin/env bash
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
STAMP="$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo manual)"
mkdir -p "$HOME/.pair" "$HOME/.claude/commands" "$HOME/.codex/prompts"

put(){ # <src> <dst> <mode>
  # Fail-closed backup with a UNIQUE name: if backup fails, do NOT overwrite the original.
  if [ -f "$2" ]; then
    cp -p "$2" "$2.bak.$STAMP.$(date +%Y%m%d%H%M%S).$$" \
      || { echo "backup failed for $2; aborting (original preserved)" >&2; exit 1; }
  fi
  install -m "$3" "$1" "$2"
}
put "$SRC/verify.sh"        "$HOME/.pair/verify.sh"          0755
put "$SRC/MANAGER.md"       "$HOME/.pair/MANAGER.md"         0644
put "$SRC/VERIFIER.md"      "$HOME/.pair/VERIFIER.md"        0644
put "$SRC/commands/pair.md" "$HOME/.claude/commands/pair.md" 0644
put "$SRC/prompts/pair.md"  "$HOME/.codex/prompts/pair.md"   0644
printf 'pair-mode %s\n' "$STAMP" > "$HOME/.pair/VERSION"
echo "pair-mode installed ($STAMP)."
