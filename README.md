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

## Portability note

These commands and agents were extracted from a specific project and still carry
some of its assumptions — the review routing references a `review-corpus/review-matrix.md`
file, the final checks run `npm run build && npm run lint && npm test`, and the
agents lean on that project's `Context` DI seam and `CLAUDE.md` invariants. They
run anywhere, but for projects with a different build or layering you'll want to
tune the `## 5. Finish once` checks in `commands/ship.md` and the project-specific
references in the reviewer agents.

## Layout

```text
.claude-plugin/plugin.json   # plugin manifest (name: shipkit)
commands/                    # ship.md, ship-plan.md   (auto-discovered)
agents/                      # builder + reviewer-*     (auto-discovered)
```
