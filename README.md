# claude-codex-pair-skill

A pairing mode for two CLI agents — **Claude Code** and **Codex** — in the roles of
**manager** and **verifier/consultant**.

The point is not a pass/fail gate but **collaboratively finding the best solution**:
the manager drives the task and, at decision forks, consults the second agent; finished
chunks go for an independent read-only review. Two different agents with different
strengths give two independent perspectives.

```
┌─────────────┐   request (CONSULT|REVIEW)   ┌──────────────────┐
│   MANAGER    │ ──────────────────────────▶ │    VERIFIER      │
│ (live CLI)  │                              │ (headless, RO)   │
│             │ ◀────────────────────────── │  codex / claude  │
└─────────────┘   verdict (stdout + exit)    └──────────────────┘
```

---

## How it works

- **One live terminal = the manager.** The CLI where you enabled pair mode.
- **The verifier** is never activated interactively — the manager spawns it as a
  headless subprocess on demand, waits for the verdict, and moves on.
- **Roles are interchangeable:** the manager can be Claude (then the verifier is
  Codex) or vice versa.
- Exchange happens through files in `~/.claude-codex-pair/handoff/<repo-key>/` (outside the repo)
  plus a CLI call.

### Two modes

| Mode | When | Verdict |
|------|------|---------|
| **CONSULT** | advice on the approach *before/during* a decision (a fork) | `STATUS: ADVICE` + Reasoning/Risks/Alternatives |
| **REVIEW** | checking a finished chunk | `STATUS: PASS` / `CHANGES_REQUESTED` + Findings |

### Read-only guarantee of the verifier

- **Codex:** a real `--sandbox read-only` — writes are blocked by the kernel.
- **Claude:** only the built-in `Read`/`Grep`/`Glob` tools (no Bash) — zero injection
  surface. The helper prepares the diff; Claude reads it.

> For critical changes, the more trustworthy verifier is **Codex** (a real sandbox).

---

## Requirements

- `bash`, `git`, `shasum` (standard on macOS/Linux)
- [Codex CLI](https://github.com/openai/codex) — `codex` on `PATH`
- [Claude Code](https://docs.claude.com/claude-code) — `claude` on `PATH`
- Both CLIs must be authenticated (`codex login`, Claude auth)

---

## Installation

One line (no clone needed):

```bash
curl -fsSL https://raw.githubusercontent.com/kolirt/claude-codex-pair-skill/master/install.sh | bash
```

Or from a clone:

```bash
git clone https://github.com/kolirt/claude-codex-pair-skill.git
bash claude-codex-pair-skill/install.sh
```

`install.sh` works either way — it uses local files when run from a clone, or fetches
them from GitHub raw when piped through `curl`. It lays files out **globally** (once per
machine; nothing lands in your working repos):

| Source | Destination |
|--------|-------------|
| `verify.sh`, `MANAGER.md`, `VERIFIER.md` | `~/.claude-codex-pair/` |
| `commands/pair.md` | `~/.claude/commands/pair.md` (Claude slash command) |
| `codex-skill/SKILL.md` | `~/.codex/skills/pair/SKILL.md` (Codex skill) |

Existing files are backed up with a unique name (`*.bak.<stamp>.<ts>.<pid>`,
fail-closed: if the backup fails, install does not overwrite the original).
The version is written to `~/.claude-codex-pair/VERSION`. Re-running `install.sh` is safe
(idempotent) and updates to the current version.

---

## Usage

Activation differs slightly per CLI (different extension mechanisms):

- **Claude Code** — a slash command:
  ```
  /pair on     # this terminal becomes the manager — consults + reviews
     ...work as usual...
  /pair off    # back to solo
  ```
- **Codex** — a skill (triggered by phrasing, since Codex has no custom slash commands).
  Just say **`pair on`** / **`enter pair mode`** to activate, and **`pair off`** to stop.

Either way, the terminal becomes the manager and the other agent is the headless verifier.

From there everything happens automatically: at forks the manager consults (CONSULT),
finished chunks go for review (REVIEW), it synthesizes the advice and reports to you.
If the manager disagrees with a verdict on solid grounds, it escalates to you rather
than silently accepting.

### Manual invocation (under the hood)

The manager composes a request file and runs:

```bash
~/.claude-codex-pair/verify.sh <your-cli: claude|codex> <effort: high|medium> <request-file>
```

The helper computes the paths itself, prepares the diff, calls the opposite agent,
returns the verdict on **stdout**, and exits with:

| Code | Meaning |
|------|---------|
| `0`  | `PASS` / `ADVICE` |
| `10` | `CHANGES_REQUESTED` (fix and repeat) |
| `20` | failed verification (missing/broken/stale verdict) — do NOT treat as verified |
| `64` | invocation/environment error (bad args, not a git repo) — not a verdict |

---

## Formats

### Request (`request-file`)

**REVIEW:**
```
MODE: review
TASK: <short description>
DECISION: <what the manager decided and why>
CHANGED:
- <file> — <what changed>
ACCEPTANCE:
- <criterion>
```

**CONSULT:**
```
MODE: consult
QUESTION: <a specific question>
CONTEXT: <concise context>
OPTIONS:            # options OR the literal "PROPOSE"
- A: <approach A + trade-offs>
- B: <approach B + trade-offs>
CRITERIA: <how to choose>
LEANING: <what the manager leans toward — so the consultant can challenge it>
```

`REQUEST_ID` (a nonce) is appended by `verify.sh` itself — no need to add it manually.

### Verdict (`stdout`)

**REVIEW:**
```
STATUS: PASS | CHANGES_REQUESTED
REQUEST_ID: <nonce>
SUMMARY: <one line>

## Findings
- [severity: blocker|major|minor] <locator> — <description>

## Notes
```

**CONSULT:**
```
STATUS: ADVICE
REQUEST_ID: <nonce>
RECOMMENDATION: <one line>

## Reasoning
## Risks
## Alternatives
```

---

## What makes it robust (engineering decisions)

- **Objective diff:** `git diff HEAD` (staged+unstaged) **plus** untracked
  (`ls-files --others` + `diff --no-index`), without mutating the index.
- **Stale-verdict protection:** a `REQUEST_ID` nonce in the request → the verifier
  must echo it in the verdict; write to `.tmp`, atomic move only on success;
  validation requires `REQUEST_ID` right after `STATUS`.
- **Round isolation:** all files of a round live in `run-<nonce>/` — concurrent calls
  never collide; stale run dirs are pruned (>1 day).
- **Preamble tolerance:** `codex -o` yields a clean verdict, while `claude -p` also
  prints reasoning — so the verdict block is taken from the LAST `STATUS:` line to EOF;
  stdout returns the clean block.
- **Collision-safe repo-key:** `sha256(repo-root)`, not character substitution.
- **Tiered effort:** `high` for significant/final work, `medium` for routine;
  `none`/`low` forbidden for anything that gates correctness.

---

## Tests

```bash
bash test/smoke.sh
```

30 smoke tests via a mock verifier (no live CLI calls): repo-key, tracked+untracked
diff, nonce, exit codes, MODE↔STATUS, stale/malformed/misplaced nonce, preamble
tolerance, install + backup.

The mock is active only when `PAIR_TEST_MODE=1` (otherwise `PAIR_VERIFIER_CMD` is
ignored — protection against an accidental mock in production).

---

## Cache & cleanup

Each verification round writes a small working set to
`~/.claude-codex-pair/handoff/<repo-key>/run-<nonce>/` (request, diff, prompt, verdict).
The diff can be sizable (the whole working-tree diff).

**Automatic:** on every `verify.sh` run, run dirs older than 1 day are pruned for that
repo (you don't call this — it runs at the start of each invocation):

```bash
find ~/.claude-codex-pair/handoff/<repo-key> -maxdepth 1 -name 'run-*' -type d -mtime +1 -exec rm -rf {} +
```

What automatic cleanup does **not** cover: handoff dirs of repos you stop using (they
linger, since the prune only runs when you invoke `verify.sh` in that repo again), and
`*.bak.*` backups left by repeated `install.sh` runs.

**Manual full cleanup** (safe — the handoff cache is transient and regenerated):

```bash
rm -rf ~/.claude-codex-pair/handoff/*
```

## Uninstall

```bash
rm -rf ~/.claude-codex-pair
rm -f ~/.claude/commands/pair.md
rm -rf ~/.codex/skills/pair
```

---

## Repository layout

```
verify.sh          # orchestrator helper (the heart of the mode)
MANAGER.md         # manager protocol
VERIFIER.md        # verifier/consultant protocol
commands/pair.md      # Claude Code slash command (/pair on|off)
codex-skill/SKILL.md  # Codex skill -> ~/.codex/skills/pair/ (say "pair on")
install.sh         # global install with backup
test/smoke.sh      # 30 smoke tests
```

---

## Limitations

- The protection assumes a good-faith manager (it catches *mistakes*, not an
  adversarial agent).
- `claude -p` as a verifier is read-only via tool restriction, not a physical sandbox;
  for critical code prefer the Codex verifier.
- `git diff HEAD` captures all working-tree changes; scoping the review is the
  manager's job via the `request`.
```
