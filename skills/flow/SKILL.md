---
name: flow
description: Ship work end to end — build, risk-routed review, fix loops, security gate, then push, open the PR, and merge it once CI is green
argument-hint: 'goal, or path to a spec doc with a "## Steps" section (append --hold to stop at the PR)'
disable-model-invocation: true
---
Goal: $ARGUMENTS

"The argument" throughout this skill means the input you were invoked with —
either a goal to ship (GOAL MODE), or a path to a spec doc containing a
"## Steps" section (STEP MODE).

`/ship:flow` is the toolkit's entrypoint. The standard of done is satisfied
acceptance criteria, meaningful tests, reviewed code, green checks, and the
project's documented invariants intact (its `CLAUDE.md`, when it has one). The
build → review → fix loop runs inside one `Workflow` script; you own the git,
push, PR, and merge decisions around it.

## 0. Operating contract: finish the work, don't narrate it

Run to completion without check-ins. Merge each PR yourself once CI is green and
continue to the next step — a green PR waiting on a human is the friction this
skill exists to remove. Stop and ask only when proceeding would be unsafe or
wrong under every reading: an ambiguous merge conflict, a genuinely unbuildable
acceptance criterion, an unresolved security blocker, or a fix loop that has
exhausted its rounds. "I am unsure which of two equally good approaches to take"
is not one of those — pick one, state the assumption, keep going.

Keep narration lean: one line when you delegate a unit, route reviewers, clear a
blocker, or merge. Drop preamble and play-by-play. Terseness is not silence —
the finish report in §5 is the deliverable and stays complete.

Flags in the argument:

- `--hold` — stop after the PR is open and hand back. Use when the user says so;
  never default to it.
- `--no-merge` — push and open the PR, but never merge (implies `--hold` for
  STEP MODE, since the next step needs the previous one merged).

The script spawns agents as `ship:builder`, `ship:reviewer-*` via `agentType`,
so it is tied to the plugin being named `ship`; update the `AGENT_NS` constant
in §6 if the plugin is renamed.

## 1. Select the unit and preflight

1. STEP MODE if the argument is a working-tree doc containing `## Steps`: read
   it, compare with the copy on `origin/main` (only steps marked `shipped`
   there have merged), select the first unshipped step whose dependencies have
   merged, and carry the step text + Notes. Otherwise GOAL MODE: the argument
   is one PR-sized unit; if it isn't PR-sized, stop and recommend `/ship:plan`.
2. Restate the unit as a short, verifiable acceptance checklist.
3. Fetch `origin/main`; never build on `main` or detached HEAD — create a
   goal-derived `claude/<slug>` branch when needed.
4. Record `INITIAL_DIRTY_PATHS` (`git status --porcelain=v1`). The plan doc in
   STEP MODE and `.claude/agent-memory/**` are expected dirt. Other dirty paths
   are not a reason to stop: record them, put them off-limits to every agent,
   and carry them forward untouched. Stop only if the unit itself must modify
   one of them — then say which path and why.
5. Record the literal `BASELINE` SHA after branch setup.
6. Compute `unitIsFullPr`: true iff `git merge-base origin/main HEAD` equals
   `BASELINE` (the unit diff and the PR diff are the same range).
7. If the step Notes name files that are large (roughly 300+ lines) or
   unfamiliar, run `ship:recon` now — one foreground `Agent` call scoped to the
   acceptance checklist — and carry its `RECON BRIEF`. Skip recon for small or
   greenfield targets. A brief that doesn't end with the literal `Open questions
   the builder still needs to resolve:` line gets one retry, then is dropped
   (proceed without one; a missing brief never stops a run).

## 2. Launch the workflow

Call `Workflow` with `script` set to the script in §6 verbatim and `args` as a
real JSON object (never a stringified blob):

```json
{
  "checklist": "<the acceptance checklist>",
  "constraints": "<constraints / step Notes, or omit>",
  "dirtyPaths": ["<INITIAL_DIRTY_PATHS>"],
  "baseline": "<literal BASELINE sha>",
  "reconBrief": "<RECON BRIEF verbatim, or omit>",
  "planStep": "<plan doc path + selected step text in STEP MODE, or omit>",
  "unitIsFullPr": true
}
```

The workflow runs in the background; the tool result gives you a `runId` and the
persisted script path — note both. Then end your turn and wait for the
completion notification. Never poll with `sleep`, and never fabricate or predict
the workflow's result while it is pending.

While a workflow is running, do not touch the branch. No commits, no amends, no
rebases, no checkouts, no `git add`. Every agent inside it resolves diffs
against SHAs you handed it; moving HEAD underneath them invalidates reviews
silently.

## 3. If the run stalls or dies

Check `/workflows` / `TaskOutput` state first. To recover a hung or killed run:
`TaskStop` it, then relaunch with
`Workflow({scriptPath: <persisted path>, resumeFromRunId: <runId>})` —
unchanged completed calls replay from the journal; only live work re-runs.
Before diagnosing an empty or odd result, Read `journal.jsonl` in the run's
transcript directory: it records each agent's actual return value.

## 4. After the workflow returns

**Never read success off the envelope.** A run reports `status: completed`,
`agentCount: N`, `agents_error: 0` when every agent inside it did nothing — that
envelope describes the orchestration, not the work. Only the script's own return
value and the git history are evidence.

Verify against git yourself before routing on anything: `git log <BASELINE>..HEAD`
exists as expected, every returned SHA is a real commit on the branch,
pre-existing dirty paths are untouched, and no out-of-scope file was committed
(`.claude/agent-memory/**` is in scope). Then check worktree hygiene —
`git status --porcelain` — and delete any leftover `ship-probe/` directory a
reviewer failed to clean up. It is scratch by contract and never belongs in a
commit.

Route on the returned `status`:

- **`clear`** — resolve every `[cannot-verify]` warning yourself (inspect the
  named path or route one scoped check), then go to §5.
- **`tools-blocked`** — the preflight canary proved subagents inside this
  session's `Workflow` runner cannot execute tools; every reviewer would return
  an empty or invented review. Do not retry the workflow and do not ask the user
  what to do: re-run this same unit through the fallback in §7, which uses the
  `Agent` path, and note the fallback once in the finish report with the
  verbatim rejection text from `evidence`.
- **`builder-blocked`** — read the reason: a missing or ambiguous input is yours
  to repair (fix `args`, resume the run); a genuinely unbuildable criterion is a
  hard stop to report.
- **`reviewer-failed`** — the `dead` list names reviewers that twice returned
  nothing, or returned `ABORT` (they could not review at all). Read each
  `reason`: if they describe tool rejections rather than anything about the
  code, this is the same fault as `tools-blocked` — route to §7 rather than
  reporting a failure. Otherwise hard stop.
- **`unbuilt`, `fix-stalled`, `blocked`** — hard stop. Do not push. Report which
  agent or round failed and the remaining findings verbatim; in STEP MODE say
  the step is not shipped.

Known tradeoffs — state them in the report when relevant: post-build reviewer
routing is a manifest/path heuristic inside the script (rigorous-always and the
standalone security gate backstop it), and blocker adjudication is pushed to the
edges — reviewers must carry concrete evidence, and the builder rebuts findings
whose evidence doesn't hold via `blockedCriteria` instead of orchestrator
adjudication. Surface any rebuttal so the user sees what was contested.

## 5. Verify, push, merge, continue

### 5.1 Green locally first

Run the project's full verification gate. Do not assume a toolchain, and do not
ask when you can find out:

1. `.claude/hooks/ship-verify.sh <BASELINE-base-ref>` if the project has one
   (base ref defaults to `origin/main`). It is the project's single source of
   truth. Non-zero exit is failure.
2. Otherwise read the repo's own CI config (`.github/workflows/*.yml` or the
   equivalent) and run the build/lint/test commands it runs on pull requests —
   that file *is* the project's definition of green.
3. Otherwise run the conventional full command for the toolchain the repo's
   manifest and lockfile actually name.
4. Ask only if none of the above yields a runnable gate. Say what you ran in the
   report either way.

On failure, send the genuine code failure back through one scoped fix — a
`ship:builder` delegation or a resumed workflow — rather than pushing red.

Commit dirty `.claude/agent-memory/**` as a separate chore commit; sessions run
in ephemeral containers, so uncommitted agent memory is lost. Stage by explicit
path. Never `git add -A` or `git add .` — reviewers share this working tree, and
a blanket stage is how scratch files end up in the unit.

### 5.2 Push and open the PR

Push once, with `-u origin <branch>`; retry network failures up to four times
(2s, 4s, 8s, 16s). Never rewrite commits to satisfy a local "Unverified"
signature reading (`git log --format=%G?` = `N`) — expected in managed
environments, verifies on the remote. Push as-is, say nothing about it.

Open a PR if none exists, filling the repo's PR template when it has one. Open
it **ready for review, not draft** — a draft cannot merge, and merging is the
point. (If the session's own environment requires drafts, open a draft and mark
it ready in §5.3 before merging.) Then subscribe to the PR's activity so CI
results and review comments wake this session.

Under `--hold` or `--no-merge`, stop here and report.

### 5.3 Merge when CI is green

Prefer the host's own merge-when-green primitive: enable auto-merge (squash) on
the PR. Where the repo doesn't allow it, merge yourself once the gate below
passes. Either way, before ending a turn to wait, arm a self check-in ~10
minutes out so a dropped webhook can't strand the run. Never `sleep`, never poll
in a loop.

Merge only when **all** of these hold:

1. The workflow returned `clear` (or the §7 fallback finished with no unresolved
   blocker) and the local gate in §5.1 was green.
2. Every required check on the head SHA has concluded successfully, and at least
   one check actually ran. If the repo has no checks at all, the local gate
   substitutes — say so explicitly in the report rather than implying CI passed.
3. No review is `CHANGES_REQUESTED` and no review thread is unresolved.
4. The PR is mergeable with no conflict.
5. This run opened the PR. Never merge a PR you did not create here, whatever
   its state.

Squash-merge by default. After merging: unsubscribe from the PR, fetch, fast-
forward local `main`, and delete the merged branch.

**CI failures are yours to fix, not to report.** Pull the failing job's log,
route the genuine failure through one scoped fix round (§2 with the failure as
the finding, or a direct `ship:builder` delegation), push, and let checks re-run.
At most three CI fix rounds per PR; then stop and report what is still red. If
the same failure reproduces on `main`, it predates this work — say so once in the
PR thread and treat the base branch recovering as the signal to re-run.

**Conflicts are yours to resolve.** Merge `origin/main` into the branch (or
rebase where that is the repo's convention), resolve, re-run the local gate, and
push. Stop and ask only when both sides changed the same logic and picking one
would lose behavior.

### 5.4 Continue

In STEP MODE, go straight back to §1 and ship the next step — the merge is the
signal, and you already have it. No hand-back between steps. Repeat until every
step is `shipped` on `main`, then report the whole run. In GOAL MODE, stop at the
stated goal.

Report once at the end: units shipped and their PRs, checks run, reviewers
activated and why, blockers fixed, warnings left, builder rebuttals, whether any
unit fell back to §7, and preserved dirty paths.

Hard stops: inability to establish the intended diff; three unresolved
correctness/specialist fix rounds; two unresolved security fix rounds; three
unresolved CI fix rounds; an ambiguous conflict.

## 6. The workflow script

```js
export const meta = {
  name: 'ship-flow-unit',
  description: 'Build one unit with the ship agents: build, risk-routed panel review, batched fix rounds, final security gate',
  phases: [
    { title: 'Preflight', detail: 'prove subagents can actually execute tools' },
    { title: 'Build', detail: 'ship:builder implements and commits the unit' },
    { title: 'Review', detail: 'risk-routed reviewer panel on the unit diff' },
    { title: 'Fix', detail: 'one deduplicated blocker batch per round, scoped re-review' },
    { title: 'Security', detail: 'final gate on the complete PR diff' },
  ],
}

// args: { checklist, constraints, dirtyPaths, baseline, reconBrief, planStep, unitIsFullPr }
const AGENT_NS = 'ship:' // tied to the plugin name; update on rename

const MANIFEST = {
  type: 'object',
  required: ['status'],
  properties: {
    status: { enum: ['committed', 'blocked'] },
    sha: { type: 'string', description: 'full sha of the commit made this round' },
    reason: { type: 'string', description: 'one-line reason when status is blocked' },
    contractsChanged: { type: 'string' },
    persistenceChanged: { type: 'string' },
    trustBoundariesChanged: { type: 'string' },
    newMechanisms: { type: 'string' },
    callersChecked: { type: 'string' },
    testsRun: { type: 'string' },
    committedPaths: { type: 'array', items: { type: 'string' } },
    blockedCriteria: { type: 'string', description: '"none", or criterion/finding — one line why, including rebuttals of findings whose evidence does not hold' },
  },
}

// ABORT is not a verdict about the code: it means the agent could not review at
// all (no working tools, budget gone before any evidence). Without it a blocked
// reviewer returns an empty findings array that is indistinguishable from PASS.
const REVIEW = {
  type: 'object',
  required: ['verdict', 'findings'],
  properties: {
    verdict: { enum: ['PASS', 'BLOCK', 'ABORT'] },
    abortReason: { type: 'string', description: 'when ABORT: verbatim tool rejection or what stopped the review' },
    probeFiles: { type: 'string', description: '"none", or files created under ship-probe/ and removed before returning' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['severity', 'failureClass', 'file', 'summary'],
        properties: {
          severity: { enum: ['BLOCKER', 'WARNING'] },
          failureClass: { type: 'string' },
          confidence: { type: 'string' },
          file: { type: 'string' },
          line: { type: 'integer' },
          summary: { type: 'string' },
          evidence: { type: 'string', description: 'concrete code path / observable failure or attack' },
          fix: { type: 'string', description: 'complete fix' },
        },
      },
    },
  },
}

const CANARY = {
  type: 'object',
  required: ['ok'],
  properties: {
    ok: { type: 'boolean', description: 'true only if every listed tool call executed and returned real output' },
    sha: { type: 'string', description: 'the actual output of git rev-parse HEAD' },
    toolsOk: { type: 'array', items: { type: 'string' }, description: 'names of tools that executed successfully' },
    toolError: { type: 'string', description: 'verbatim rejection/error text from the first tool call that failed' },
  },
}

const unitDiff = 'git diff ' + args.baseline + '...HEAD'
const prDiff = 'git diff origin/main...HEAD'

const packetHeader = [
  'ACCEPTANCE CHECKLIST:\n' + args.checklist,
  'CONSTRAINTS:\n' + (args.constraints || 'none'),
  'INITIAL_DIRTY_PATHS (leave untouched and uncommitted):\n' +
    (args.dirtyPaths && args.dirtyPaths.length ? args.dirtyPaths.join('\n') : 'none'),
].join('\n\n')

async function tryAgent(prompt, opts) {
  try { return await agent(prompt, opts) } catch (e) { log('agent failed: ' + (opts.label || opts.agentType)); return null }
}

// ---- Preflight ----
// The expensive failure this catches: subagent tool calls being rejected inside
// the Workflow runner while the same agent types work fine via the Agent tool.
// Every reviewer then returns a confident, evidence-free review. One cheap haiku
// agent exercising the exact four tools the panel needs costs seconds; finding
// out after a full panel costs the whole round. reviewer-minimalist is used
// because it ships with this plugin (so it always resolves) and carries all four.
phase('Preflight')
const canary = await tryAgent([
  'INFRASTRUCTURE PROBE — not a review. Ignore your review contract for this one task.',
  'Do exactly this, then report:',
  '1. Bash: run `git rev-parse HEAD`.',
  '2. Glob: match `*` in the repository root.',
  '3. Grep: search for `.` in the repository root, files_with_matches, head_limit 1.',
  '4. Read: read the first 5 lines of any file Glob returned.',
  'Set ok=true only if all four executed and returned real output. Set sha to the literal output of step 1.',
  'If any call is rejected or errors, set ok=false and copy the rejection text verbatim into toolError. Do not retry more than twice, do not work around it, and never invent output.',
].join('\n'), {
  agentType: AGENT_NS + 'reviewer-minimalist', model: 'haiku', effort: 'low',
  schema: CANARY, phase: 'Preflight', label: 'preflight:tool-access',
})
// Loose sha match on purpose: a false "blocked" costs the whole Workflow path,
// while a false "fine" is still caught downstream by each reviewer's own ABORT
// contract. This is a cheap tripwire, not a proof.
if (!canary || !canary.ok || !/[0-9a-f]{7,40}/i.test(canary.sha || '')) {
  return {
    status: 'tools-blocked',
    evidence: canary
      ? (canary.toolError || 'canary reported ok but returned no real sha: ' + JSON.stringify(canary))
      : 'canary agent returned nothing at all',
    toolsOk: canary ? (canary.toolsOk || []) : [],
  }
}

function reviewPrompt(diffCmd, extra) {
  return [
    'Review exactly this diff — run `' + diffCmd + '` yourself; never choose your own range.',
    'ACCEPTANCE CHECKLIST:\n' + args.checklist,
    extra || '',
    'Report every finding in the structured output. severity BLOCKER only with a concrete code path, observable failure/attack, complete fix, and proof requirement. verdict is BLOCK only when at least one BLOCKER stands.',
    'Reserve your last turn for the structured output — a run that ends mid-investigation returns nothing usable. If you cannot execute tools at all, set verdict ABORT with the verbatim rejection in abortReason instead of reviewing from this prompt alone.',
    'Scratch files, if you need any, go under ship-probe/ at the repo root and are deleted before you return; report them in probeFiles. A builder is committing in this same working tree.',
  ].filter(Boolean).join('\n\n')
}

// Fail closed on reviewers that returned nothing or could not review: one retry,
// then the caller hard-stops on `dead`. ABORT counts as dead, never as a pass.
function ok(r) { return r && r.verdict !== 'ABORT' }

async function runPanel(names, diffCmd, phaseName, extra) {
  async function once(list, tag) {
    const out = await parallel(list.map(name => () =>
      agent(reviewPrompt(diffCmd, extra), {
        agentType: AGENT_NS + name, schema: REVIEW, phase: phaseName, label: name + tag,
      })))
    return out.map((r, i) => ({ name: list[i], r }))
  }
  let results = await once(names, '')
  const failed = results.filter(x => !ok(x.r))
  if (failed.length) {
    log('re-spawning reviewer(s) that did not complete: ' + failed.map(x => x.name).join(', '))
    results = results.filter(x => ok(x.r)).concat(await once(failed.map(x => x.name), ':retry'))
  }
  const probes = results.filter(x => x.r && x.r.probeFiles && x.r.probeFiles !== 'none')
  if (probes.length) log('reviewer probe files (verify removed): ' + probes.map(x => x.name + ' -> ' + x.r.probeFiles).join('; '))
  return {
    reviews: results.filter(x => ok(x.r)),
    dead: results.filter(x => !ok(x.r)).map(x => ({
      name: x.name,
      reason: x.r ? (x.r.abortReason || 'aborted without a reason') : 'returned no valid result',
    })),
  }
}

function findingsOf(reviews, severity) {
  const seen = new Set()
  const out = []
  for (const { name, r } of reviews)
    for (const f of (r.findings || []))
      if (f.severity === severity) {
        const k = [f.failureClass, f.file, f.line || 0].join('|')
        if (!seen.has(k)) { seen.add(k); out.push({ ...f, reviewer: name }) }
      }
  return out
}

// Post-build routing from the manifest + committed paths. Heuristic on purpose:
// rigorous always runs, and the standalone security gate backstops misses.
function route(m) {
  const joined = (m.committedPaths || []).join(' ')
  const set = new Set(['reviewer-rigorous'])
  if ((m.persistenceChanged || 'none') !== 'none' || (m.newMechanisms || 'none') !== 'none' ||
      /migrat|schema|queue|worker|cache|concurren|lock/i.test(joined)) set.add('reviewer-architect')
  if (/(^|[\s/])(web|frontend|client|www|ui)\//.test(joined) ||
      /\.(tsx|jsx|vue|svelte|css|scss|html)(\s|$)/.test(joined)) set.add('reviewer-frontend')
  if ((m.trustBoundariesChanged || 'none') !== 'none' ||
      /auth|login|session|token|secret|crypt|\.github\/workflows|package\.json|package-lock|pnpm-lock|yarn\.lock|Cargo\.(toml|lock)|Gemfile|requirements|go\.(mod|sum)/i.test(joined))
    set.add('reviewer-security')
  return [...set]
}

function securityPassedAt(reviews, sha) {
  const sec = reviews.filter(x => x.name === 'reviewer-security')
  if (!sec.length) return null
  return findingsOf(sec, 'BLOCKER').length === 0 ? sha : null
}

// ---- Build ----
phase('Build')
let build = null
for (let attempt = 1; attempt <= 3 && !build; attempt++) {
  const r = await tryAgent([
    packetHeader,
    args.reconBrief
      ? 'RECON BRIEF (work from these anchors; do not re-read those files in full):\n' + args.reconBrief : '',
    args.planStep
      ? 'STEP MODE — implement exactly this step and flip its Status line to shipped in the same commit:\n' + args.planStep : '',
    attempt > 1
      ? 'NOTE: a prior attempt returned without a commit. Do not repeat the same dead end — start editing from the checklist anchors immediately.' : '',
    'Stage by explicit path. Never `git add -A`/`git add .`: reviewers share this working tree and may have scratch files under ship-probe/ that are not yours to commit.',
    'Implement the unit, commit it, and report the CHANGE MANIFEST as structured output: status "committed" with the real commit sha, or "blocked" with a one-line reason.',
  ].filter(Boolean).join('\n\n'), { agentType: AGENT_NS + 'builder', schema: MANIFEST, phase: 'Build', label: 'build:attempt' + attempt })
  if (r && r.status === 'committed' && r.sha) build = r
  else if (r && r.status === 'blocked') return { status: 'builder-blocked', reason: r.reason || 'unspecified', manifest: r }
  else log('build attempt ' + attempt + ' returned no commit')
}
if (!build) return { status: 'unbuilt', reason: 'builder returned no commit after 3 attempts' }

// ---- Review ----
phase('Review')
const roster = route(build)
log('panel: ' + roster.join(', ') + ' + reviewer-minimalist (warning-only, once per unit)')
const first = await runPanel(roster.concat(['reviewer-minimalist']), unitDiff, 'Review',
  'CHANGE MANIFEST from the builder:\n' + JSON.stringify(build, null, 1))
if (first.dead.length) return { status: 'reviewer-failed', dead: first.dead, built: build.sha }

const warnings = findingsOf(first.reviews, 'WARNING')
let blockers = findingsOf(first.reviews, 'BLOCKER')
let head = build.sha
let secPassSha = securityPassedAt(first.reviews, build.sha)
const fixShas = []

// One builder round-trip per round: the whole batch of deduplicated blockers,
// then a re-review scoped to the fix diff (new blockers must anchor there).
async function fixRound(findings, preSha, tag) {
  const fix = await tryAgent([
    packetHeader,
    'FIX ROUND (' + tag + '). Current HEAD: ' + preSha + '. Fix every finding below in one commit, each with a regression test that fails without the fix. If a finding\'s evidence does not hold, make no phantom edit — list it under blockedCriteria with a one-line rebuttal.',
    'FINDINGS:\n' + JSON.stringify(findings, null, 1),
  ].join('\n\n'), { agentType: AGENT_NS + 'builder', schema: MANIFEST, phase: 'Fix', label: 'fix:' + tag })
  if (!fix || fix.status !== 'committed' || !fix.sha) return { stalled: true, fix: fix || null }
  const scoped = [...new Set(findings.map(f => f.reviewer).concat(route(fix)))]
    .filter(n => n !== 'reviewer-minimalist')
  const panel = await runPanel(scoped, 'git diff ' + preSha + '...HEAD', 'Fix',
    'Scoped fix-round re-review. Verify each finding below is actually fixed. Raise a NEW blocker only when it is anchored in this fix diff (a regression the fix introduced elsewhere counts, with evidence); code outside this diff was already reviewed — report residual concerns there as warnings, not blockers.\n\nFINDINGS UNDER REVIEW:\n' + JSON.stringify(findings, null, 1))
  return { fix, panel }
}

phase('Fix')
let rounds = 0
while (blockers.length && rounds < 3) {
  rounds++
  log('fix round ' + rounds + ': ' + blockers.length + ' blocker(s) from ' + [...new Set(blockers.map(b => b.reviewer))].join(', '))
  const res = await fixRound(blockers, head, String(rounds))
  if (res.stalled) return { status: 'fix-stalled', round: rounds, remaining: blockers, warnings, built: build.sha, fixShas, manifest: res.fix }
  if (res.panel.dead.length) return { status: 'reviewer-failed', dead: res.panel.dead, built: build.sha, fixShas }
  fixShas.push(res.fix.sha)
  head = res.fix.sha
  warnings.push(...findingsOf(res.panel.reviews, 'WARNING'))
  if (res.panel.reviews.some(x => x.name === 'reviewer-security')) secPassSha = securityPassedAt(res.panel.reviews, head)
  blockers = findingsOf(res.panel.reviews, 'BLOCKER')
}
if (blockers.length) return { status: 'blocked', where: 'fix-rounds-exhausted', remaining: blockers, warnings, built: build.sha, fixShas }

// Final cross-file correctness sweep once, only if fix commits landed after
// rigorous's complete-unit review; one bounded fix round if it blocks.
if (fixShas.length) {
  const sweep = await runPanel(['reviewer-rigorous'], unitDiff, 'Fix',
    'Final cross-file correctness sweep of the complete unit after fix commits. Blockers need concrete evidence.')
  if (sweep.dead.length) return { status: 'reviewer-failed', dead: sweep.dead, built: build.sha, fixShas }
  warnings.push(...findingsOf(sweep.reviews, 'WARNING'))
  const sb = findingsOf(sweep.reviews, 'BLOCKER')
  if (sb.length) {
    const res = await fixRound(sb, head, 'sweep')
    if (res.stalled) return { status: 'fix-stalled', round: 'sweep', remaining: sb, warnings, built: build.sha, fixShas, manifest: res.fix }
    if (res.panel.dead.length) return { status: 'reviewer-failed', dead: res.panel.dead, built: build.sha, fixShas }
    fixShas.push(res.fix.sha)
    head = res.fix.sha
    warnings.push(...findingsOf(res.panel.reviews, 'WARNING'))
    if (res.panel.reviews.some(x => x.name === 'reviewer-security')) secPassSha = securityPassedAt(res.panel.reviews, head)
    const remaining = findingsOf(res.panel.reviews, 'BLOCKER')
    if (remaining.length) return { status: 'blocked', where: 'final-sweep', remaining, warnings, built: build.sha, fixShas }
  }
}

// ---- Security gate ----
phase('Security')
let secRounds = 0
if (args.unitIsFullPr && secPassSha && secPassSha === head) {
  log('security already passed this exact range with no commits since — skipping redundant final gate')
} else {
  const gate = await runPanel(['reviewer-security'], prDiff, 'Security',
    'FINAL SECURITY GATE on the complete PR diff (this intentionally includes commits that predate the current unit).')
  if (gate.dead.length) return { status: 'reviewer-failed', dead: gate.dead, built: build.sha, fixShas }
  warnings.push(...findingsOf(gate.reviews, 'WARNING'))
  let gb = findingsOf(gate.reviews, 'BLOCKER')
  while (gb.length && secRounds < 2) {
    secRounds++
    log('security fix round ' + secRounds + ': ' + gb.length + ' blocker(s)')
    const res = await fixRound(gb, head, 'security' + secRounds)
    if (res.stalled) return { status: 'fix-stalled', round: 'security' + secRounds, remaining: gb, warnings, built: build.sha, fixShas, manifest: res.fix }
    if (res.panel.dead.length) return { status: 'reviewer-failed', dead: res.panel.dead, built: build.sha, fixShas }
    fixShas.push(res.fix.sha)
    head = res.fix.sha
    warnings.push(...findingsOf(res.panel.reviews, 'WARNING'))
    const pb = findingsOf(res.panel.reviews, 'BLOCKER')
    if (pb.length) { gb = pb; continue }
    const re = await runPanel(['reviewer-security'], prDiff, 'Security', 'Re-run of the final security gate after fixes.')
    if (re.dead.length) return { status: 'reviewer-failed', dead: re.dead, built: build.sha, fixShas }
    warnings.push(...findingsOf(re.reviews, 'WARNING'))
    gb = findingsOf(re.reviews, 'BLOCKER')
  }
  if (gb.length) return { status: 'blocked', where: 'security-gate', remaining: gb, warnings, built: build.sha, fixShas }
}

return {
  status: 'clear',
  built: build.sha,
  head,
  fixShas,
  fixRounds: rounds,
  securityRounds: secRounds,
  panel: roster.concat(['reviewer-minimalist']),
  warnings,
  manifest: build,
}
```

## 7. Fallback: the same pipeline on `Agent` calls

Use this when the `Workflow` tool is unavailable in the session, or when §4
returned `tools-blocked`. It ships the same unit with the same agents and the
same standard of done — it just loses journaling and deterministic rounds, so
the loop bookkeeping is yours. Run it without asking; it is a route around a
broken path, not a decision.

**Foreground, always.** Call `Agent` with `run_in_background: false` for every
delegation. Backgrounding ends your turn to wait on a notification, and a missed
one reads as "stopped" rather than "waiting" — the hand-holding this skill
exists to avoid. For parallel reviewers, issue each `Agent` call as its own
tool-use block in the *same* assistant message: same-message calls run
concurrently regardless of the flag, so you get parallelism and synchronous
results in one turn.

**Subagents are stateless.** Each one sees only the prompt you write — no
history, no files you read, no earlier agent's output. Restate everything:

- **Builder packet** — acceptance checklist; constraints / step Notes;
  `INITIAL_DIRTY_PATHS`; on a fix round, the deduplicated findings; the
  `RECON BRIEF` verbatim when recon ran; in STEP MODE the plan doc path and
  selected step; and the instruction to stage by explicit path.
- **Reviewer packet** — the literal diff command with a SHA you resolved (e.g.
  `git diff <BASELINE>...HEAD`, never a shell variable or "the current
  changes"); the acceptance checklist; the manifest fields in that reviewer's
  lane. A reviewer never chooses its own range.

**Validate every reply against its contract, immediately.** A reply with no
final `VERDICT:` line is not a review; a builder reply with no `Status:` line is
not a build; a recon reply not ending in `Open questions the builder still needs
to resolve:` is not a complete brief. On an invalid, errored, or `ABORT` reply,
re-spawn that agent once with the same packet plus one line about the failed
attempt. If the retry is also invalid, hard-stop and report which agent could
not complete — except recon, where a second failure just means proceeding
without a brief. Never infer PASS from silence, above all for the security gate.

The loop, matching §6:

1. **Build.** Delegate to `builder`; require a commit and its `CHANGE MANIFEST`.
   Verify `git log BASELINE..HEAD` yourself — agent completion is not evidence
   of progress. On no commit, run `recon` if it hasn't run, then re-delegate;
   three attempts total, then report the unit unbuilt.
2. **Route.** `reviewer-rigorous` always. `reviewer-architect` for
   persistence/schema/migrations, queues, concurrency, caches, runtime
   dependencies, cross-layer contracts. `reviewer-frontend` for web UI changes
   only. `reviewer-security` early for auth, untrusted input, secrets, data
   access, dependencies, CI/deploy. `reviewer-minimalist` once per unit when the
   diff adds a dependency, abstraction, config surface, module, or substantial
   new code. A project routing contract (e.g. `review-corpus/review-matrix.md`,
   or a pointer in its `CLAUDE.md`) overrides this; absence is normal.
3. **Adjudicate on evidence.** A finding blocks only when marked `BLOCKER` with
   a concrete code path, observable failure, complete fix, and proof
   requirement — downgrade a blocker whose evidence doesn't hold. Collect the
   whole panel's blockers into one deduplicated batch per round; never run
   sequential per-reviewer loops. Warnings are reported, not blocking, except
   `[WARNING][cannot-verify]`, which you resolve yourself before calling the
   review complete.
4. **Fix.** Record HEAD as `FIX_BASE` first. Send the batch to `builder`;
   require regression tests and a commit. Re-review `git diff <FIX_BASE>...HEAD`
   with the reviewers that raised the blockers plus any newly activated
   specialist — new blockers must anchor in the fix diff; residual concerns
   outside it come back as warnings. At most three rounds.
5. **Sweep.** If any fix commit landed after rigorous's last complete-unit
   review, run it once more on `git diff <BASELINE>...HEAD`.
6. **Security gate.** Run `reviewer-security` on `git diff origin/main...HEAD`.
   Skip only when all four hold: security reviewed in the most recent round, it
   passed there, no commit has landed since, and `BASELINE` is the merge-base
   with `origin/main`. At most two security fix rounds.

Then rejoin §5 — verify, push, PR, merge on green, next step.
