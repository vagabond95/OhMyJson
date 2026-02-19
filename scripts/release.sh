#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# OhMyJson Release Script
#
# Usage: ./scripts/release.sh <version> [release-message]
#   e.g. ./scripts/release.sh 0.3.0 "Add search highlighting"
#
# This script:
#   1. Validates semver format, clean tree, and main branch
#   2. Bumps MARKETING_VERSION in project.pbxproj
#   3. Commits, tags, and pushes
#
# GitHub Actions handles the rest (build, sign, notarize, DMG,
# GitHub Release, Homebrew cask update).
# ─────────────────────────────────────────────────────────────

VERSION="${1:-}"
RELEASE_MSG="${2:-"Release v${VERSION}"}"

PBXPROJ="OhMyJson.xcodeproj/project.pbxproj"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Helpers ──────────────────────────────────────────────────

die() {
  echo "error: $1" >&2
  exit 1
}

# ── Validation ───────────────────────────────────────────────

if [ -z "$VERSION" ]; then
  echo "Usage: ./scripts/release.sh <version> [release-message]"
  echo "  e.g. ./scripts/release.sh 0.3.0 \"Add search highlighting\""
  exit 1
fi

# Semver format check (X.Y.Z)
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  die "Invalid version format: '$VERSION'. Expected semver (e.g. 0.3.0)"
fi

cd "$PROJECT_ROOT"

# Clean working tree
if ! git diff --quiet || ! git diff --cached --quiet; then
  die "Working tree is not clean. Commit or stash changes first."
fi

if [ -n "$(git ls-files --others --exclude-standard)" ]; then
  die "Untracked files found. Commit or remove them first."
fi

# Must be on main branch
BRANCH=$(git symbolic-ref --short HEAD)
if [ "$BRANCH" != "main" ]; then
  die "Must be on 'main' branch (currently on '$BRANCH')."
fi

# Tag must not exist
if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
  die "Tag v${VERSION} already exists."
fi

# project.pbxproj must exist
if [ ! -f "$PBXPROJ" ]; then
  die "Cannot find $PBXPROJ"
fi

# ── Detect current version ───────────────────────────────────

# Find the current app MARKETING_VERSION (X.Y.Z format, not "1.0" which is test target)
CURRENT_VERSION=$(grep 'MARKETING_VERSION = ' "$PBXPROJ" \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
  | head -1)

if [ -z "$CURRENT_VERSION" ]; then
  die "Could not detect current MARKETING_VERSION in $PBXPROJ"
fi

if [ "$CURRENT_VERSION" = "$VERSION" ]; then
  die "Version is already $VERSION"
fi

# ── Summary & confirmation ───────────────────────────────────

echo ""
echo "  OhMyJson Release"
echo "  ────────────────────────────"
echo "  Version:  $CURRENT_VERSION -> $VERSION"
echo "  Tag:      v${VERSION}"
echo "  Message:  $RELEASE_MSG"
echo ""
read -rp "  Proceed? [y/N] " confirm
echo ""

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

# ── Bump version ─────────────────────────────────────────────

echo "Bumping MARKETING_VERSION: $CURRENT_VERSION -> $VERSION ..."

# Replace only the app target's version (X.Y.Z format), not the test target's "1.0"
sed -i '' "s/MARKETING_VERSION = ${CURRENT_VERSION};/MARKETING_VERSION = ${VERSION};/g" "$PBXPROJ"

# Verify exactly 2 replacements (Debug + Release build configurations)
MATCH_COUNT=$(grep -c "MARKETING_VERSION = ${VERSION};" "$PBXPROJ")
if [ "$MATCH_COUNT" -ne 2 ]; then
  echo "error: Expected 2 MARKETING_VERSION replacements, found $MATCH_COUNT. Rolling back."
  git checkout -- "$PBXPROJ"
  exit 1
fi

echo "  Updated $MATCH_COUNT occurrences in $PBXPROJ"

# ── Commit, tag, push ────────────────────────────────────────

echo "Committing version bump..."
git add "$PBXPROJ"
git commit -m "chore: bump version to $VERSION"

echo "Creating tag v${VERSION}..."
git tag -a "v${VERSION}" -m "$RELEASE_MSG"

echo "Pushing to origin..."
git push origin main
git push origin "v${VERSION}"

echo ""
echo "Done! Tag v${VERSION} pushed."
echo "GitHub Actions will now build, sign, notarize, and release."
echo "Monitor progress at: https://github.com/vagabond95/OhMyJson/actions"
