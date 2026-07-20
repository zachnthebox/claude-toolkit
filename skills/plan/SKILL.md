---
name: plan
description: Draft a step-structured spec doc that /ship:it builds one shippable step at a time
argument-hint: 'feature or goal to plan'
disable-model-invocation: true
---
Goal to plan: $ARGUMENTS

"The argument" throughout this skill means the input you were invoked with — the
feature or goal to plan.

Produce a spec doc in `docs/` that `/ship:it` can drive **one independently-shippable
step at a time**. You are planning, not building — write no feature code.

## 1. Ground the plan in the codebase
Before proposing steps, understand what exists. Read the project's `CLAUDE.md`
and its `docs/` RFCs / decision log when present — absence is normal — then the
code the feature touches (use the `Explore` or `Plan` subagent for a broad sweep
if the surface is large). Its findings shape the steps you write next, so call it
with `run_in_background: false` — backgrounding it hands continuation to a
notification hop instead of the same turn, and a missed or delayed one leaves the
run looking stalled until a human nudges it. The plan must fit the project's
actual layering — and its dependency seam where one exists (visible in how tests
substitute fakes); don't invent one for a project without it — and preserve its
security/data invariants, sourced from `CLAUDE.md` when present, otherwise from
the conventions the code itself practices. Note which invariants each step must
preserve.

## 2. Carve the work into shippable steps
A step is the unit `/ship:it` builds, reviews, and merges as **one PR**. Good steps:
- **Independently shippable** — each leaves `main` working, tested, and releasable
  on its own. No step depends on a later one.
- **Small** — roughly one focused PR's worth (a migration + its read/write path; a
  new external-input path + its validation/security test). If a step needs more
  than a handful of acceptance criteria, split it.
- **Ordered by dependency and risk** — foundations before things that lean on them;
  low-risk wins early. Make dependencies explicit so `/ship:it` can gate on them.
- **Right-sized** — apply YAGNI. Don't add steps for scale the system won't reach;
  mark genuinely-deferred work as a later step or a "Non-goals" note, not step 1.

Default to the **fewest steps that work**. Every step costs a full
build/review/merge cycle, so start from "can this be one step?" and add a step
only when something forces the split: a hard merge dependency (schema before
backfill), a risk boundary worth isolating behind its own review, or a PR too
large to review meaningfully. Never split by layer or file type — "models, then
services, then UI" is one step, not three. A step you can't justify splitting
gets merged into its neighbor.

## 3. Write the doc
Markdown hygiene so the doc lands clean (many repos lint Markdown in CI): tag
every fenced code block with a language (` ```markdown `, ` ```ts `, ` ```bash `),
no trailing whitespace, end the file with a single newline.

Create `docs/<slug>.md` (kebab-case slug from the goal). Open with:
- A `> **Status:** Proposed` header (lifecycle: Proposed → Accepted → Implemented;
  the per-step `Status:` lines track shipping progress).
- **Goals / non-goals**, then enough **design** for a builder to act without
  re-deriving it — data model, the seam each change lands on, invariants to keep.

Then a `## Steps` section in EXACTLY this shape, so `/ship:it` can parse it. Use the
canonical `Status: not started` for every step at authoring time:

```markdown
## Steps

Each step is one independently-shippable PR. `/ship:it <this doc>` builds the first
step whose Status is not `shipped`, then stops; merging its PR is the signal to
ship the next. Do not reorder steps after shipping starts.

### Step 1 — <short imperative title>
- **Status:** not started   <!-- not started | in progress | shipped (#PR) -->
- **Depends on:** —          <!-- none, or step numbers that must merge first -->
- **Acceptance:**
  - <concrete, independently verifiable outcome>
  - <another — keep the list short; if it grows past ~5, split the step>
- **Notes:** <optional — only a non-obvious heads-up the Acceptance can't carry,
  e.g. "touches the SSRF guard, keep it on the project's safe fetcher". Omit the
  line otherwise.>

### Step 2 — <short imperative title>
- **Status:** not started
- **Depends on:** 1
- **Acceptance:**
  - ...
```

Keep it to those fields. Don't pre-list the files a step touches — the builder
finds its own blast radius by grepping callers, a hand-maintained file list just
rots and can anchor it to the wrong set. Don't restate project invariants per
step either — the always-on correctness reviewer (`reviewer-rigorous`) and the
final security gate enforce them on every diff, and `/ship:it` risk-routes the other
specialists to the surfaces that need them. Acceptance is the spec; Notes is for
the rare thing it can't express.

## 4. Hand off
Report the step list (titles, a one-line rationale for the ordering, and — for
any plan with more than one step — what forces each split) and the doc path. Do not start building — tell the user to run `/ship:it docs/<slug>.md` to ship
step 1, then merge to advance. The doc does **not** need to be committed or merged
first: `/ship:it` reads the plan from the working tree, and step 1's PR is what lands
this doc on `main` (with step 1 flipped to `shipped`). If the codebase research
surfaced a real go/no-go risk or an open question only the user can resolve, call
it out before they start.
