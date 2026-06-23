# `diagnose` Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fourth verifier mode `diagnose` (independent, symmetric root-cause analysis of known symptoms) to the pair-mode skill.

**Architecture:** `diagnose` reuses the scope-centric, no-diff transport of `audit` in `verify.sh`, but is a distinct mode: it requires a `SYMPTOMS` field, has terminal `STATUS: DIAGNOSIS_COMPLETE` (exit 0), and is non-gating. The verifier protocol (`VERIFIER.md`) gains a `MODE: diagnose` block; the manager protocol (`MANAGER.md`) gains a symmetric two-pass DIAGNOSE workflow and anti-conflict rules vs `audit`.

**Tech Stack:** Bash (`verify.sh`), the `test/smoke.sh` harness with its mock verifier (`PAIR_TEST_MODE`/`PAIR_VERIFIER_CMD`), Markdown protocol docs.

**Spec:** `docs/superpowers/specs/2026-06-23-diagnose-mode-design.md` (PASS at spec gate).

## Global Constraints

- **No commits during execution.** User's global rule overrides the skill's "frequent commits": omit every commit step. The working tree accumulates all changes until the user explicitly says to commit. Plan/spec/doc artifacts stay in the tree and are committed together with the implementation when the user asks.
- Terminal status string is exactly `STATUS: DIAGNOSIS_COMPLETE`; verify.sh maps it to exit `0`.
- `diagnose` requires non-empty `SCOPE:` AND non-empty `SYMPTOMS:` lines; a missing either → exit `64`.
- `diagnose` is no-diff (no `DIFF_PATCH`, no `diff.patch`), like `audit`.
- VERSION bump: `1.1.1` → `1.2.0`.
- Run real diagnoses at `high` effort (manager protocol).
- Fix-constraints allowed in a diagnosis; fix-choice forbidden (that stays `consult`).

## File Structure

- `verify.sh` — transport: extend the scope-centric/no-diff branch to `audit|diagnose`, add `SYMPTOMS` validation, add STATUS↔MODE validation and exit-0 mapping for `diagnose`.
- `test/smoke.sh` — add a `DIAGNOSE` case to the mock verifier and a `diagnose` test block.
- `VERIFIER.md` — add the `## MODE: diagnose` block; update the Common diff/scope line to cover `audit`/`diagnose`.
- `MANAGER.md` — mode-selection row, anti-conflict rules, `## DIAGNOSE` two-pass section, invoke bullet, exit-code line.
- `README.md` — document the mode in all six places that enumerate modes (diagram, modes table+heading, read-only line, manual-invocation diff line, exit-code table, request/verdict format sections, cache-cleanup line).
- `VERSION` — bump to `1.2.0`.

---

### Task 1: verify.sh transport for `diagnose` (TDD via smoke harness)

**Files:**
- Modify: `test/smoke.sh` (mock verifier `case` ~line 23-31; new test block after the audit block ~line 112)
- Modify: `verify.sh` (no-diff branch lines 28-39; prompt DIFF_PATCH line 50; validation `case` lines 84-89; exit `case` lines 92-96)

**Interfaces:**
- Consumes: existing `verify.sh` request format (`MODE:`, `SCOPE:`, `REQUEST_ID:`), the mock verifier contract `<cmd> <prompt-file> <request-md>`.
- Produces: `MODE: diagnose` accepting `SCOPE` + `SYMPTOMS`, emitting/validating `STATUS: DIAGNOSIS_COMPLETE` → exit 0; missing SCOPE or SYMPTOMS → exit 64; STATUS≠mode → exit 20.

- [ ] **Step 1: Add the `DIAGNOSE` arm to the mock verifier in `test/smoke.sh`**

In the mock `case "${PAIR_MOCK_STATUS:-PASS}"` block (currently ending with the `AUDIT)` arm), add a `DIAGNOSE)` arm right after `AUDIT)`:

```bash
  AUDIT)     printf 'STATUS: AUDIT_COMPLETE\n%s\nSUMMARY: m\n' "$rid";;
  DIAGNOSE)  printf 'STATUS: DIAGNOSIS_COMPLETE\n%s\nSUMMARY: m\n' "$rid";;
```

- [ ] **Step 2: Add the `diagnose` test block to `test/smoke.sh`**

Insert directly after the audit block (after the line `PAIR_MOCK_STATUS=PASS PAIR_MOCK_NONCE= ; export PAIR_MOCK_STATUS PAIR_MOCK_NONCE` that closes the audit section, before `# --- install.sh ---`):

```bash
# --- diagnose mode (scope-centric + symptoms, no diff) ---
REQD="$SCRATCH/reqd.txt"; printf 'MODE: diagnose\nSCOPE: a.txt\nSYMPTOMS: breaks on click\n' > "$REQD"
PAIR_MOCK_STATUS=DIAGNOSE PAIR_MOCK_NONCE= ; export PAIR_MOCK_STATUS PAIR_MOCK_NONCE
t "diagnose DIAGNOSIS_COMPLETE exit 0" '[ "$(runrc "$REQD")" -eq 0 ]'
t "diagnose prompt omits DIFF_PATCH" '! grep -q "^DIFF_PATCH: " "$(latest_run)prompt.txt"'
t "diagnose prompt injects REPO_ROOT" 'grep -q "^REPO_ROOT: " "$(latest_run)prompt.txt"'
t "diagnose writes no diff.patch" '[ ! -f "$(latest_run)diff.patch" ]'
PAIR_MOCK_STATUS=PASS ; export PAIR_MOCK_STATUS
t "diagnose/PASS mismatch exit 20" '[ "$(runrc "$REQD")" -eq 20 ]'
PAIR_MOCK_STATUS=DIAGNOSE PAIR_MOCK_NONCE=WRONG ; export PAIR_MOCK_STATUS PAIR_MOCK_NONCE
t "diagnose stale nonce exit 20" '[ "$(runrc "$REQD")" -eq 20 ]'
PAIR_MOCK_NONCE= ; export PAIR_MOCK_NONCE
PAIR_MOCK_STATUS=DIAGNOSE ; export PAIR_MOCK_STATUS
REQDS="$SCRATCH/reqds.txt"; printf 'MODE: diagnose\nSYMPTOMS: x\n' > "$REQDS"
t "diagnose without SCOPE exit 64" '[ "$(runrc "$REQDS")" -eq 64 ]'
REQDN="$SCRATCH/reqdn.txt"; printf 'MODE: diagnose\nSCOPE: a.txt\n' > "$REQDN"
t "diagnose without SYMPTOMS exit 64" '[ "$(runrc "$REQDN")" -eq 64 ]'
PAIR_MOCK_STATUS=PASS PAIR_MOCK_NONCE= ; export PAIR_MOCK_STATUS PAIR_MOCK_NONCE
```

- [ ] **Step 3: Run the smoke suite to verify the new diagnose tests FAIL**

Run: `bash test/smoke.sh`
Expected: existing tests still `ok`; new lines fail — notably `NOT ok - diagnose DIAGNOSIS_COMPLETE exit 0` (current verify.sh hits `*) fail20 "unknown MODE"` → exit 20, not 0) and `NOT ok - diagnose without SYMPTOMS exit 64`. Overall exit code non-zero.

- [ ] **Step 4: Extend the no-diff branch in `verify.sh` to `audit|diagnose` + SYMPTOMS check**

Replace the `if [ "$MODE" = audit ]; then ... else ... fi` block (lines 28-39) with:

```bash
case "$MODE" in
  audit|diagnose)
    # Scope-centric modes inspect existing code over a declared SCOPE; a diff is not relevant.
    grep -qE '^SCOPE:[[:space:]]*[^[:space:]]' "$REQUEST_FILE" \
      || { echo "$MODE mode requires a non-empty SCOPE: line" >&2; exit 64; }
    # diagnose additionally needs the observed symptoms to investigate.
    if [ "$MODE" = diagnose ]; then
      grep -qE '^SYMPTOMS:[[:space:]]*[^[:space:]]' "$REQUEST_FILE" \
        || { echo "diagnose mode requires a non-empty SYMPTOMS: line" >&2; exit 64; }
    fi
    ;;
  *)
    # Objective diff: tracked (diff HEAD) + untracked, without mutating the index.
    git -C "$REPO" --no-pager diff HEAD > "$RUN/diff.patch"
    git -C "$REPO" ls-files --others --exclude-standard -z \
      | while IFS= read -r -d '' f; do
          git -C "$REPO" --no-pager diff --no-index -- /dev/null "$f" >> "$RUN/diff.patch" || true
        done
    ;;
esac
```

- [ ] **Step 5: Omit `DIFF_PATCH` for `diagnose` too in the prompt build**

Replace line 50 (`  [ "$MODE" = audit ] || printf 'DIFF_PATCH: %s\n' "$RUN/diff.patch"`) with:

```bash
  case "$MODE" in audit|diagnose) ;; *) printf 'DIFF_PATCH: %s\n' "$RUN/diff.patch";; esac
```

- [ ] **Step 6: Add the `diagnose` STATUS↔MODE validation case in `verify.sh`**

In the validation `case "$MODE" in ... esac` (lines 84-89), add the `diagnose` arm after the `audit)` arm:

```bash
  audit)   [ "$first" = "STATUS: AUDIT_COMPLETE" ] || fail20 "STATUS!=MODE(audit)";;
  diagnose) [ "$first" = "STATUS: DIAGNOSIS_COMPLETE" ] || fail20 "STATUS!=MODE(diagnose)";;
  *) fail20 "unknown MODE";;
```

- [ ] **Step 7: Map `DIAGNOSIS_COMPLETE` to exit 0 in `verify.sh`**

In the final exit `case "$first" in ... esac` (lines 92-96), add `DIAGNOSIS_COMPLETE` to the exit-0 alternation:

```bash
case "$first" in
  "STATUS: PASS"|"STATUS: ADVICE"|"STATUS: AUDIT_COMPLETE"|"STATUS: DIAGNOSIS_COMPLETE") exit 0;;
  "STATUS: CHANGES_REQUESTED") exit 10;;
  *) fail20 "unreachable STATUS";;   # guard
esac
```

- [ ] **Step 8: Run the smoke suite to verify ALL tests pass**

Run: `bash test/smoke.sh`
Expected: every line `ok - ...`, including all `diagnose ...` tests; process exit code `0`.

---

### Task 2: `VERIFIER.md` — `MODE: diagnose` block

**Files:**
- Modify: `VERIFIER.md` (Common section line 7; add a new `## MODE: diagnose` block after the `## MODE: audit` block)

**Interfaces:**
- Consumes: the request fields `SCOPE`/`SYMPTOMS` placed by `verify.sh`, the `REQUEST_ID` nonce contract (STATUS first line, REQUEST_ID second line).
- Produces: the `STATUS: DIAGNOSIS_COMPLETE` verdict shape that `verify.sh` Task 1 validates.

- [ ] **Step 1: Update the Common diff/scope line to cover `diagnose`**

In `VERIFIER.md` line 7, change the audit clause so both scope-centric modes are covered. Replace:

```
- For `review`/`consult`: read the diff at the absolute path from the `DIFF_PATCH:` line in the prompt. For `audit`: there is no `DIFF_PATCH`; inspect the files named by the `SCOPE:` line of the request, under `REPO_ROOT:`.
```

with:

```
- For `review`/`consult`: read the diff at the absolute path from the `DIFF_PATCH:` line in the prompt. For `audit`/`diagnose`: there is no `DIFF_PATCH`; inspect the files named by the `SCOPE:` line of the request, under `REPO_ROOT:`.
```

- [ ] **Step 2: Add the `## MODE: diagnose` block after the `## MODE: audit` block**

Append immediately after the audit block (after the `Locator: ... Empty Findings is valid ...` line for audit) and before `## MODE: consult`:

```markdown
## MODE: diagnose
Explain the root cause of each symptom in `SYMPTOMS`, over the code named by `SCOPE`. This is root-cause analysis of KNOWN symptoms, not discovery (`audit`) and not fix-choice (`consult`). You MAY state fix-constraints (what any fix must satisfy or cannot do); you MUST NOT compare or recommend remediation strategies. Never invent a cause: if a symptom's root cause cannot be located in the code, set the locator to the literal `not established` (never a guessed `file:line`), `confidence: low`, and a `missing-evidence` line.

```
STATUS: DIAGNOSIS_COMPLETE
REQUEST_ID: <nonce>
SUMMARY: <one line>

## Diagnosis
- [symptom: <ref>] <root cause @ file:line | not established>
  mechanism: <why the symptom happens, or "undetermined">
  evidence: <what in the code proves it>
  confidence: high|medium|low
  fix-constraints: <what any fix must satisfy / cannot do>   (optional)
  missing-evidence: <what is needed to raise confidence>     (required when confidence<high or root cause "not established")

## Notes
<optional>
```
Locator: `file:line`, or the literal `not established`. One `- [symptom: ...]` entry per provided symptom.
```

- [ ] **Step 3: Manual verification (regression + content)**

Run: `bash test/smoke.sh`
Expected: still all `ok` (VERIFIER.md is copied into the prompt; smoke must stay green).
Then re-read the new block against the spec's VERIFIER.md section: STATUS first line, REQUEST_ID second line, `not established` form present, fix-constraints-yes/fix-choice-no wording present. (Content judgement is a manager/user review item, not an automated pass.)

---

### Task 3: `MANAGER.md` — DIAGNOSE protocol

**Files:**
- Modify: `MANAGER.md` (mode-selection table ~lines 10-14; anti-conflict rules ~lines 16-19; add a `## DIAGNOSE` section after the `## AUDIT` section ~line 41; "How to invoke" step 1 ~lines 51-53; exit-code list ~lines 56-59)

**Interfaces:**
- Consumes: the `MODE: diagnose` + `SCOPE` + `SYMPTOMS` request contract (Task 1) and the `DIAGNOSIS_COMPLETE`/exit-0 mapping.
- Produces: manager-facing rules — no downstream task depends on its exact wording.

- [ ] **Step 1: Add the `diagnose` row to the mode-selection table**

In the table under "## Choosing the mode (deterministic)", add a row (place it above the `review` row, after `audit`):

```
| Need the root cause of a KNOWN symptom/bug in existing code | `diagnose` |
```

- [ ] **Step 2: Add anti-conflict rules for `diagnose`**

In the "Anti-conflict rules:" list, append:

```
- `diagnose` is behavior-first (explain a KNOWN symptom) while `audit` is code-first (discover UNKNOWN defects). Discriminator: is an observed symptom/repro provided? Yes → `diagnose`; no → `audit`.
- An `audit` finding usually already locates its cause — do not redundantly re-diagnose it. But `audit` only guarantees discovery, not a mechanism; if an audit-surfaced symptom has a genuinely uncertain root cause, escalating that one symptom to `diagnose` is correct. The symptom's source (user or a prior audit) does not gate the choice.
- A mixed request ("diagnose X, and find what else is broken") = two invocations: `diagnose` for X plus a separate `audit` for the rest. Do not merge them.
- Bug-handling order: `diagnose` (when the root cause is uncertain) → `consult` per the existing mandatory-CONSULT triggers → implementation → `review`. `diagnose` precedes `consult`; it does not narrow or replace it.
```

- [ ] **Step 3: Add the `## DIAGNOSE` section after the `## AUDIT` section**

Insert after the AUDIT section (after its "Run audits at `high` effort." line), before "## Superpowers workflow gates":

```markdown
## DIAGNOSE (symmetric, two independent passes)
When you need the root cause of a known symptom/bug in existing code:
1. **Your own hypothesis first.** Investigate the scope yourself and record your root-cause hypothesis to a file BEFORE you read the verifier's diagnosis (preserves independence — no anchoring).
2. **Verifier's independent diagnosis.** Invoke `MODE: diagnose` (see below) with `SCOPE` + `SYMPTOMS` only — never your hypothesis.
3. **Consolidate.** Per symptom, reconcile the two root causes. For any symptom where the sides disagree, or only one side located the cause, verify it yourself and mark it `disputed` with your resolution. Record a "Decision after synthesis".
4. **Final review.** Send the consolidated diagnosis through `MODE: review` with `ACCEPTANCE` = root cause is correct and evidence-backed, no misattribution, fix-constraints are sound, and every symptom is addressed. `CHANGES_REQUESTED` → rework and re-review (cap ~3 rounds, then escalate).

Trigger (discretionary): `diagnose` is mandatory when the root cause is non-trivial/uncertain after your first inspection; for an obvious single-line cause you may skip it, but MUST log the skip in one line (what the cause is, why it is obvious).
Under-specified symptoms: do not block the user — proceed best-effort; if repro/expected/actual are missing and cannot be inferred, the diagnosis carries `confidence: low` + explicit `missing-evidence`.
Diagnosis is "what & why" only: it may state fix-constraints but never chooses the fix (that is a separate `consult`).

Run diagnoses at `high` effort.
```

- [ ] **Step 4: Add the DIAGNOSE invoke bullet to "How to invoke the verifier" step 1**

In step 1's list of request shapes, add after the AUDIT bullet:

```
   - DIAGNOSE: `MODE: diagnose` + `SCOPE` (paths/globs/subsystem) + `SYMPTOMS` (observed bug(s)/repro). No `FOCUS` — the symptoms already focus the investigation.
```

- [ ] **Step 5: Add `DIAGNOSIS_COMPLETE` to the exit-code 0 line**

In the exit-code list, change the `0` line to include the diagnose status:

```
   - `0`  → PASS / ADVICE / AUDIT_COMPLETE / DIAGNOSIS_COMPLETE
```

- [ ] **Step 6: Manual verification (regression + content)**

Run: `bash test/smoke.sh`
Expected: still all `ok` (MANAGER.md is copied at install; smoke installs it and must stay green).
Then re-read the edited sections against the spec's MANAGER.md change list: table row, four anti-conflict bullets, full DIAGNOSE section, invoke bullet, exit-code line. (Content judgement is a manager/user review item.)

---

### Task 4: `README.md` (all mode references) + `VERSION` bump

The README documents modes in six places (verified by the plan gate). All must
gain `diagnose` for the docs to stay consistent with `verify.sh`/`MANAGER.md`.

**Files:**
- Modify: `README.md` (intro diagram line 12; modes table+heading lines 48-54; read-only line 60; manual-invocation diff line 181; exit-code table line 186; request-format section line 220; verdict-format section line 254; cache-cleanup line 305)
- Modify: `VERSION` (`1.1.1` → `1.2.0`)

**Interfaces:**
- Consumes: nothing downstream.
- Produces: user-facing documentation + the version string the update-check compares.

- [ ] **Step 1: Modes table + heading (lines 48-54)**

Change the heading `### Three modes` to `### Four modes`, and add a `DIAGNOSE` row to the table after the `AUDIT` row:

```
| **DIAGNOSE** | independent root-cause analysis of a KNOWN symptom/bug in existing code (both agents diagnose, then the manager consolidates and REVIEWs the result) | `STATUS: DIAGNOSIS_COMPLETE` + Diagnosis (non-gating) |
```

- [ ] **Step 2: Intro diagram label (line 12)**

In the diagram line containing `request (CONSULT|REVIEW|AUDIT)`, add the new mode:

```
┌─────────────┐ request (CONSULT|REVIEW|AUDIT|DIAGNOSE) ┌──────────────────┐
```

(If adding `|DIAGNOSE` breaks the ASCII box alignment, keep the box border characters aligned by trimming surrounding spaces so the overall width is unchanged.)

- [ ] **Step 3: Read-only guarantee line (line 60)**

Change the clause `for `audit` Claude reads the files named by `SCOPE`` to cover both no-diff modes:

```
surface. For `review`/`consult` the helper prepares the diff and Claude reads it; for `audit`/`diagnose` Claude reads the files named by `SCOPE` under `REPO_ROOT`.
```

- [ ] **Step 4: Manual-invocation diff line (line 181)**

Change `prepares the diff (for `review`/`consult`; `audit` skips it)` to:

```
The helper computes the paths itself, prepares the diff (for `review`/`consult`; `audit`/`diagnose` skip it), calls the opposite agent,
```

- [ ] **Step 5: Exit-code table (line 186)**

Change the exit-`0` row to include the new status:

```
| `0`  | `PASS` / `ADVICE` / `AUDIT_COMPLETE` / `DIAGNOSIS_COMPLETE` |
```

- [ ] **Step 6: Request-format section (after the AUDIT block, line 225)**

Add a `DIAGNOSE` request example after the `**AUDIT:**` fenced block:

````
**DIAGNOSE:**
```
MODE: diagnose
SCOPE: <paths/globs/subsystem to inspect>
SYMPTOMS: <observed bug(s) / repro — what is wrong, expected vs actual>
```
````

- [ ] **Step 7: Verdict-format section (after the AUDIT block, line 264)**

Add a `DIAGNOSE` verdict example after the `**AUDIT:**` fenced block:

````
**DIAGNOSE:**
```
STATUS: DIAGNOSIS_COMPLETE
REQUEST_ID: <nonce>
SUMMARY: <one line>

## Diagnosis
- [symptom: <ref>] <root cause @ file:line | not established>
  mechanism: <why the symptom happens>
  evidence: <what in the code proves it>
  confidence: high|medium|low
  fix-constraints: <what any fix must satisfy / cannot do>   (optional)
  missing-evidence: <needed when confidence<high or "not established">

## Notes
```
````

- [ ] **Step 8: Cache-cleanup line (line 305)**

Change `audit` writes no diff` to cover both no-diff modes:

```
For `review`/`consult` the diff can be sizable (the whole working-tree diff); `audit`/`diagnose` write no diff.
```

- [ ] **Step 9: Bump `VERSION`**

Set the sole line of `VERSION` to:

```
1.2.0
```

- [ ] **Step 10: Manual verification**

Run: `bash test/smoke.sh`
Expected: all `ok`, including `installed version matches repo VERSION` and `version marker is real semver` (both read the bumped `VERSION` file).
Then visually confirm: the modes table, both format sections, exit-code table, and the three inline clauses all mention `diagnose` consistently. (Content judgement is a user review item.)

---

## Self-Review

**Spec coverage:**
- Transport (verify.sh: audit|diagnose branch, SCOPE+SYMPTOMS, STATUS validation, exit-0) → Task 1.
- VERIFIER.md MODE block + Common line 7 → Task 2.
- MANAGER.md table/anti-conflict/DIAGNOSE/invoke/exit-codes → Task 3.
- README + VERSION bump → Task 4.
- Decisions (discretionary trigger, fix-constraints-only, always two-pass, soft under-spec, `not established` form, anti-conflict) → encoded in Tasks 2 & 3 content and the spec Global Constraints. No spec section is left without a task.

**Placeholder scan:** No TBD/TODO; every code/edit step shows exact strings. README Step 2 intentionally describes content to mirror an existing row rather than hardcoding a format this plan cannot see — the implementer reads the real row first (Step 1).

**Type consistency:** Status string `STATUS: DIAGNOSIS_COMPLETE`, field names `SCOPE`/`SYMPTOMS`, locator form `not established`, and exit codes (0/10/20/64) are used identically across Tasks 1–4 and match the spec.
