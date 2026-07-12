# claude-toolkit

A personal [Claude Code](https://code.claude.com/docs) plugin — the same
shipping workflow and reviewer panel, installable across every project by
cloning it into your skills directory during environment setup.

## What's inside

Plugin **`ship`**. Plugin components are namespaced by the plugin name, so you
invoke everything as `ship:…` — a short, meaningful namespace that reads as a
phrase with each command.

- **Commands** — `/ship:it` (build one safe unit with risk-routed review, fix
  loops, and a final security gate) and `/ship:plan` (draft a step-structured
  spec doc that `/ship:it` builds one shippable step at a time).
- **Agents** — `ship:builder` (implements the work) and the reviewer panel:
  `ship:reviewer-rigorous`, `ship:reviewer-architect`, `ship:reviewer-frontend`,
  `ship:reviewer-minimalist`, `ship:reviewer-security`.

## Install (headless / setup script)

Clone this repo into your skills directory. Claude Code auto-discovers any folder
under `~/.claude/skills/` that has a `.claude-plugin/plugin.json` and loads it as
a full plugin (`ship@skills-dir`) — commands and agents included — on the next
session. No interactive `/plugin` command required.

```bash
git clone https://github.com/zachnthebox/claude-toolkit ~/.claude/skills/claude-toolkit
```

Update later with a plain `git pull` in that directory.

## Install (interactive, optional)

If you prefer the plugin UI in a normal session, this repo also works as a
single-plugin install:

```text
/plugin install zachnthebox/claude-toolkit
```

## Per-project setup: the verify gate

`/ship:it` is toolchain-agnostic. Its final build/lint/test gate does not assume
`npm` (or any tool) — instead it runs a script the project provides:

```text
.claude/hooks/ship-verify.sh <base-ref>   # base-ref defaults to origin/main
```

That script is the project's single source of truth for a full build, lint, and
test run. A non-zero exit blocks the push and feeds `/ship:it`'s builder/reviewer
fix loop. Copy-paste starting points live in [`examples/`](./examples):

- [`examples/ship-verify.node.sh`](./examples/ship-verify.node.sh)
- [`examples/ship-verify.ios.sh`](./examples/ship-verify.ios.sh)
- [`examples/ship-verify.rust.sh`](./examples/ship-verify.rust.sh)

Drop one into `.claude/hooks/ship-verify.sh`, `chmod +x`, and adjust for the
project. If a project has no such script, `/ship:it` detects the conventional
command or asks rather than guessing a toolchain.

## Portability note

The agents are project-agnostic by contract. Each one derives the target
project's conventions from whatever actually exists — `CLAUDE.md` and
docs/ADRs when present, otherwise lint configs, tests, and the surrounding
code — and degrades gracefully when a file is absent (a missing `CLAUDE.md`
never blocks a run or weakens the security gate). Two optional per-project
hooks sharpen them further:

- **Reviewer routing** — `/ship:it` routes reviewers from the diff itself
  (paths touched, contracts changed, new dependencies). A project can override
  the default with its own routing contract (e.g.
  `review-corpus/review-matrix.md`, or a pointer in its `CLAUDE.md`); no such
  file is required.
- **Invariants** — a project `CLAUDE.md` gives the builder and reviewers
  explicit invariants to enforce; without one they hold the diff to the
  conventions the code itself practices.
- **Cross-run memory** — the builder and the correctness reviewer keep
  per-project notes (toolchain facts, recurring failure patterns) in
  `.claude/agent-memory/` via `memory: project`. `/ship:it` treats those paths
  as expected and commits them with the work, so the knowledge survives
  ephemeral sessions and rides along in version control.

All five reviewers share one output contract: findings as
`[BLOCKER|WARNING][failure-class][confidence]` blocks, ending with a
machine-parseable `VERDICT: PASS|BLOCK (N blockers, M warnings)` line that
`/ship:it` routes on.

## Layout

```text
.claude-plugin/plugin.json   # plugin manifest (name: ship)
commands/                    # it.md, plan.md           (auto-discovered → /ship:it, /ship:plan)
agents/                      # builder + reviewer-*     (auto-discovered)
```
