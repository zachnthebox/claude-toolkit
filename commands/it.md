---
description: Build one safe unit with risk-routed review, fix loops, and a final security gate
argument-hint: [goal, or path to a spec doc with a "## Steps" section]
allowed-tools: Read, Grep, Glob, Bash, Agent
model: inherit
# This command commits, pushes, and opens PRs — deploy-class side effects.
# Only the user decides when to ship; Claude must never auto-invoke it.
disable-model-invocation: true
---
Goal: $ARGUMENTS

Orchestrate the work; do not write feature code yourself. Use `builder` for all
edits — reviewers never edit files, and the builder never reviews its own diff.
The standard of done is satisfied acceptance criteria, meaningful tests,
reviewed code, green final checks, and the project's documented invariants
intact (its `CLAUDE.md`, when it has one).

This command and its agents ship together in the `ship` plugin, so the agents are
registered under that namespace. When you spawn one, pass the namespaced
`subagent_type` — `ship:builder`, `ship:recon`, `ship:reviewer-rigorous`,
`ship:reviewer-architect`, `ship:reviewer-frontend`, `ship:reviewer-minimalist`,
`ship:reviewer-security` — even where the steps below name them in short form
(`builder`, `recon`, `reviewer-…`). This one list is the only place tied to the
plugin name; update it if it is renamed.

## Communication style

Keep the running narration lean. The progress the user wants stays — one line
when you delegate a unit, route reviewers, or clear a blocker — but drop
preamble and routine play-by-play ("Now I'll…", "Let me check…"). Lead with the
outcome, not the steps you took to reach it. The §5 finish report is the
deliverable; keep it complete. Terseness here is not silence: never trade away
the visibility that lets the user follow what actually ran.

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

When a step calls for parallel reviewers (§2, §3.5, §4), issue every
reviewer's `Agent` call as its own tool-use block within the *same* assistant
message, each still with `run_in_background: false`. Same-message tool calls
run concurrently regardless of that flag, so this gets true parallelism while
keeping every result synchronous — the run resumes once every reviewer in the
batch has returned, in that same turn, with no notification hop to miss.

## Subagents are stateless — pass everything, parse the reply

Every `builder`/reviewer sees ONLY the delegation prompt you write: no
conversation history, no files you read, no earlier agent's output. Restate in
each prompt everything that agent needs.

**Builder packet** — the acceptance checklist; constraints / step Notes;
`INITIAL_DIRTY_PATHS`; on a fix round, the deduplicated findings; when recon ran
(§2, §3), its `RECON BRIEF` verbatim, with an instruction that the builder works
from those anchors and does not re-read those files in full; in STEP MODE, the
plan doc path and selected step. The builder returns a `CHANGE MANIFEST` whose
first line is `Status: committed <sha>` or `Status: blocked — <reason>`.

**Recon packet** — the target to locate (the acceptance checklist, or the
deduplicated findings on a fix round) and any paths already known to be
relevant. `recon` never edits and returns a `RECON BRIEF` of file:line anchors
and bounded excerpts — never a full-file summary. Fold its brief into the next
`builder` packet; do not make the builder re-derive what recon already found.

**Reviewer packet** — the literal diff command with a SHA you resolved (e.g.
`git diff <BASELINE>...HEAD` — never a shell variable, never "the current
changes"); the acceptance checklist; the manifest fields relevant to that
reviewer's lane; and the activated failure classes. A reviewer must never
choose its own diff range.

**Reviewer reply shape** — all five reviewers answer in one format: zero or
more `[BLOCKER|WARNING][failure-class][confidence]` finding blocks, then a
final line `VERDICT: PASS (0 blockers, M warnings)` or
`VERDICT: BLOCK (N blockers, M warnings)`. Route on that last line; adjudicate
each blocker on its evidence (§3), not the verdict alone.
`reviewer-minimalist` is warning-only and always ends `VERDICT: PASS`.

**Fail closed on invalid replies** — agents die: mid-run errors, turn
exhaustion, truncation. A reply with no final `VERDICT:` line is not a review,
and a builder reply with no `Status:` line is not a build. Apply one uniform
rule to every delegation: validate the reply against its contract the moment
it returns; on an invalid or errored reply, re-spawn that agent once with the
same packet plus a one-line note about the failed attempt; if the retry is
also invalid, hard-stop the run and report which agent could not complete.
Never infer a PASS from silence — above all for the security gate — and never
adjudicate findings from a reply whose verdict line is missing.

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
   expected. `.claude/agent-memory/**` is always expected dirt — the builder and
   rigorous reviewer maintain per-project memory there (`memory: project`). Any
   other dirty path must be explicitly included by the user or the run stops
   with the path list. Never absorb unrelated work.
4. Record the literal `BASELINE` SHA after branch setup and before the builder.
   Keep the SHA in the orchestration notes; do not depend on a shell variable
   surviving another Bash call.
5. If the project provides a reviewer-routing contract — a dedicated file such as
   `review-corpus/review-matrix.md`, or a pointer in its `CLAUDE.md` — read it; it
   is canonical and overrides the default routing in §2. Absence is the normal
   case: the §2 default derives routing from the diff itself and requires
   nothing from the project. Never stall looking for a matrix.

## 2. Build and classify risk

If the constraints/step Notes name specific files or modules, check their size
(`wc -l` or equivalent). When any named file is large (roughly 300+ lines) or
unfamiliar, run `recon` on it first, scoped to the acceptance checklist, and
fold the `RECON BRIEF` into the builder packet. Skip recon when the unit's
files are small or the target is greenfield — it exists to bound reads on
large/unfamiliar code, not to run on every unit.

Delegate the acceptance checklist, constraints, `INITIAL_DIRTY_PATHS`, any
recon brief, and any prior findings to `builder`. Require a commit and its
`CHANGE MANIFEST`. The builder runs focused tests/checks during iteration; the
orchestrator owns the final full suite.

Verify after return:

- The manifest's `Status:` line says `committed <sha>` and that SHA is a real
  commit on the branch.
- The commit exists and the intended diff is `git diff BASELINE...HEAD`.
- Pre-existing dirty paths were preserved.
- No out-of-scope file was committed (`.claude/agent-memory/**` updates are in
  scope by default).
- The manifest names changed contracts, persistence/derived data, trust
  boundaries, new mechanisms, callers, and tests.

### If the builder produced no commit

An `Agent` delegation can end without doing the work — an agent died mid-run, a
terminal API error, a manifest with no matching commit — and still return as
"done." Never take agent completion alone as evidence of progress; check
`git log BASELINE..HEAD` and the manifest's stated SHA yourself before trusting
either.

If the manifest says `Status: blocked — <reason>`, read the reason first: a
missing or ambiguous input is yours to fix — repair the packet and re-delegate;
a genuinely unbuildable acceptance criterion is a hard stop to report, not
something to retry blind.

If `git log BASELINE..HEAD` is empty (no new commit) or the returned manifest
does not name a real commit on the branch:

1. Treat this as a stall, not a failure of the unit — the acceptance checklist
   is unproven either way, not disproven.
2. A stall this early is itself evidence the builder spent its turns reading
   instead of editing. Before re-delegating, run `recon` (if not already run
   for this unit) scoped to the acceptance checklist and any files visible in
   the stalled attempt's partial diff or manifest.
3. Re-delegate to a fresh `builder` call with the same acceptance checklist,
   constraints, and `INITIAL_DIRTY_PATHS`, plus the recon brief and one line
   noting the prior attempt returned without a commit so the retry doesn't
   repeat the same dead end blind.
4. Re-verify `git log BASELINE..HEAD` after each retry. Allow up to two retries
   (three attempts total) before treating it as a hard stop.
5. If all attempts stall, stop and report the unit as unbuilt — do not report
   completion, and do not silently move on to review with nothing to review.

Classify the complete unit diff using changed paths plus the manifest. If the
project supplied a routing contract in §1.5, it is canonical and wins wherever the
two differ. Otherwise this default routing applies:

- `reviewer-rigorous`: always.
- `reviewer-architect`: persistence/schema/migrations, queues/jobs, concurrency,
  caches/projections, runtime/dependencies, cross-layer contracts, DI boundaries,
  or substantial data-access changes.
- `reviewer-frontend`: any change to the project's web-frontend code — detect it
  from the diff (directories like `web/`, `frontend/`, `client/`, an app's view
  layer, or component/style/markup files). Projects with no web frontend never
  route here.
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

Parse each reviewer's final `VERDICT:` line to see who blocked. A finding
blocks only when it is marked `BLOCKER` and contains a concrete code path,
observable failure/attack, complete fix, and proof requirement — evidence, not
reviewer votes or verdict lines, determines severity; downgrade a blocker whose
evidence doesn't hold. Merge duplicate class + location findings before sending
them to the builder. Warnings — including every minimalist finding, which are
warning-only by contract — are reported to the user but block only if their
evidence independently proves an acceptance criterion unmet. Exception:
resolve every `[WARNING][cannot-verify]` finding yourself — inspect the named
path or route a scoped check — before treating that review as complete; it
marks a gap in coverage, not a pass-through warning.

For each blocking fix batch:

1. Record HEAD's SHA as the fix baseline (`FIX_BASE`, used in step 5) before
   delegating — a literal SHA in the orchestration notes, not a shell variable that
   another Bash call won't preserve (per §1.4).
2. Run `recon` scoped to the deduplicated findings — each already carries a
   file:line location, so this is cheap. Fold the `RECON BRIEF` into the fix
   packet so the builder starts from the exact site instead of re-finding it.
3. Send the deduplicated findings and the recon brief to `builder`; require
   regression tests and a commit.
4. Inspect the fix manifest and diff. If it adds a field, column, table, guard,
   cache, optional value, stored flag, or dependency, re-run the routing matrix.
5. Review `git diff <FIX_BASE>...HEAD` with the reviewer(s) that raised the
   blocker plus every newly activated specialist. Do not make the full panel
   rediscover the unchanged unit.
6. Repeat for at most three blocking fix rounds.

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

If its final line is `VERDICT: BLOCK (…)`:

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
   pre-existing dirty path was staged or committed. If `.claude/agent-memory/**`
   files are dirty (reviewer memory written during review), commit them now as a
   separate chore commit — sessions may run in ephemeral containers, so
   uncommitted agent memory is lost.
3. Push the branch. The whole build/review/fix loop ran locally, so the branch
   reaches the remote only once it is green — nothing half-built is pushed. If no
   PR exists, open one ready for review now. If a PR already exists, update it only
   after the local gate is green.
4. Report the unit shipped, checks run, reviewers activated and why, blockers
   fixed, warnings left, and preserved dirty paths.

Never rewrite commits to satisfy a commit-identity or signature warning. A local
"Unverified" / no-signature reading (`git log --format=%G?` = `N`) is expected in
managed environments that sign with a key the container can't verify locally; the
commit verifies on the remote. Do not `git commit --amend --reset-author` or
`git rebase --exec` to chase it, and never rewrite branch history while a spawned
`builder` is still committing onto it (it changes every SHA, including that
builder's base). Push as-is. This reading is a non-event: do not surface it as a
"warning left" in the step-4 report, and do not explain it — say nothing.

In STEP MODE, stop after this one step and tell the user to merge the PR before
re-running `/ship:it <doc>` for the next step. In GOAL MODE, stop at the stated goal.

Hard stops: unrelated dirty work without explicit scope; inability to establish
the intended diff; three unresolved correctness/specialist fix rounds; or two
unresolved security fix rounds.
