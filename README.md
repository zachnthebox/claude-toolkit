# claude-toolkit

A personal [Claude Code](https://code.claude.com/docs) plugin — the same
shipping workflow and reviewer panel, installable across every project by
cloning it into your skills directory during environment setup.

## What's inside

Plugin **shipkit**:

- **Commands** — `/ship` (build one safe unit with risk-routed review, fix loops,
  and a final security gate) and `/ship-plan` (draft a step-structured spec doc
  that `/ship` builds one shippable step at a time).
- **Agents** — `builder` (implements the work) and the reviewer panel:
  `reviewer-rigorous`, `reviewer-architect`, `reviewer-frontend`,
  `reviewer-minimalist`, `reviewer-security`.

## Install (headless / setup script)

Clone this repo into your skills directory. Claude Code auto-discovers any folder
under `~/.claude/skills/` that has a `.claude-plugin/plugin.json` and loads it as
a full plugin (`shipkit@skills-dir`) — commands and agents included — on the next
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

`/ship` is toolchain-agnostic. Its final build/lint/test gate does not assume
`npm` (or any tool) — instead it runs a script the project provides:

```text
.claude/hooks/ship-verify.sh <base-ref>   # base-ref defaults to origin/main
```

That script is the project's single source of truth for a full build, lint, and
test run. A non-zero exit blocks the push and feeds `/ship`'s builder/reviewer
fix loop. Copy-paste starting points live in [`examples/`](./examples):

- [`examples/ship-verify.node.sh`](./examples/ship-verify.node.sh)
- [`examples/ship-verify.ios.sh`](./examples/ship-verify.ios.sh)
- [`examples/ship-verify.rust.sh`](./examples/ship-verify.rust.sh)

Drop one into `.claude/hooks/ship-verify.sh`, `chmod +x`, and adjust for the
project. If a project has no such script, `/ship` detects the conventional
command or asks rather than guessing a toolchain.

## Portability note

The reviewer agents still carry some conventions from the project they were
extracted from — the review routing references a `review-corpus/review-matrix.md`
file, and the agents lean on that project's `Context` DI seam and `CLAUDE.md`
invariants. They run anywhere, but for a project with different layering you'll
want to tune those references.

## Layout

```text
.claude-plugin/plugin.json   # plugin manifest (name: shipkit)
commands/                    # ship.md, ship-plan.md   (auto-discovered)
agents/                      # builder + reviewer-*     (auto-discovered)
```
