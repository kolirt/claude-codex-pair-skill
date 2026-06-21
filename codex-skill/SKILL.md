---
name: pair
description: Use when the user wants to enable pair mode and act as the MANAGER paired with the other agent as a read-only verifier/consultant. Triggers on requests like "pair on", "enter pair mode", "be the manager", or asking to consult/review a decision with the paired agent. Also handles "pair update" to upgrade the installed pair-mode files. Deactivate when the user says "pair off".
---

# Pair mode (manager)

When this skill is active, act as the MANAGER per the installed protocol.

If the user says `pair update`: reinstall the latest version with
`curl -fsSL https://raw.githubusercontent.com/kolirt/claude-codex-pair-skill/master/install.sh | bash`,
then report the new version (`head -n1 ~/.claude-codex-pair/VERSION`). The protocol files take effect
immediately; if this skill file itself changed, reopen the session so Codex reloads it. Then continue as MANAGER.

0. **Update check (best-effort, never block on it).** Run once at activation; prints a line only when an update exists, silent on network error or if checked within 24h. If it prints, pass it to the user verbatim:
   ```bash
   CHK="$HOME/.claude-codex-pair/.last-update-check"
   if [ -z "$(find "$CHK" -mmin -1440 2>/dev/null)" ]; then
     touch "$CHK" 2>/dev/null
     REMOTE=$(curl -fsSL --max-time 3 https://raw.githubusercontent.com/kolirt/claude-codex-pair-skill/master/VERSION 2>/dev/null | head -n1 | tr -d '[:space:]')
     LOCAL=$(head -n1 "$HOME/.claude-codex-pair/VERSION" 2>/dev/null | tr -d '[:space:]')
     [ -n "$REMOTE" ] && [ "$REMOTE" != "$LOCAL" ] && \
       printf '🔄 Pair mode update available (%s → %s) — run: pair update\n' "${LOCAL:-?}" "$REMOTE"
   fi
   ```
1. Read `~/.claude-codex-pair/MANAGER.md` and follow it strictly as the MANAGER until the user says `pair off`.
2. In short: at decision forks consult the verifier (CONSULT); send finished chunks for review (REVIEW). Compose a request file and run
   `~/.claude-codex-pair/verify.sh <your-cli: claude|codex> <effort: high|medium> <request-file>`, then read its stdout (the verdict) and exit code (`0` PASS/ADVICE, `10` CHANGES_REQUESTED, `20` failed, `64` invocation error).
3. Superpowers workflow gates: REVIEW the spec (after `brainstorming`), the plan (after `writing-plans`), and each task + the final result (during execution) through the verifier before advancing — do not pass a gate while it sits at CHANGES_REQUESTED.
4. Synthesis, not obedience; escalate to the user on reasoned disagreement.

To stop: when the user says `pair off`, stop acting under this protocol and work solo.
