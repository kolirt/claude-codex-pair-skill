#!/usr/bin/env bash
set -uo pipefail

MANAGER_CLI="${1:?usage: verify.sh <claude|codex> <high|medium> <request-file>}"
EFFORT="${2:?missing effort}"
REQUEST_FILE="${3:?missing request-file}"

case "$MANAGER_CLI" in claude) VERIFIER_CLI=codex;; codex) VERIFIER_CLI=claude;; *) echo "bad manager-cli" >&2; exit 64;; esac
case "$EFFORT" in high|medium) ;; *) echo "bad effort" >&2; exit 64;; esac
[ -f "$REQUEST_FILE" ] || { echo "no request file" >&2; exit 64; }

REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 64; }
KEY="$(printf '%s' "$REPO" | shasum -a 256 | cut -c1-16)"
HANDOFF="$HOME/.pair/handoff/$KEY"
mkdir -p "$HANDOFF"

# Remove stale run dirs (>1 day); never touches concurrent rounds.
find "$HANDOFF" -maxdepth 1 -name 'run-*' -type d -mtime +1 -exec rm -rf {} + 2>/dev/null || true

# Each round is isolated in its own run dir (no race on shared filenames).
REQUEST_ID="$(head -c16 /dev/urandom | xxd -p)"
RUN="$HANDOFF/run-$REQUEST_ID"
mkdir -p "$RUN"

# Objective diff: tracked (diff HEAD) + untracked, without mutating the index.
git -C "$REPO" --no-pager diff HEAD > "$RUN/diff.patch"
git -C "$REPO" ls-files --others --exclude-standard -z \
  | while IFS= read -r -d '' f; do
      git -C "$REPO" --no-pager diff --no-index -- /dev/null "$f" >> "$RUN/diff.patch" || true
    done

# Place request + nonce (guarantee a trailing newline before appending).
cp "$REQUEST_FILE" "$RUN/request.md"
[ -z "$(tail -c1 "$RUN/request.md")" ] || printf '\n' >> "$RUN/request.md"
printf 'REQUEST_ID: %s\n' "$REQUEST_ID" >> "$RUN/request.md"

# Build prompt with injected absolute paths.
PROMPT_FILE="$RUN/prompt.txt"
{ cat "$HOME/.pair/VERIFIER.md" 2>/dev/null || true
  cat "$RUN/request.md"
  printf 'DIFF_PATCH: %s\n' "$RUN/diff.patch"
  printf 'REPO_ROOT: %s\n' "$REPO"
} > "$PROMPT_FILE"

# Invoke verifier; Codex via -o (final message only), Claude/mock via stdout.
TMP="$RUN/verdict.md.tmp"
if [ "${PAIR_TEST_MODE:-}" = 1 ] && [ -n "${PAIR_VERIFIER_CMD:-}" ]; then
  echo "USING MOCK VERIFIER" >&2
  # PAIR_VERIFIER_CMD is a path to a mock script: <cmd> <prompt-file> <request-md>
  "$PAIR_VERIFIER_CMD" "$PROMPT_FILE" "$RUN/request.md" > "$TMP" 2>/dev/null; rc=$?
elif [ "$VERIFIER_CLI" = codex ]; then
  codex exec --sandbox read-only --skip-git-repo-check -C "$REPO" \
    -c model_reasoning_effort="$EFFORT" -o "$TMP" - < "$PROMPT_FILE" >/dev/null 2>&1; rc=$?
else
  ( cd "$REPO" && claude -p --effort "$EFFORT" --add-dir "$REPO" \
      --allowedTools "Read Grep Glob" < "$PROMPT_FILE" ) > "$TMP" 2>/dev/null; rc=$?
fi
{ [ "$rc" -eq 0 ] && [ -s "$TMP" ]; } && mv "$TMP" "$RUN/verdict.md"

# Validate verdict (MODE<->STATUS, nonce) + exit codes.
# Transport differs: codex -o emits only the final message, while claude -p
# also prints reasoning preamble. So the verdict block is taken from the LAST
# `^STATUS: ` line to EOF (the block is always at the end), but inside it the
# check is strict: REQUEST_ID must be the line right after STATUS.
MODE="$(grep -m1 '^MODE:' "$RUN/request.md" | awk '{print $2}')"
V="$RUN/verdict.md"
fail20(){ echo "FAILED: $1" >&2; exit 20; }
[ -s "$V" ] || fail20 "no verdict"
start="$(grep -n '^STATUS: ' "$V" | tail -1 | cut -d: -f1)"
[ -n "$start" ] || fail20 "no STATUS line"
BLOCK="$RUN/verdict.block.md"
sed -n "${start},\$p" "$V" > "$BLOCK"
first="$(sed -n 1p "$BLOCK")"
[ "$(sed -n 2p "$BLOCK")" = "REQUEST_ID: ${REQUEST_ID}" ] || fail20 "stale/misplaced/missing REQUEST_ID"

case "$MODE" in
  review)  case "$first" in "STATUS: PASS"|"STATUS: CHANGES_REQUESTED") ;; *) fail20 "STATUS!=MODE(review)";; esac;;
  consult) [ "$first" = "STATUS: ADVICE" ] || fail20 "STATUS!=MODE(consult)";;
  *) fail20 "unknown MODE";;
esac

cat "$BLOCK"   # stdout: clean verdict block only (no preamble)
case "$first" in
  "STATUS: PASS"|"STATUS: ADVICE") exit 0;;
  "STATUS: CHANGES_REQUESTED") exit 10;;
  *) fail20 "unreachable STATUS";;   # guard
esac
