# claude-toolkit

A personal [Claude Code](https://code.claude.com/docs) plugin — the same
shipping workflow and reviewer panel, installable across every project by
cloning it into your skills directory during environment setup.

## What's inside

Plugin **`ship`**. Plugin components are namespaced by the plugin name, so you
invoke everything as `ship:…` — a short, meaningful namespace that reads as a
phrase with each invocation.

- **Skills** — `/ship:flow` (the entrypoint: build, risk-routed review, fix
  loops, security gate, push, PR, merge on green CI — then straight on to the
  next step) and `/ship:plan` (draft a step-structured spec doc that
  `/ship:flow` ships one step at a time).
- **Agents** — `ship:builder` (implements the work), `ship:recon` (read-only
  scout that bounds the builder's reads on large/unfamiliar files), and the
  reviewer panel: `ship:reviewer-rigorous`, `ship:reviewer-architect`,
  `ship:reviewer-frontend`, `ship:reviewer-minimalist`, `ship:reviewer-security`.

## How a run goes

```text
/ship:flow docs/my-feature.md
```

`/ship:flow` picks the first unshipped step, builds it with `ship:builder`,
routes a reviewer panel at the diff, batches every blocker into one fix round,
runs the security gate on the full PR diff, runs the project's verify gate,
pushes, opens the PR, waits for CI, merges on green — then goes back for the
next step. One invocation ships the whole plan.

It runs unattended by design. It stops to ask only when proceeding would be
unsafe under every reading: an ambiguous merge conflict, an unbuildable
acceptance criterion, an unresolved security blocker, or an exhausted fix loop.
CI failures and merge conflicts are its own to fix, not yours to triage.

Append `--hold` to stop once the PR is open, or `--no-merge` to never merge.
Both are opt-in; the default is to finish.

The build/review/fix loop runs inside one `Workflow` script, so agent results
are journaled — a hung run resumes from cache with `resumeFromRunId` instead of
redoing hours of work. Where the `Workflow` runner is unavailable or its
subagents can't execute tools, a preflight canary detects it in seconds and the
same pipeline runs on plain `Agent` calls instead, without asking.

The entrypoints are **skills**, not plugin slash-commands. That's deliberate:
Claude Code on the web surfaces a skills-dir plugin's *skills and agents* but
not its `commands/`, so a `commands/*.md` entrypoint is invisible there while a
skill loads on the web *and* the desktop/CLI. They stay user-invoke-only
(`disable-model-invocation`) — only you trigger a deploy-class run; Claude never
auto-fires one.

## Install (headless / setup script)

Clone this repo into your skills directory. Claude Code auto-discovers any folder
under `~/.claude/skills/` that has a `.claude-plugin/plugin.json` and loads it as
a full plugin (`ship@skills-dir`) — skills and agents included — on the next
session. No interactive `/plugin` command required.

```bash
git clone https://github.com/zachnthebox/claude-toolkit ~/.claude/skills/claude-toolkit
```

Update later with a plain `git pull` in that directory.

### Optional: concise output everywhere

The `ship` skills and agents already keep their own output lean. To apply the
same concise, outcome-first style to *every* Claude Code session — not just
`ship:…` runs — append the stanza in
[`examples/concise-style.md`](./examples/concise-style.md) to your personal
`~/.claude/CLAUDE.md` as part of environment setup:

```bash
cat ~/.claude/skills/claude-toolkit/examples/concise-style.md >> ~/.claude/CLAUDE.md
```

This is opt-in on purpose: `~/.claude/CLAUDE.md` is your personal, all-projects
config, so cloning the toolkit never edits it for you. (Output tokens cost ~5×
input, so trimming filler is where verbosity savings actually land.)

## Install (interactive, optional)

If you prefer the plugin UI in a normal session, this repo also works as a
single-plugin install:

```text
/plugin install zachnthebox/claude-toolkit
```

## Per-project setup: the verify gate

`/ship:flow` is toolchain-agnostic. Its final build/lint/test gate does not assume
`npm` (or any tool) — instead it runs a script the project provides:

```text
.claude/hooks/ship-verify.sh <base-ref>   # base-ref defaults to origin/main
```

That script is the project's single source of truth for a full build, lint, and
test run. A non-zero exit blocks the push and feeds `/ship:flow`'s
builder/reviewer fix loop. Copy-paste starting points live in
[`examples/`](./examples):

- [`examples/ship-verify.node.sh`](./examples/ship-verify.node.sh)
- [`examples/ship-verify.ios.sh`](./examples/ship-verify.ios.sh)
- [`examples/ship-verify.rust.sh`](./examples/ship-verify.rust.sh)

Drop one into `.claude/hooks/ship-verify.sh`, `chmod +x`, and adjust for the
project. Without one, `/ship:flow` reads the repo's own CI workflow and runs what
it runs on pull requests — that file is the project's real definition of green —
falling back to the conventional command for whatever toolchain the manifest
names. It asks only when nothing is detectable, and always reports what it ran.

## Portability note

The agents are project-agnostic by contract. Each one derives the target
project's conventions from whatever actually exists — `CLAUDE.md` and
docs/ADRs when present, otherwise lint configs, tests, and the surrounding
code — and degrades gracefully when a file is absent (a missing `CLAUDE.md`
never blocks a run or weakens the security gate). Two optional per-project
hooks sharpen them further:

- **Reviewer routing** — `/ship:flow` routes reviewers from the diff itself
  (paths touched, contracts changed, new dependencies). A project can override
  the default with its own routing contract (e.g.
  `review-corpus/review-matrix.md`, or a pointer in its `CLAUDE.md`); no such
  file is required.
- **Invariants** — a project `CLAUDE.md` gives the builder and reviewers
  explicit invariants to enforce; without one they hold the diff to the
  conventions the code itself practices.
- **Cross-run memory** — the builder and the correctness reviewer keep
  per-project notes (toolchain facts, recurring failure patterns) in
  `.claude/agent-memory/` via `memory: project`. `/ship:flow` treats those paths
  as expected and commits them with the work, so the knowledge survives
  ephemeral sessions and rides along in version control.

All five reviewers share one output contract: findings as
`[BLOCKER|WARNING][failure-class][confidence]` blocks, ending with a
machine-parseable `VERDICT: PASS|BLOCK|ABORT (N blockers, M warnings)` line that
`/ship:flow` routes on. `ABORT` is the reviewer saying *this review did not
happen* — no working tools, or a budget spent before any evidence landed. It
exists so a reviewer that couldn't run can never be mistaken for one that found
nothing, which is the failure mode that lets a broken run report a clean pass.

Reviewers share the working tree with a committing builder, so they hold to two
rules: nothing writes outside a throwaway `ship-probe/` at the repo root (the
security and correctness reviewers may execute a probe when reading can't settle
a question; both delete it before returning), and nothing ever stages with
`git add -A`.

## Layout

```text
.claude-plugin/plugin.json   # plugin manifest (name: ship, skills: flow/plan)
skills/                      # flow/, plan/ — each a SKILL.md → /ship:flow, /ship:plan
agents/                      # builder + recon + reviewer-*  (auto-discovered)
```

`/ship:it` was retired in 0.4.0; `/ship:flow` is the single entrypoint, and its
`Agent`-based fallback path carries what `it` did.
