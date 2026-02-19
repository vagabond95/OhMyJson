#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# OhMyJson Release Script (idempotent — safe to re-run)
#
# Usage: ./scripts/release.sh <version> [release-message]
#   e.g. ./scripts/release.sh 0.3.0 "Add search highlighting"
#
# This script:
#   1. Validates semver format and main branch
#   2. Bumps MARKETING_VERSION in project.pbxproj (skips if already done)
#   3. Commits (skips if already committed)
#   4. Tags (skips if already tagged)
#   5. Pushes commit and tag (skips if already pushed)
#
# Each step is idempotent — if the script fails midway,
# re-running it with the same version resumes from where it left off.
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

# Must be on main branch
BRANCH=$(git symbolic-ref --short HEAD)
if [ "$BRANCH" != "main" ]; then
  die "Must be on 'main' branch (currently on '$BRANCH')."
fi

# project.pbxproj must exist
if [ ! -f "$PBXPROJ" ]; then
  die "Cannot find $PBXPROJ"
fi

# Check if tag already exists on remote (fully done — nothing to do)
if git ls-remote --tags origin "refs/tags/v${VERSION}" | grep -q "v${VERSION}"; then
  echo "Tag v${VERSION} already exists on remote. Release already complete."
  echo "Monitor at: https://github.com/vagabond95/OhMyJson/actions"
  exit 0
fi

# ── Detect current state ─────────────────────────────────────

CURRENT_VERSION=$(grep 'MARKETING_VERSION = ' "$PBXPROJ" \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
  | head -1)

if [ -z "$CURRENT_VERSION" ]; then
  die "Could not detect current MARKETING_VERSION in $PBXPROJ"
fi

# Determine what's already done
NEED_BUMP=true
NEED_COMMIT=true
NEED_TAG=true

if [ "$CURRENT_VERSION" = "$VERSION" ]; then
  NEED_BUMP=false
fi

# Check for uncommitted changes (only pbxproj modification is allowed for resume)
if ! git diff --quiet || ! git diff --cached --quiet; then
  # Only allow if the sole change is pbxproj with our version
  CHANGED_FILES=$(git diff --name-only; git diff --cached --name-only)
  if [ "$CHANGED_FILES" != "$PBXPROJ" ]; then
    die "Working tree has unexpected changes. Commit or stash them first.\n$(git status --short)"
  fi
  if [ "$NEED_BUMP" = true ]; then
    die "Working tree has changes to $PBXPROJ but version is not $VERSION. Resolve manually."
  fi
  # pbxproj is modified with target version — just need to commit
  NEED_COMMIT=true
fi

if [ -n "$(git ls-files --others --exclude-standard)" ]; then
  die "Untracked files found. Commit or remove them first."
fi

# If version already matches and tree is clean, check if commit exists
if [ "$NEED_BUMP" = false ] && git diff --quiet && git diff --cached --quiet; then
  # Check if HEAD commit is the version bump
  if git log -1 --format='%s' | grep -q "chore: bump version to $VERSION"; then
    NEED_COMMIT=false
  else
    # Version matches but commit is not the bump — already committed and more commits on top
    NEED_COMMIT=false
  fi
fi

# Check if local tag exists
if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
  NEED_TAG=false
fi

# ── Summary & confirmation ───────────────────────────────────

echo ""
echo "  OhMyJson Release"
echo "  ────────────────────────────"
if [ "$NEED_BUMP" = true ]; then
  echo "  Version:  $CURRENT_VERSION -> $VERSION"
else
  echo "  Version:  $VERSION (already bumped)"
fi
echo "  Tag:      v${VERSION}"
echo "  Message:  $RELEASE_MSG"
echo ""
echo "  Steps:"
[ "$NEED_BUMP" = true ]   && echo "    - Bump version" || echo "    - Bump version (skip)"
[ "$NEED_COMMIT" = true ] && echo "    - Commit"       || echo "    - Commit (skip)"
[ "$NEED_TAG" = true ]    && echo "    - Create tag"    || echo "    - Create tag (skip)"
echo "    - Push to origin"
echo ""
read -rp "  Proceed? [y/N] " confirm
echo ""

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

# ── Step 1: Bump version ─────────────────────────────────────

if [ "$NEED_BUMP" = true ]; then
  echo "Bumping MARKETING_VERSION: $CURRENT_VERSION -> $VERSION ..."

  sed -i '' "s/MARKETING_VERSION = ${CURRENT_VERSION};/MARKETING_VERSION = ${VERSION};/g" "$PBXPROJ"

  MATCH_COUNT=$(grep -c "MARKETING_VERSION = ${VERSION};" "$PBXPROJ")
  if [ "$MATCH_COUNT" -ne 2 ]; then
    echo "error: Expected 2 MARKETING_VERSION replacements, found $MATCH_COUNT. Rolling back."
    git checkout -- "$PBXPROJ"
    exit 1
  fi

  echo "  Updated $MATCH_COUNT occurrences in $PBXPROJ"
else
  echo "Version already $VERSION, skipping bump."
fi

# ── Step 2: Commit ───────────────────────────────────────────

if [ "$NEED_COMMIT" = true ]; then
  echo "Committing version bump..."
  git add "$PBXPROJ"
  git commit -m "chore: bump version to $VERSION"
else
  echo "Version bump already committed, skipping commit."
fi

# ── Step 3: Tag ──────────────────────────────────────────────

if [ "$NEED_TAG" = true ]; then
  echo "Creating tag v${VERSION}..."
  git tag -a "v${VERSION}" -m "$RELEASE_MSG"
else
  echo "Tag v${VERSION} already exists locally, skipping tag."
fi

# ── Step 4: Push ─────────────────────────────────────────────

echo "Pushing to origin..."
git push origin main
git push origin "v${VERSION}"

echo ""
echo "Done! Tag v${VERSION} pushed."
echo "Waiting for GitHub Actions workflow to start..."

# Wait briefly for GitHub to register the workflow run
sleep 5

if command -v gh &>/dev/null; then
  gh run watch
else
  echo "Install 'gh' CLI to watch progress here, or visit:"
  echo "https://github.com/vagabond95/OhMyJson/actions"
fi
