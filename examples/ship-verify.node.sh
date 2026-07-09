#!/usr/bin/env bash
# Example ship-verify.sh — Node project.
#
# Copy to .claude/hooks/ship-verify.sh in your project and `chmod +x` it.
# /ship runs it as the final gate before pushing, invoked as
# `.claude/hooks/ship-verify.sh <base-ref>` (base-ref defaults to origin/main).
# A non-zero exit blocks the push and routes failures back through /ship's
# builder/reviewer fix loop. This script is the single source of truth for what
# "green" means in the project.
set -euo pipefail

BASE="${1:-origin/main}"

npm run build
npm run lint
npm test

# Lint Markdown only when this unit changed a .md file.
if ! git diff --quiet "$BASE"...HEAD -- '*.md' 2>/dev/null; then
  npm run lint:md
fi
