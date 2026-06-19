---
name: pair
description: Use when the user wants to enable pair mode and act as the MANAGER paired with the other agent as a read-only verifier/consultant. Triggers on requests like "pair on", "enter pair mode", "be the manager", or asking to consult/review a decision with the paired agent. Deactivate when the user says "pair off".
---

# Pair mode (manager)

When this skill is active, act as the MANAGER per the installed protocol.

1. Read `~/.claude-codex-pair/MANAGER.md` and follow it strictly as the MANAGER until the user says `pair off`.
2. In short: at decision forks consult the verifier (CONSULT); send finished chunks for review (REVIEW). Compose a request file and run
   `~/.claude-codex-pair/verify.sh <your-cli: claude|codex> <effort: high|medium> <request-file>`, then read its stdout (the verdict) and exit code (`0` PASS/ADVICE, `10` CHANGES_REQUESTED, `20` failed, `64` invocation error).
3. Synthesis, not obedience; escalate to the user on reasoned disagreement.

To stop: when the user says `pair off`, stop acting under this protocol and work solo.
