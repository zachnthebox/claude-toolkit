---
name: flow
description: Experimental /ship:it variant on the Workflow runner — deterministic build/review/fix loops that resume from a journal instead of going stale
argument-hint: 'goal, or path to a spec doc with a "## Steps" section'
disable-model-invocation: true
---
Goal: $ARGUMENTS

"The argument" throughout this skill means the input you were invoked with —
either a goal to ship (GOAL MODE), or a path to a spec doc containing a
"## Steps" section (STEP MODE).

This is the experimental Workflow-runner variant of `/ship:it`. The standard of
done is identical — satisfied acceptance criteria, meaningful tests, reviewed
code, green final checks, project invariants intact — but the build → review →
fix loop runs inside one `Workflow` script instead of a chain of foreground
`Agent` calls. What that buys:

- **No stale runs.** Every agent result is journaled. If the run hangs, dies,
  or the container restarts, you resume it with `resumeFromRunId` and the
  completed prefix replays instantly from cache — hours of build/review work
  are never redone, and nobody has to manually re-kick a builder.
- **Deterministic rounds.** Fix-loop counts, dedup, scoped re-review rosters,
  and fail-closed handling of dead agents are plain JavaScript, not orchestrator
  judgment applied consistently over a long context.

If the `Workflow` tool is not available in the session, say so and run
`/ship:it` instead — do not half-emulate this file with raw `Agent` calls.

The script spawns agents as `ship:builder`, `ship:reviewer-*` via `agentType`,
so like `/ship:it` it is tied to the plugin being named `ship`; update the
`AGENT_NS` constant in the script if the plugin is renamed.

## 1. Select the unit and preflight (inline, before the workflow)

Same rules as `/ship:it` §0–§1, condensed:

1. STEP MODE if the argument is a working-tree doc containing `## Steps`: read
   it, compare with the copy on `origin/main` (only steps marked `shipped`
   there have merged), select the first unshipped step whose dependencies have
   merged, and carry the step text + Notes. Otherwise GOAL MODE: the argument
   is one PR-sized unit; if it isn't PR-sized, stop and recommend `/ship:plan`.
2. Restate the unit as a short, verifiable acceptance checklist.
3. Fetch `origin/main`; never build on `main` or detached HEAD — create a
   goal-derived `claude/<slug>` branch when needed.
4. Record `INITIAL_DIRTY_PATHS` (`git status --porcelain=v1`). The plan doc in
   STEP MODE and `.claude/agent-memory/**` are expected dirt; any other dirty
   path must be explicitly in scope or the run stops with the path list.
5. Record the literal `BASELINE` SHA after branch setup.
6. Compute `unitIsFullPr`: true iff `git merge-base origin/main HEAD` equals
   `BASELINE` (the unit diff and the PR diff are the same range).
7. If the step Notes name files that are large (roughly 300+ lines) or
   unfamiliar, run `ship:recon` now — one foreground `Agent` call scoped to the
   acceptance checklist — and carry its `RECON BRIEF`. Skip recon for small or
   greenfield targets. Apply `/ship:it`'s validity rule: a brief that doesn't
   end with the literal `Open questions the builder still needs to resolve:`
   line gets one retry, then is dropped.

## 2. Launch the workflow

Call `Workflow` with `script` set to the script in §5 verbatim and `args` as a
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

The workflow runs in the background; the tool result gives you a `runId` and
the persisted script path — note both. Then end your turn and wait for the
completion notification. Never poll with `sleep`, and never fabricate or
predict the workflow's result while it is pending.

## 3. If the run stalls or dies

When the user nudges a quiet run, check `/workflows` / `TaskOutput` state
first. To recover a hung or killed run: `TaskStop` it, then relaunch with
`Workflow({scriptPath: <persisted path>, resumeFromRunId: <runId>})` —
unchanged completed calls replay from the journal; only live work re-runs.
Before diagnosing an empty or odd result, Read `journal.jsonl` in the run's
transcript directory — it records each agent's actual return value.

## 4. After the workflow returns

First, whatever the returned status claims, verify against git yourself:
`git log <BASELINE>..HEAD` exists as expected, every returned SHA is a real
commit on the branch, pre-existing dirty paths are untouched, and no
out-of-scope file was committed (`.claude/agent-memory/**` is in scope). Never
take the workflow's word for a commit.

Then route on `status`:

- **`clear`** — resolve every `[cannot-verify]` warning yourself (inspect the
  named path or route one scoped check) before treating review as complete,
  then finish exactly like `/ship:it` §5: run
  `.claude/hooks/ship-verify.sh <BASELINE-base-ref>` (or detect the project's
  conventional full gate, or ask — never assume a toolchain); on failure send
  the genuine code failure back through one scoped fix (a `ship:builder`
  delegation or a resumed workflow) rather than pushing red. Once green: push
  the branch once, open a PR if none exists, and report — unit shipped, checks
  run, panel + rounds actually run, blockers fixed, warnings left, builder
  rebuttals recorded under `blockedCriteria`, dirty paths preserved. Never
  rewrite commits to satisfy a local "Unverified" signature reading; push
  as-is and don't mention it.
- **`builder-blocked`** — read the reason: a missing or ambiguous input is
  yours to repair (fix `args`, resume the run); a genuinely unbuildable
  criterion is a hard stop to report.
- **`unbuilt`, `reviewer-failed`, `fix-stalled`, `blocked`** — hard stop. Do
  not push. Report which agent or round failed and the remaining findings
  verbatim; in STEP MODE tell the user the step is not shipped.

Known tradeoffs vs `/ship:it` — state them in the report when relevant: the
post-build reviewer routing is a manifest/path heuristic inside the script
(rigorous-always and the standalone security gate backstop it), and blocker
adjudication is pushed to the edges — reviewers must carry concrete evidence,
and the builder rebuts findings whose evidence doesn't hold via
`blockedCriteria` instead of orchestrator adjudication. Surface any rebuttal
in the report so the user sees what was contested.

## 5. The workflow script

```js
export const meta = {
  name: 'ship-flow-unit',
  description: 'Build one unit with the ship agents: build, risk-routed panel review, batched fix rounds, final security gate',
  phases: [
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

const REVIEW = {
  type: 'object',
  required: ['verdict', 'findings'],
  properties: {
    verdict: { enum: ['PASS', 'BLOCK'] },
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

function reviewPrompt(diffCmd, extra) {
  return [
    'Review exactly this diff — run `' + diffCmd + '` yourself; never choose your own range.',
    'ACCEPTANCE CHECKLIST:\n' + args.checklist,
    extra || '',
    'Report every finding in the structured output. severity BLOCKER only with a concrete code path, observable failure/attack, complete fix, and proof requirement. verdict is BLOCK only when at least one BLOCKER stands.',
  ].filter(Boolean).join('\n\n')
}

// Fail closed on dead reviewers: one retry, then the caller hard-stops on `dead`.
async function runPanel(names, diffCmd, phaseName, extra) {
  async function once(list, tag) {
    const out = await parallel(list.map(name => () =>
      agent(reviewPrompt(diffCmd, extra), {
        agentType: AGENT_NS + name, schema: REVIEW, phase: phaseName, label: name + tag,
      })))
    return out.map((r, i) => ({ name: list[i], r }))
  }
  let results = await once(names, '')
  const failed = results.filter(x => !x.r).map(x => x.name)
  if (failed.length) {
    log('re-spawning failed reviewer(s): ' + failed.join(', '))
    results = results.filter(x => x.r).concat(await once(failed, ':retry'))
  }
  return {
    reviews: results.filter(x => x.r),
    dead: results.filter(x => !x.r).map(x => x.name),
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
