#!/usr/bin/env bash
# Example ship-verify.sh — iOS / Swift project.
#
# Copy to .claude/hooks/ship-verify.sh in your project and `chmod +x` it.
# /ship runs it as the final gate before pushing, invoked as
# `.claude/hooks/ship-verify.sh <base-ref>` (base-ref defaults to origin/main).
# A non-zero exit blocks the push and routes failures back through /ship's
# builder/reviewer fix loop. This script is the single source of truth for what
# "green" means in the project.
set -euo pipefail

BASE="${1:-origin/main}"

# Point these at your app. Use -workspace App.xcworkspace if you use CocoaPods/SPM
# workspaces instead of a bare project, and pick a simulator you actually have
# (list them with `xcrun simctl list devices`).
SCHEME="App"
DESTINATION="platform=iOS Simulator,name=iPhone 15"

xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" build
swiftlint --strict
xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" test
