# claude-toolkit

A personal [Claude Code](https://code.claude.com/docs) plugin — a shipping
workflow and reviewer panel, installable across every project by cloning it
into your skills directory during environment setup.

## What's inside

Plugin **`ship`**. Components are namespaced by the plugin name, so you
invoke everything as `ship:…`.

- **Skills** — `/ship:flow` (the entrypoint: build, risk-routed review, fix
  loops, security gate, push, PR, merge on green CI — then straight on to
  the next step) and `/ship:plan` (draft a step-structured spec doc that
  `/ship:flow` ships one step at a time).
- **Agents** — `ship:builder` (implements the work), `ship:recon` (read-only
  scout for large/unfamiliar files), and the reviewer panel:
  `ship:reviewer-rigorous`, `ship:reviewer-architect`,
  `ship:reviewer-frontend`, `ship:reviewer-minimalist`,
  `ship:reviewer-security`.

## How a run goes

```text
/ship:flow docs/my-feature.md
```

`/ship:flow` picks the first unshipped step, builds it with `ship:builder`,
routes a reviewer panel at the diff (correctness always; architecture,
frontend, and security when the diff touches their surfaces), batches every
blocker into one fix round where the builder fixes what holds and rebuts
what doesn't, runs the security gate on the full PR diff, runs the project's
verify gate, pushes, opens the PR, merges on green — then goes back for the
next step. One invocation ships the whole plan.

It runs unattended by design. It stops to ask only when proceeding would be
unsafe under every reading: an ambiguous merge conflict, an unbuildable
acceptance criterion, an unresolved security blocker, or an exhausted fix
loop. CI failures and merge conflicts are its own to fix, not yours to
triage.

Append `--hold` to stop once the PR is open, or `--no-merge` to never merge.
Both are opt-in; the default is to finish.

Merging is gated on six conditions, and the last one matters most for an
unattended run: the head being merged must be the exact SHA the review
pipeline cleared. A CI fix, a conflict resolution, or an agent-memory commit
lands after the reviewers went home, so each one re-runs the local gate and
the security pass before the merge proceeds.

The entrypoints are **skills**, not plugin slash-commands, so they load on
Claude Code on the web as well as the desktop/CLI. They stay user-invoke-only
(`disable-model-invocation`) — only you trigger a deploy-class run; Claude
never auto-fires one.

## Install (headless / setup script)

Clone this repo into your skills directory. Claude Code auto-discovers any
folder under `~/.claude/skills/` that has a `.claude-plugin/plugin.json` and
loads it as a full plugin (`ship@skills-dir`) — skills and agents included —
on the next session:

```bash
git clone https://github.com/zachnthebox/claude-toolkit ~/.claude/skills/claude-toolkit
```

Update later with a plain `git pull` in that directory. If you prefer the
plugin UI: `/plugin install zachnthebox/claude-toolkit`.

### Optional: concise output everywhere

To apply the same concise, outcome-first style to every Claude Code
session — not just `ship:…` runs — append the stanza in
[`examples/concise-style.md`](./examples/concise-style.md) to your personal
`~/.claude/CLAUDE.md`:

```bash
cat ~/.claude/skills/claude-toolkit/examples/concise-style.md >> ~/.claude/CLAUDE.md
```

Opt-in on purpose: `~/.claude/CLAUDE.md` is your personal, all-projects
config, so cloning the toolkit never edits it for you.

## Per-project setup: the verify gate

`/ship:flow` is toolchain-agnostic. Its final build/lint/test gate runs a
script the project provides:

```text
.claude/hooks/ship-verify.sh <base-ref>   # base-ref defaults to origin/main
```

That script is the project's single source of truth for a full build, lint,
and test run. A non-zero exit blocks the push and feeds the fix loop.
Copy-paste starting points live in [`examples/`](./examples):
[`ship-verify.node.sh`](./examples/ship-verify.node.sh),
[`ship-verify.ios.sh`](./examples/ship-verify.ios.sh),
[`ship-verify.rust.sh`](./examples/ship-verify.rust.sh). Drop one into
`.claude/hooks/ship-verify.sh` and `chmod +x`.

Without one, `/ship:flow` reads the repo's own CI workflow and runs what it
runs on pull requests — that file is the project's real definition of
green — falling back to the conventional command for the toolchain the
manifest names. It asks only when nothing is detectable, and always reports
what it ran.

## Portability

The agents are project-agnostic by contract. Each derives the target
project's conventions from whatever exists — `CLAUDE.md` and docs/ADRs when
present, otherwise lint configs, tests, and the surrounding code — and a
missing file never blocks a run or weakens the security gate. Two optional
per-project hooks sharpen them:

- **Reviewer routing** — `/ship:flow` routes reviewers from the diff itself.
  A project can override that with its own routing contract (e.g.
  `review-corpus/review-matrix.md`, or a pointer in its `CLAUDE.md`).
- **Invariants** — a project `CLAUDE.md` gives the builder and reviewers
  explicit invariants to enforce; without one they hold the diff to the
  conventions the code itself practices.
- **Cross-run memory** — the builder and the correctness reviewer keep
  per-project notes (toolchain facts, recurring failure patterns) in
  `.claude/agent-memory/` via `memory: project`, injected at spawn.
  `/ship:flow` commits those paths with the work, so the knowledge survives
  ephemeral sessions.

Every reviewer reports demonstrated findings — evidence, impact, the
smallest complete fix, and the regression test required — and ends with a
`VERDICT: PASS | BLOCK` line. Blockers gate on evidence: the builder fixes
what holds and rebuts what doesn't, and rebuttals go back to the reviewer
that raised the finding for re-adjudication rather than being accepted
silently.
