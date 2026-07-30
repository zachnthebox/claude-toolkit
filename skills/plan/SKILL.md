---
name: plan
description: Draft a step-structured spec doc that /ship:flow ships one step at a time, merging each before starting the next
argument-hint: 'feature or goal to plan'
disable-model-invocation: true
---
Goal to plan: $ARGUMENTS

Produce a spec doc in `docs/` that `/ship:flow` can drive **one
independently-shippable step at a time**. `/ship:flow` builds, reviews,
merges, and moves to the next step without stopping, so the step list you
write here is the whole run's plan — get the ordering and the acceptance
criteria right. You are planning, not building — write no feature code.

## 1. Ground the plan in the codebase

Read the project's `CLAUDE.md` and its `docs/` RFCs or decision log when
present — absence is normal — then the code the feature touches (use the
`Explore` subagent for a broad sweep, foreground, since its findings shape
the steps you write next). The plan must fit the project's actual layering —
and its dependency seam where one exists; don't invent one for a project
without it — and preserve its security/data invariants, from `CLAUDE.md`
when present, otherwise from the conventions the code practices. Note which
invariants each step must preserve.

## 2. Carve the work into shippable steps

A step is the unit `/ship:flow` builds, reviews, and merges as **one PR**:

- **Independently shippable** — each leaves `main` working, tested, and
  releasable. No step depends on a later one.
- **Small** — roughly one focused PR (a migration + its read/write path; a
  new input path + its validation and security test). More than a handful of
  acceptance criteria means split it.
- **Ordered by dependency and risk** — foundations first; dependencies
  explicit so `/ship:flow` can gate on them.

Default to the **fewest steps that work**. Every step costs a full
build/review/merge cycle, so start from "can this be one step?" and add one
only when something forces the split: a hard merge dependency, a risk
boundary worth its own review, or a PR too large to review meaningfully.
Never split by layer or file type — "models, then services, then UI" is one
step, not three. Apply YAGNI: no steps for scale the system won't reach;
genuinely deferred work is a later step or a Non-goals note.

## 3. Write the doc

Markdown hygiene (many repos lint it in CI): tag every fenced block with a
language, no trailing whitespace, single trailing newline.

Create `docs/<slug>.md` (kebab-case from the goal). Open with a
`> **Status:** Proposed` header, then **Goals / non-goals**, then enough
**design** for a builder to act without re-deriving it — data model, the
seam each change lands on, invariants to keep.

Then a `## Steps` section in EXACTLY this shape, so `/ship:flow` can parse
it:

```markdown
## Steps

Each step is one independently-shippable PR. `/ship:flow <this doc>` ships
the first step whose Status is not `shipped`, merges its PR once CI is
green, then continues to the next. Do not reorder steps after shipping
starts.

### Step 1 — <short imperative title>
- **Status:** not started   <!-- not started | in progress | shipped -->
- **Depends on:** —          <!-- none, or step numbers that must merge first -->
- **Acceptance:**
  - <concrete, independently verifiable outcome>
  - <another — keep the list short; past ~5, split the step>
- **Notes:** <optional — only a non-obvious heads-up the Acceptance can't
  carry. Omit the line otherwise.>

### Step 2 — <short imperative title>
- **Status:** not started
- **Depends on:** 1
- **Acceptance:**
  - ...
```

Keep it to those fields. Don't pre-list the files a step touches — the
builder finds its own blast radius, and a hand-maintained list rots. Don't
restate project invariants per step — the always-on correctness reviewer and
the security gate enforce them on every diff. Acceptance is the spec; Notes
is for the rare thing it can't express.

## 4. Hand off

Report the step list (titles, one line on the ordering, and what forces each
split) and the doc path. Do not start building — tell the user to run
`/ship:flow docs/<slug>.md`. The doc does not need to be committed first:
`/ship:flow` reads it from the working tree, and step 1's PR is what lands
it on `main`.

Because that run is unattended once it starts, raise anything the user
should decide *now*: a real go/no-go risk, an open question only they can
resolve, a step whose acceptance criteria you had to guess. A wrong
assumption caught here costs a sentence; caught after four merged PRs it
costs a revert.
