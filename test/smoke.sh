#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
VERIFY="$HERE/../verify.sh"
fail=0
t(){ if eval "$2"; then echo "ok - $1"; else echo "NOT ok - $1"; fail=1; fi; }

SCRATCH="$(mktemp -d)" || { echo "FATAL: mktemp -d failed" >&2; exit 1; }
[ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] || { echo "FATAL: no scratch dir — aborting (would touch real repo)" >&2; exit 1; }
trap 'rm -rf "$SCRATCH"' EXIT
git -C "$SCRATCH" init -q
git -C "$SCRATCH" config user.email t@t; git -C "$SCRATCH" config user.name t
echo base > "$SCRATCH/a.txt"; git -C "$SCRATCH" add a.txt; git -C "$SCRATCH" commit -qm init

export PAIR_TEST_MODE=1
# Mock verifier: emits a verdict per PAIR_MOCK_STATUS, copies REQUEST_ID (or PAIR_MOCK_NONCE).
MOCK="$SCRATCH/mock.sh"
cat > "$MOCK" <<'MOCKEOF'
#!/usr/bin/env bash
# args: $1=prompt-file $2=request-md
rid=$(grep -m1 '^REQUEST_ID:' "$2")
[ -n "${PAIR_MOCK_NONCE:-}" ] && rid="REQUEST_ID: $PAIR_MOCK_NONCE"
case "${PAIR_MOCK_STATUS:-PASS}" in
  GARBAGE)   printf 'garbage\n';;
  PREAMBLE)  printf 'analyzing file...\nmore reasoning\n\nSTATUS: PASS\n%s\nSUMMARY: m\n' "$rid";;  # preamble like claude -p
  MISPLACED) printf 'STATUS: PASS\nSUMMARY: m\n%s\n' "$rid";;  # nonce on line 3
  ADVICE)    printf 'STATUS: ADVICE\n%s\nRECOMMENDATION: m\n' "$rid";;
  CR)        printf 'STATUS: CHANGES_REQUESTED\n%s\nSUMMARY: m\n' "$rid";;
  AUDIT)     printf 'STATUS: AUDIT_COMPLETE\n%s\nSUMMARY: m\n' "$rid";;
  *)         printf 'STATUS: PASS\n%s\nSUMMARY: m\n' "$rid";;
esac
MOCKEOF
chmod +x "$MOCK"
export PAIR_VERIFIER_CMD="$MOCK"
REQ="$SCRATCH/req.txt"; printf 'MODE: review\nTASK: x\n' > "$REQ"
( cd "$SCRATCH" && HOME="$SCRATCH/home" "$VERIFY" claude medium "$REQ" >/dev/null 2>&1 )
# Compute KEY the same way verify.sh does (git rev-parse canonicalizes path on macOS).
KEY=$(cd "$SCRATCH" && printf '%s' "$(git rev-parse --show-toplevel)" | shasum -a 256 | cut -c1-16)
HPATH="$SCRATCH/home/.claude-codex-pair/handoff/$KEY"
latest_run(){ ls -td "$HPATH"/run-*/ 2>/dev/null | head -1; }
t "handoff created under repo-key" '[ -d "$HPATH" ]'

# --- diff (tracked + untracked) ---
echo modified >> "$SCRATCH/a.txt"
echo newfile > "$SCRATCH/new.txt"
REQ2="$SCRATCH/req2.txt"; printf 'MODE: review\nTASK: y\n' > "$REQ2"
( cd "$SCRATCH" && HOME="$SCRATCH/home" "$VERIFY" claude medium "$REQ2" >/dev/null 2>&1 )
PATCH="$(latest_run)diff.patch"
t "diff includes tracked change" 'grep -q "modified" "$PATCH"'
t "diff includes untracked file" 'grep -q "new.txt" "$PATCH"'

# --- nonce in request.md ---
REQ3="$SCRATCH/req3.txt"; printf 'MODE: review\nTASK: z\n' > "$REQ3"
( cd "$SCRATCH" && HOME="$SCRATCH/home" "$VERIFY" claude medium "$REQ3" >/dev/null 2>&1 )
RM="$(latest_run)request.md"
t "request.md has REQUEST_ID" 'grep -qE "^REQUEST_ID: .+" "$RM"'

# --- verifier invocation via mock + path injection ---
REQ4="$SCRATCH/req4.txt"; printf 'MODE: review\nTASK: w\n' > "$REQ4"
( cd "$SCRATCH" && HOME="$SCRATCH/home" "$VERIFY" claude medium "$REQ4" >/dev/null 2>&1 )
HD="$(latest_run)"
t "verdict written" '[ -s "${HD}verdict.md" ]'
t "verdict echoes REQUEST_ID" 'grep -q "$(grep -m1 ^REQUEST_ID: "${HD}request.md" | cut -d" " -f2)" "${HD}verdict.md"'
t "prompt injects DIFF_PATCH" 'grep -q "^DIFF_PATCH: " "${HD}prompt.txt"'
t "prompt injects REPO_ROOT" 'grep -q "^REPO_ROOT: " "${HD}prompt.txt"'

# --- validation: MODE<->STATUS, nonce, exit codes ---
runrc(){ ( cd "$SCRATCH" && HOME="$SCRATCH/home" "$VERIFY" claude medium "$1" >/dev/null 2>&1 ); echo $?; }
REQC="$SCRATCH/reqc.txt"; printf 'MODE: consult\nQUESTION: q\nOPTIONS: PROPOSE\n' > "$REQC"

PAIR_MOCK_STATUS=PASS  PAIR_MOCK_NONCE= ; export PAIR_MOCK_STATUS PAIR_MOCK_NONCE
t "review PASS exit 0" '[ "$(runrc "$REQ4")" -eq 0 ]'
PAIR_MOCK_STATUS=CR ; export PAIR_MOCK_STATUS
t "review CR exit 10" '[ "$(runrc "$REQ4")" -eq 10 ]'
PAIR_MOCK_STATUS=ADVICE ; export PAIR_MOCK_STATUS
t "review/ADVICE mismatch exit 20" '[ "$(runrc "$REQ4")" -eq 20 ]'
PAIR_MOCK_STATUS=ADVICE ; export PAIR_MOCK_STATUS
t "consult ADVICE exit 0" '[ "$(runrc "$REQC")" -eq 0 ]'
PAIR_MOCK_STATUS=PASS PAIR_MOCK_NONCE=WRONG ; export PAIR_MOCK_STATUS PAIR_MOCK_NONCE
t "stale exit 20" '[ "$(runrc "$REQ4")" -eq 20 ]'
PAIR_MOCK_NONCE= ; export PAIR_MOCK_NONCE
PAIR_MOCK_STATUS=GARBAGE ; export PAIR_MOCK_STATUS
t "malformed exit 20" '[ "$(runrc "$REQ4")" -eq 20 ]'
PAIR_MOCK_STATUS=MISPLACED ; export PAIR_MOCK_STATUS
t "misplaced nonce exit 20" '[ "$(runrc "$REQ4")" -eq 20 ]'
# preamble before the verdict block (like claude -p) must be tolerated
PAIR_MOCK_STATUS=PREAMBLE ; export PAIR_MOCK_STATUS
t "preamble before verdict exit 0" '[ "$(runrc "$REQ4")" -eq 0 ]'
preout=$( cd "$SCRATCH" && HOME="$SCRATCH/home" "$VERIFY" claude medium "$REQ4" 2>/dev/null )
t "stdout starts with STATUS (clean block)" 'printf "%s" "$preout" | head -n1 | grep -q "^STATUS: PASS"'
PAIR_MOCK_STATUS=PASS ; export PAIR_MOCK_STATUS
# request WITHOUT trailing newline: nonce must remain a standalone line
REQNL="$SCRATCH/reqnl.txt"; printf 'MODE: review\nTASK: nonl' > "$REQNL"
t "request without trailing newline still validates" '[ "$(runrc "$REQNL")" -eq 0 ]'
t "nonce stays standalone line (not glued)" 'grep -qE "^REQUEST_ID: [0-9a-f]+$" "$(latest_run)request.md"'

# --- audit mode (scope-centric, no diff) ---
REQA="$SCRATCH/reqa.txt"; printf 'MODE: audit\nSCOPE: a.txt\nFOCUS: all\n' > "$REQA"
PAIR_MOCK_STATUS=AUDIT PAIR_MOCK_NONCE= ; export PAIR_MOCK_STATUS PAIR_MOCK_NONCE
t "audit AUDIT_COMPLETE exit 0" '[ "$(runrc "$REQA")" -eq 0 ]'
t "audit prompt omits DIFF_PATCH" '! grep -q "^DIFF_PATCH: " "$(latest_run)prompt.txt"'
t "audit prompt injects REPO_ROOT" 'grep -q "^REPO_ROOT: " "$(latest_run)prompt.txt"'
t "audit writes no diff.patch" '[ ! -f "$(latest_run)diff.patch" ]'
PAIR_MOCK_STATUS=PASS ; export PAIR_MOCK_STATUS
t "audit/PASS mismatch exit 20" '[ "$(runrc "$REQA")" -eq 20 ]'
PAIR_MOCK_STATUS=AUDIT PAIR_MOCK_NONCE=WRONG ; export PAIR_MOCK_STATUS PAIR_MOCK_NONCE
t "audit stale nonce exit 20" '[ "$(runrc "$REQA")" -eq 20 ]'
PAIR_MOCK_NONCE= ; export PAIR_MOCK_NONCE
REQAN="$SCRATCH/reqan.txt"; printf 'MODE: audit\nFOCUS: all\n' > "$REQAN"
PAIR_MOCK_STATUS=AUDIT ; export PAIR_MOCK_STATUS
t "audit without SCOPE exit 64" '[ "$(runrc "$REQAN")" -eq 64 ]'
PAIR_MOCK_STATUS=PASS PAIR_MOCK_NONCE= ; export PAIR_MOCK_STATUS PAIR_MOCK_NONCE

# --- install.sh ---
HOME2="$SCRATCH/home2"; mkdir -p "$HOME2"
HOME="$HOME2" bash "$HERE/../install.sh" >/dev/null 2>&1
t "verify.sh installed exec" '[ -x "$HOME2/.claude-codex-pair/verify.sh" ]'
t "MANAGER installed" '[ -f "$HOME2/.claude-codex-pair/MANAGER.md" ]'
t "VERIFIER installed" '[ -f "$HOME2/.claude-codex-pair/VERIFIER.md" ]'
t "claude cmd installed" '[ -f "$HOME2/.claude/commands/pair.md" ]'
t "codex skill installed" '[ -f "$HOME2/.codex/skills/pair/SKILL.md" ]'
t "version marker" '[ -f "$HOME2/.claude-codex-pair/VERSION" ]'
t "version marker is real semver (from VERSION file)" 'grep -qE "^[0-9]+\.[0-9]+\.[0-9]+$" "$HOME2/.claude-codex-pair/VERSION"'
t "installed version matches repo VERSION" '[ "$(head -n1 "$HOME2/.claude-codex-pair/VERSION")" = "$(head -n1 "$HERE/../VERSION")" ]'
printf 'USER_ORIGINAL\n' > "$HOME2/.claude-codex-pair/MANAGER.md"
HOME="$HOME2" bash "$HERE/../install.sh" >/dev/null 2>&1
t "backup created on reinstall" 'ls "$HOME2/.claude-codex-pair/"MANAGER.md.bak.* >/dev/null 2>&1'
t "backup preserves original content" 'grep -rqx USER_ORIGINAL "$HOME2/.claude-codex-pair/"MANAGER.md.bak.*'
HOME="$HOME2" bash "$HERE/../install.sh" >/dev/null 2>&1
t "original backup still present after 2nd reinstall" 'grep -rqx USER_ORIGINAL "$HOME2/.claude-codex-pair/"MANAGER.md.bak.*'

# --- e2e via installed verify.sh ---
HOME="$HOME2" bash "$HERE/../install.sh" >/dev/null 2>&1
PAIR_MOCK_STATUS=PASS PAIR_MOCK_NONCE= ; export PAIR_MOCK_STATUS PAIR_MOCK_NONCE
out=$( cd "$SCRATCH" && HOME="$HOME2" "$HOME2/.claude-codex-pair/verify.sh" claude high "$REQ4" ); rc=$?
t "e2e exit 0" '[ "$rc" -eq 0 ]'
t "e2e stdout STATUS" 'printf "%s" "$out" | grep -q "^STATUS: PASS"'

exit $fail
