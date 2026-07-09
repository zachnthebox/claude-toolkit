# claude-toolkit

A personal [Claude Code](https://code.claude.com/docs) plugin marketplace so the
same shipping workflow and reviewer panel can be installed across every project.

## What's inside

One plugin, **shipkit**:

- **Commands** — `/ship` (build one safe unit with risk-routed review, fix loops,
  and a final security gate) and `/ship-plan` (draft a step-structured spec doc
  that `/ship` builds one shippable step at a time).
- **Agents** — `builder` (implements the work) and the reviewer panel:
  `reviewer-rigorous`, `reviewer-architect`, `reviewer-frontend`,
  `reviewer-minimalist`, `reviewer-security`.

## Install

In any project (or your user-level Claude Code config):

```text
/plugin marketplace add zachnthebox/claude-toolkit
/plugin install shipkit
```

Then `/ship`, `/ship-plan`, and the agents are available. Update later with
`/plugin update shipkit`.

## Portability note

These commands and agents were extracted from a specific project and still carry
some of its assumptions — the review routing references a `review-corpus/review-matrix.md`
file, the final checks run `npm run build && npm run lint && npm test`, and the
agents lean on that project's `Context` DI seam and `CLAUDE.md` invariants. They
run anywhere, but for projects with a different build or layering you'll want to
tune the `## 5. Finish once` checks in `ship.md` and the project-specific
references in the reviewer agents.

## Layout

```text
.claude-plugin/marketplace.json   # marketplace manifest (lists the plugins)
plugins/shipkit/
  .claude-plugin/plugin.json       # plugin manifest
  commands/                        # ship.md, ship-plan.md
  agents/                          # builder + reviewer-*
```
