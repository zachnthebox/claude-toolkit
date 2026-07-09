---
description: Build one safe unit with risk-routed review, fix loops, and a final security gate
argument-hint: [goal, or path to a spec doc with a "## Steps" section]
allowed-tools: Read, Grep, Glob, Bash, Agent
model: inherit
---
Goal: $ARGUMENTS

Orchestrate the work; do not write feature code yourself. Use `builder` for all
edits. The standard of done is satisfied acceptance criteria, meaningful tests,
reviewed code, green final checks, and intact CLAUDE.md invariants.

This command and its agents ship together in the `ship` plugin, so the agents are
registered under that namespace. When you spawn one, pass the namespaced
`subagent_type` — `ship:builder`, `ship:reviewer-rigorous`, `ship:reviewer-architect`,
`ship:reviewer-frontend`, `ship:reviewer-minimalist`, `ship:reviewer-security` —
even where the steps below name them in short form (`builder`, `reviewer-…`). This
one list is the only place tied to the plugin name; update it if it is renamed.

## Delegation mode: foreground, always

Every `builder`/reviewer delegation below gates the very next instruction in
this command — there is no point where the orchestrator has other useful work
to do while one runs. Call `Agent` with `run_in_background: false` for every
delegation in this command. Do not fall back to the tool's background default:
that ends the orchestrator's turn to wait on a `task-notification`, and if that
notification is missed, delayed, or the session isn't being watched when it
arrives, the run reads as "stopped" rather than "waiting on an agent" — a human
has to notice and nudge it to continue. Running in the foreground makes the
wait synchronous and visible in the same turn instead.

When a step calls for parallel reviewers (§2, §3.4, §4), issue every
reviewer's `Agent` call as its own tool-use block within the *same* assistant
message, each still with `run_in_background: false`. Same-message tool calls
run concurrently regardless of that flag, so this gets true parallelism while
keeping every result synchronous — the run resumes once every reviewer in the
batch has returned, in that same turn, with no notification hop to miss.

## 0. Select exactly one unit

If the argument is a working-tree document containing `## Steps`, use STEP MODE:

1. Read the plan from the working tree.
2. Fetch `origin/main`. Read the same path from `origin/main` (fall back to local
   `main`). Only steps marked `shipped` there have merged. If the document is not
   on main yet, no steps have merged.
3. Select the first unshipped step whose dependencies have merged. Ship exactly
   that step and stop; never batch or begin the next step.
4. The builder must include the plan document and mark the selected step
   `shipped (<branch or PR>)` in the unit commit. Main remains the source of truth,
   so this status advances the plan only after the PR merges.

Otherwise use GOAL MODE and treat the argument as one PR-sized unit. If it is not
PR-sized, stop and recommend `/ship:plan`; do not silently run multiple milestones.

Restate the unit as a short, verifiable acceptance checklist. Carry the selected
step's Notes as constraints, not as extra scope.

## 1. Preflight before delegation

1. Fetch `origin/main` and inspect the current branch, upstream, HEAD, and
   `git status --porcelain=v1`.
2. Never build or commit on `main` or detached HEAD. Create a goal-derived
   `claude/<slug>` branch before continuing when needed.
3. Record `INITIAL_DIRTY_PATHS`. In STEP MODE the uncommitted plan document is
   expected. Any other dirty path must be explicitly included by the user or the
   run stops with the path list. Never absorb unrelated work.
4. Record the literal `BASELINE` SHA after branch setup and before the builder.
   Keep the SHA in the orchestration notes; do not depend on a shell variable
   surviving another Bash call.
5. If the project provides a reviewer-routing contract — a dedicated file such as
   `review-corpus/review-matrix.md`, or a pointer in its `CLAUDE.md` — read it; it
   is canonical and overrides the default routing in §2. Otherwise use the §2
   default.

## 2. Build and classify risk

Delegate the acceptance checklist, constraints, `INITIAL_DIRTY_PATHS`, and any
prior findings to `builder`. Require a commit and its `CHANGE MANIFEST`. The
builder runs focused tests/checks during iteration; the orchestrator owns the
final full suite.

Verify after return:

- The commit exists and the intended diff is `git diff BASELINE...HEAD`.
- Pre-existing dirty paths were preserved.
- No out-of-scope file was committed.
- The manifest names changed contracts, persistence/derived data, trust
  boundaries, new mechanisms, callers, and tests.

### If the builder produced no commit

An `Agent` delegation can end without doing the work — a died mid-run, a
terminal API error, a manifest with no matching commit — and still return as
"done." Never take agent completion alone as evidence of progress; check
`git log BASELINE..HEAD` and the manifest's stated SHA yourself before trusting
either.

If `git log BASELINE..HEAD` is empty (no new commit) or the returned manifest
does not name a real commit on the branch:

1. Treat this as a stall, not a failure of the unit — the acceptance checklist
   is unproven either way, not disproven.
2. Re-delegate to a fresh `builder` call with the same acceptance checklist,
   constraints, and `INITIAL_DIRTY_PATHS`, plus one line noting the prior
   attempt returned without a commit so the retry doesn't repeat the same
   dead end blind.
3. Re-verify `git log BASELINE..HEAD` after each retry. Allow up to two retries
   (three attempts total) before treating it as a hard stop.
4. If all attempts stall, stop and report the unit as unbuilt — do not report
   completion, and do not silently move on to review with nothing to review.

Classify the complete unit diff using changed paths plus the manifest. If the
project supplied a routing contract in §1.5, it is canonical and wins wherever the
two differ. Otherwise this default routing applies:

- `reviewer-rigorous`: always.
- `reviewer-architect`: persistence/schema/migrations, queues/jobs, concurrency,
  caches/projections, runtime/dependencies, cross-layer contracts, DI boundaries,
  or substantial data-access changes.
- `reviewer-frontend`: any change to the project's frontend/UI code (e.g. a `web/`
  directory or an app's view layer).
- `reviewer-security` early: auth/authorization, user-owned data, routes/input,
  URLs/fetching, errors/secrets/PII, SQL/deserialization, destructive migrations,
  dependencies, CI/deploy, resource bounds, or permissions.
- `reviewer-minimalist`: new dependency, abstraction, configuration surface,
  module/layer, or substantial new code. Run it once per unit, not every round.

Run the activated reviewers in parallel. Give each the literal command
`git diff <BASELINE>...HEAD`, the acceptance checklist, relevant manifest fields,
and the activated failure classes. A reviewer must never choose its own diff
range.

## 3. Adjudicate and fix

A finding blocks only when it is marked `BLOCKER` and contains a concrete code
path, observable failure/attack, complete fix, and proof requirement. Evidence,
not reviewer votes, determines severity. Merge duplicate class + location
findings before sending them to the builder. Warnings and minimalist findings are
reported but do not block unless their evidence independently proves acceptance
criteria are unmet.

For each blocking fix batch:

1. Record HEAD's SHA as the fix baseline (`FIX_BASE`, used in step 4) before
   delegating — a literal SHA in the orchestration notes, not a shell variable that
   another Bash call won't preserve (per §1.4).
2. Send deduplicated findings to `builder`; require regression tests and a commit.
3. Inspect the fix manifest and diff. If it adds a field, column, table, guard,
   cache, optional value, stored flag, or dependency, re-run the routing matrix.
4. Review `git diff <FIX_BASE>...HEAD` with the reviewer(s) that raised the
   blocker plus every newly activated specialist. Do not make the full panel
   rediscover the unchanged unit.
5. Repeat for at most three blocking fix rounds.

After fixes, run `reviewer-rigorous` once on `git diff <BASELINE>...HEAD` if any
fix commit was added after its last complete-unit review. This is the final
cross-file correctness sweep.

When handling external PR comments, use this same flow: capture the current HEAD
as the baseline before the comment-fix batch, preserve unrelated dirt, route the
fix, and review before push. Do not infer a base with `HEAD~N`.

## 4. Final security fix loop

Run `reviewer-security` on the complete PR diff:
`git diff origin/main...HEAD`. This intentionally includes commits that predate
the current unit but will merge in the PR.

If the gate blocks:

1. Record HEAD as `SECURITY_FIX_BASE`.
2. Send the demonstrated blockers to `builder`; require tests and a commit.
3. Review `git diff <SECURITY_FIX_BASE>...HEAD` with security and rigorous, plus
   any specialist activated by the fix.
4. Re-run security on `git diff origin/main...HEAD`.

Allow at most two security fix rounds. If still blocked, stop and report the
remaining attack paths; do not push or claim completion.

## 5. Finish once

After all blocking findings are cleared:

1. Run the project's full verification gate. This step is toolchain-agnostic on
   purpose — the project owns what "green" means, not `/ship:it`. Projects expose it
   as an executable `.claude/hooks/ship-verify.sh` at the repo root, invoked as
   `.claude/hooks/ship-verify.sh <BASELINE-base-ref>` (the base ref defaults to
   `origin/main`). It is the single source of truth for the project's full build,
   lint, and test run, whether that is `npm test`, `xcodebuild test`, `cargo test`,
   or a mix. Run it and treat a non-zero exit as failure.
   If the project has no such script, do not assume a toolchain (`npm`, etc.):
   detect its conventional full build/lint/test command, or ask, before proceeding.
   Do not push on failure; send genuine code failures through the same scoped
   builder/reviewer loop.
2. Confirm the final diff, commits, branch, and plan-step status. Confirm no
   pre-existing dirty path was staged or committed.
3. Push the branch. The whole build/review/fix loop ran locally, so the branch
   reaches the remote only once it is green — nothing half-built is pushed. If no
   PR exists, open one ready for review now. If a PR already exists, update it only
   after the local gate is green.
4. Report the unit shipped, checks run, reviewers activated and why, blockers
   fixed, warnings left, and preserved dirty paths.

In STEP MODE, stop after this one step and tell the user to merge the PR before
re-running `/ship:it <doc>` for the next step. In GOAL MODE, stop at the stated goal.

Hard stops: unrelated dirty work without explicit scope; inability to establish
the intended diff; three unresolved correctness/specialist fix rounds; or two
unresolved security fix rounds.
