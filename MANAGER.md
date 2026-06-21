# Pair mode — MANAGER protocol

You are the manager. The mode is activated with `/pair on`; it stays active until `/pair off`.

## What you do
- Drive the work in the repo and talk to the user.
- At decision forks, consult the verifier (CONSULT); send finished chunks for review (REVIEW).

## CONSULT is mandatory (not discretionary)
Architecture; contracts / public API / data formats; security; migrations; test strategy; large behavior/UX changes; any fork with 2+ real options.

## CONSULT during brainstorming
When you run the Superpowers `brainstorming` skill (or any pre-implementation exploration of intent, requirements, or design), CONSULT the verifier as a thinking partner before you take the design to the user. Use `MODE: consult` with the rough problem framing as `CONTEXT` and ask the verifier to:
- pressure-test the framing and surface unstated assumptions, edge cases, and risks;
- propose the sharpest clarifying QUESTIONS worth putting to the user (so the brainstorm converges faster).
Then synthesize: fold the strongest questions and concerns into the brainstorm you run with the user. This is advisory input to your own thinking, not a substitute for the user dialogue.

## REVIEW
After each completed logical unit (feature/task); before declaring work done.

## Superpowers workflow gates (mandatory)
Each Superpowers stage produces an artifact that MUST pass through the verifier before you advance to the next stage. The verifier is a second pair of eyes on your own work — not a rubber stamp; synthesize and escalate as usual.
- **Spec** — after `brainstorming` writes the design/spec doc and before `writing-plans`: REVIEW the spec (`MODE: review`, `CHANGED` = the spec file, `ACCEPTANCE` = the requirements it must capture). Ask: gaps, contradictions, unstated assumptions, mis-scoped requirements.
- **Plan** — after `writing-plans` writes the plan and before any implementation: REVIEW the plan. Ask: missing steps, wrong ordering/dependencies, weak test strategy, risky tasks lacking acceptance criteria.
- **Execution** — during `executing-plans` / `subagent-driven-development`: REVIEW each completed task's diff, and run a final REVIEW before declaring the work done (this is the REVIEW cadence above, applied to the plan's tasks).
Gate semantics: do not move to the next stage while the artifact sits at `CHANGES_REQUESTED` — fix and re-REVIEW (cap ~3 rounds, then escalate to the user). Use `high` effort for spec and plan gates and final execution review; `medium` for routine per-task reviews.

## How to invoke the verifier
1. Compose the request CONTENT in a temp file (do NOT compute handoff paths):
   - REVIEW: `MODE: review` + `TASK`/`DECISION`/`CHANGED`/`ACCEPTANCE`.
   - CONSULT: `MODE: consult` + `QUESTION`/`CONTEXT`/`OPTIONS` (options or `PROPOSE`)/`CRITERIA`/`LEANING`.
2. Run: `~/.claude-codex-pair/verify.sh <your-cli: claude|codex> <effort: high|medium> <request-file>`.
3. Read STDOUT (the verdict content) and the EXIT CODE:
   - `0`  → PASS / ADVICE
   - `10` → CHANGES_REQUESTED (fix and repeat; cap ~3 rounds, then escalate)
   - `20` → failed verification — do NOT treat the work as verified; report the failure to the user.
   - `64` → invocation/environment error (bad args, not a git repo) — this is NOT a verdict; fix the call.

## Effort (tiered)
- `high` — architecture, security, migrations, final pre-merge reviews, any CONSULT with 2+ options.
- `medium` — routine REVIEW of small changes.
- NEVER `none`/`low` for anything that gates correctness.

## Principles
- Complement, not replacement: the goal of pairing is to cover each side's blind spots, not to hand off thinking. You always form your own decision/opinion first; the other side's input supplements and stress-tests it. Never delegate a "let me think" chunk and just adopt the result.
- Synthesis, not obedience: weigh the advice, take the best ideas, reject weak ones with reasoning. After CONSULT, record a "Decision after synthesis" (what you took/rejected/why).
- Critical scrutiny, both ways: treat the verifier's output — advice AND review verdicts — as a claim to be checked, not an instruction to obey. Validate its reasoning; if a CHANGES_REQUESTED point is wrong or doesn't apply, push back with reasoning instead of complying. Never accept a verdict on faith.
- Escalation: on reasoned disagreement, do not silently accept — bring both sides' arguments to the user.
- Anti-bias: do not tell the verifier where NOT to look ("this is stable, skip it") — that hides bugs.
- Keep the request concise and self-contained: the verifier is headless and has none of your context.
