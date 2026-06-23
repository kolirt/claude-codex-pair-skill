#!/usr/bin/env bash
set -euo pipefail

# Source of files: a local clone if present next to this script, otherwise
# fetched from GitHub raw — so `curl -fsSL .../install.sh | bash` works too.
SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
RAW="${PAIR_RAW_BASE:-https://raw.githubusercontent.com/kolirt/claude-codex-pair-skill/master}"

have_local(){ [ -n "$SRC" ] && [ -f "$SRC/verify.sh" ]; }

mkdir -p "$HOME/.claude-codex-pair" "$HOME/.claude/commands" "$HOME/.codex/skills/pair"

# fetch <relpath> -> stdout (local file if available, else GitHub raw)
fetch(){
  if have_local && [ -f "$SRC/$1" ]; then cat "$SRC/$1"
  else curl -fsSL "$RAW/$1"; fi
}

# Version comes from the VERSION file in the source (local clone or GitHub raw),
# so curl-piped installs record a real version too (not a "remote" placeholder).
# This is what the /pair update check compares against.
VER="$(fetch VERSION 2>/dev/null | head -n1 | tr -d '[:space:]' || true)"
[ -n "$VER" ] || VER="unknown"
STAMP="$VER"

put(){ # <relpath> <dst> <mode>
  local tmp; tmp="$(mktemp)"
  fetch "$1" > "$tmp" || { echo "fetch failed: $1" >&2; rm -f "$tmp"; exit 1; }
  [ -s "$tmp" ] || { echo "empty source: $1" >&2; rm -f "$tmp"; exit 1; }
  # Fail-closed backup with a UNIQUE name: if backup fails, do NOT overwrite the original.
  if [ -f "$2" ]; then
    cp -p "$2" "$2.bak.$STAMP.$(date +%Y%m%d%H%M%S).$$" \
      || { echo "backup failed for $2; aborting (original preserved)" >&2; rm -f "$tmp"; exit 1; }
  fi
  install -m "$3" "$tmp" "$2"
  rm -f "$tmp"
}

put verify.sh        "$HOME/.claude-codex-pair/verify.sh"          0755
put MANAGER.md       "$HOME/.claude-codex-pair/MANAGER.md"         0644
put VERIFIER.md      "$HOME/.claude-codex-pair/VERIFIER.md"        0644
put claude-skill/pair.md "$HOME/.claude/commands/pair.md"   0644
put codex-skill/SKILL.md "$HOME/.codex/skills/pair/SKILL.md" 0644
printf '%s\n' "$VER" > "$HOME/.claude-codex-pair/VERSION"
echo "pair-mode installed ($VER)."
