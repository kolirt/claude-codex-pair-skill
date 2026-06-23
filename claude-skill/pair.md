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
    if [ -n "$REMOTE" ] && [ "$REMOTE" != "$LOCAL" ]; then
      printf '🔄 Pair mode update available (%s → %s) — run /pair update\n' "${LOCAL:-?}" "$REMOTE"
    fi
  fi
  : # never let the best-effort check fail the activation
  ```
  If it printed an update line, pass it on to the user verbatim; otherwise say nothing about updates.
- Read `~/.claude-codex-pair/MANAGER.md` and from now on act STRICTLY by it as the MANAGER until `/pair off`.
- Confirm: "Pair mode enabled — I am the manager."

If the argument is `update`:
- **Step 1 — prefer a local clone (no network, no hooks).** If this session is inside a clone of the pair-mode repo, install straight from it. Run:
  ```bash
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$ROOT" ] && [ -f "$ROOT/install.sh" ] && [ -f "$ROOT/verify.sh" ] \
     && [ -f "$ROOT/MANAGER.md" ] && grep -q claude-codex-pair "$ROOT/install.sh"; then
    bash "$ROOT/install.sh"
  else
    echo "PAIR_NO_LOCAL_CLONE"
  fi
  ```
  If it printed `pair-mode installed (...)`, the update is done — skip Step 2.
- **Step 2 — otherwise, have the USER run the installer (do NOT run `curl … | bash` yourself).** Some environments block Claude from downloading and executing a remote script (e.g. the context-mode plugin intercepts `curl`/`wget`; restrictive permission/auto modes deny fetch-and-execute). The `!` prefix runs the command in the user's own shell, bypassing tool hooks and auto-mode. Ask the user to paste this line into the prompt verbatim:
  ```
  ! curl -fsSL https://raw.githubusercontent.com/kolirt/claude-codex-pair-skill/master/install.sh | bash
  ```
  Wait until they confirm it ran (look for `pair-mode installed (...)`) before continuing.
- Read the new version and report it: `head -n1 "$HOME/.claude-codex-pair/VERSION"` → "Pair mode updated to v<VERSION>."
- Tell the user: the protocol (`MANAGER.md` / `VERIFIER.md` / `verify.sh`) takes effect immediately; if the `/pair` command itself changed, reopen the session so the CLI reloads it.
- Re-read `~/.claude-codex-pair/MANAGER.md` now so the freshest protocol is active in this session (same as `/pair on`, but skip the update check).

If the argument is `off`:
- Stop acting under the pair-mode protocol; work solo.
- Confirm: "Pair mode disabled."
