---
description: Pair mode (manager) — /pair on | off | update
---

Argument: $ARGUMENTS

If the argument is `on` (or empty):
- **Update check (best-effort, never block on it).** Run this once; it prints a line only when an update exists, and stays silent on any network error or if checked within the last 24h:
  ```bash
  CHK="$HOME/.claude-codex-pair/.last-update-check"
  if [ -z "$(find "$CHK" -mmin -1440 2>/dev/null)" ]; then
    touch "$CHK" 2>/dev/null
    REMOTE=$(curl -fsSL --max-time 3 https://raw.githubusercontent.com/kolirt/claude-codex-pair-skill/master/VERSION 2>/dev/null | head -n1 | tr -d '[:space:]')
    LOCAL=$(head -n1 "$HOME/.claude-codex-pair/VERSION" 2>/dev/null | tr -d '[:space:]')
    [ -n "$REMOTE" ] && [ "$REMOTE" != "$LOCAL" ] && \
      printf '🔄 Pair mode update available (%s → %s) — run /pair update\n' "${LOCAL:-?}" "$REMOTE"
  fi
  ```
  If it printed an update line, pass it on to the user verbatim; otherwise say nothing about updates.
- Read `~/.claude-codex-pair/MANAGER.md` and from now on act STRICTLY by it as the MANAGER until `/pair off`.
- Confirm: "Pair mode enabled — I am the manager."

If the argument is `update`:
- Reinstall the latest version: `curl -fsSL https://raw.githubusercontent.com/kolirt/claude-codex-pair-skill/master/install.sh | bash`.
- Read the new version and report it to the user: `head -n1 "$HOME/.claude-codex-pair/VERSION"` → "Pair mode updated to v<VERSION>."
- Tell the user: the protocol (`MANAGER.md` / `VERIFIER.md` / `verify.sh`) takes effect immediately; if the `/pair` command itself changed, reopen the session so the CLI reloads it.
- Re-read `~/.claude-codex-pair/MANAGER.md` now so the freshest protocol is active in this session (same as `/pair on`, but skip the update check).

If the argument is `off`:
- Stop acting under the pair-mode protocol; work solo.
- Confirm: "Pair mode disabled."
