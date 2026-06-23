# Design — `diagnose` mode for pair-mode

Date: 2026-06-23
Status: approved (brainstorming), pending spec gate + user review

## Problem

Pair-mode has three verifier modes: `review` (gating, diff-centric), `consult`
(advisory, forward-looking), `audit` (discovery over a scope, non-gating). None
gates the step *between* them: **root-cause analysis of a known symptom**.

Real gap (observed session): the user reported two concrete bugs in an existing
component and asked to "diagnose them". Because the findings were already
provided, this was neither discovery (`audit`) nor a fix-choice (`consult`). No
mode covered it, so the manager diagnosed solo and only planned to involve the
verifier later at `consult` (fix approach). Root-cause work — exactly where
anchoring hurts most — got no independent second pass.

## Goal

Add a `diagnose` mode so root-cause analysis of known symptoms gets an
independent, symmetric second pass, mechanically aligned with `audit` but
distinct in intent and inputs.

## Decisions (brainstorming)

1. **Distinct mode, not `audit + SYMPTOMS`.** Provided symptoms anchor the
   investigation by design; folding them into `audit` would corrupt audit's
   independent-discovery role.
2. **Trigger: discretionary.** `diagnose` is mandatory when the root cause is
   non-trivial / uncertain after the manager's first inspection. For an obvious
   single-line cause the manager may skip it, but MUST log the skip in one line
   (what the cause is, why it is obvious).
3. **Fix boundary: fix-constraints allowed, fix-choice forbidden.** A diagnosis
   may state what any fix must satisfy or cannot do (e.g. "must clear the stale
   closure", "not solvable by changing width") but MUST NOT compare or choose
   remediation strategies — choosing the fix stays a separate `consult`.
4. **Always symmetric two-pass.** No single-pass "lite" escape. The discretionary
   trigger already filters out trivial cases (an obvious root cause is not a
   `diagnose` at all).
5. **Under-specified symptoms: soft.** Proceed best-effort; if repro / expected /
   actual are missing and cannot be inferred, emit the diagnosis with
   `confidence: low` and explicit `missing-evidence` rather than blocking the user.

## Anti-conflict with `audit`

Mechanically near-identical (scope-centric, no diff, non-gating, symmetric
two-pass), so the boundary is enforced at mode selection:

- `audit` = **code-first** discovery of unknown defects (input: scope only).
  `diagnose` = **behavior-first** explanation of a known symptom (input: an
  observed symptom / repro). Discriminator: *is an observed symptom/repro
  provided?* Yes → `diagnose`; no → `audit`.
- An `audit` finding usually already locates its cause — do NOT redundantly
  re-diagnose findings `audit` has already explained. But `diagnose` is not
  forbidden on audit-surfaced issues: `audit` only guarantees discovery
  (`file:line` + description), not a root-cause mechanism, so if an `audit`
  finding names a real symptom whose root cause is genuinely uncertain,
  escalating that one symptom to `diagnose` is correct. The discriminator stays
  behavior-first vs code-first; the *source* of the symptom (user or a prior
  audit) does not gate it.
- A mixed request ("diagnose X, and also see what else is broken") = two
  invocations: `diagnose` for X **plus** a separate `audit` for the rest. Do not
  merge them.

At the transport level there is no conflict: distinct terminal STATUS
(`AUDIT_COMPLETE` vs `DIAGNOSIS_COMPLETE`) so validation cannot cross-accept, and
distinct required fields (`audit`: `SCOPE`; `diagnose`: `SCOPE` + `SYMPTOMS`).

## Changes

### `verify.sh` (transport)

- Treat `diagnose` as scope-centric / no-diff, same branch as `audit`: extend the
  `if [ "$MODE" = audit ]` guard to `audit|diagnose`. Both require a non-empty
  `SCOPE:` line. `diagnose` additionally requires a non-empty `SYMPTOMS:` line
  (else exit 64). The prompt build omits `DIFF_PATCH` for both.
- Validation `case`: add `diagnose) [ "$first" = "STATUS: DIAGNOSIS_COMPLETE" ]
  || fail20 "STATUS!=MODE(diagnose)"`.
- Exit-code `case`: add `STATUS: DIAGNOSIS_COMPLETE` to the `exit 0` success list.

### `VERIFIER.md`

- Common, line 7: update "For `audit`: ... inspect the files named by `SCOPE`" to
  cover `audit`/`diagnose` (both no `DIFF_PATCH`, inspect `SCOPE` files).
- New `## MODE: diagnose` block. Instruction: explain the root cause of each
  provided `SYMPTOMS` entry over `SCOPE`. Allowed to state fix-constraints (what a
  fix must address / cannot solve) but MUST NOT compare or choose remediation
  strategies. Never invent a cause: when the root cause cannot be located, the
  locator MUST be the literal `not established` (not a guessed `file:line`), with
  `confidence: low` and a required `missing-evidence` line. Output format:

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

### `MANAGER.md`

- Mode-selection table: add a `diagnose` row — "Need the root cause of a KNOWN
  symptom/bug in existing code → `diagnose`".
- Anti-conflict rules: add the three bullets from "Anti-conflict with `audit`"
  above; state the bug-handling order: `diagnose` (when root cause is uncertain)
  → `consult` **per the existing mandatory-CONSULT triggers** (`MANAGER.md:21` —
  architecture, contracts/API, security, migrations, test strategy, large
  behavior/UX changes, or any fork with 2+ real options) → implementation →
  `review`. This does NOT narrow consult: `diagnose` precedes consult, it does
  not replace or restrict it.
- New `## DIAGNOSE (symmetric, two independent passes)` section mirroring AUDIT:
  1. Your own root-cause hypothesis first, recorded to a file BEFORE reading the
     verifier's diagnosis (anti-anchoring).
  2. Verifier's independent diagnosis: `MODE: diagnose` with `SCOPE` + `SYMPTOMS`
     only — never your hypothesis.
  3. Consolidate: per symptom, reconcile root causes; for any symptom where the
     two disagree or only one side found it, verify yourself and mark `disputed`
     with your resolution. Record a "Decision after synthesis".
  4. Final review: send the consolidated diagnosis through `MODE: review`,
     `ACCEPTANCE` = root cause correct & evidence-backed, no misattribution,
     fix-constraints sound, all symptoms addressed. `CHANGES_REQUESTED` → rework
     and re-review (cap ~3 rounds, then escalate).
  - Trigger (discretionary): mandatory when the root cause is non-trivial /
    uncertain after first inspection; for an obvious single-line cause the
    manager may skip and MUST log the skip in one line.
  - Under-specified symptoms: best-effort with `confidence: low` +
    `missing-evidence`; do not block the user.
  - Run diagnoses at `high` effort.
- "How to invoke the verifier", step 1: add a DIAGNOSE bullet — `MODE: diagnose`
  + `SCOPE` + `SYMPTOMS`. No `FOCUS`: the provided symptoms already focus the
  investigation.
- Exit-code list: `0` → PASS / ADVICE / AUDIT_COMPLETE / DIAGNOSIS_COMPLETE.

### `README.md`

- Document `diagnose` in the modes section, alongside the existing three.

### `VERSION`

- Bump `1.1.1` → `1.2.0` (new feature; drives the update-check banner).

## Out of scope

- No `diagnose-lite` single-pass path.
- `diagnose` does not propose or choose fixes (that remains `consult`).
- No change to `review` / `consult` / `audit` semantics beyond the shared
  no-diff transport branch and the exit-code/STATUS additions.
