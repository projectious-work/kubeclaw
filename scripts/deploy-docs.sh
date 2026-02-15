#!/usr/bin/env bash
set -euo pipefail

# Deploy MkDocs site to the 'pages' branch for Codeberg Pages (git-pages compatible).
# Usage: ./scripts/deploy-docs.sh

PAGES_BRANCH="pages"
BUILD_DIR="site"

echo "Building MkDocs site..."
mkdocs build --strict

echo "Deploying to '${PAGES_BRANCH}' branch..."

# Use a temporary worktree to avoid messing with the current checkout
WORKTREE_DIR=$(mktemp -d)
trap 'rm -rf "${WORKTREE_DIR}"' EXIT

# Check if the pages branch exists
if git show-ref --verify --quiet "refs/heads/${PAGES_BRANCH}"; then
    git worktree add "${WORKTREE_DIR}" "${PAGES_BRANCH}"
else
    # Create an orphan branch
    git worktree add --detach "${WORKTREE_DIR}"
    git -C "${WORKTREE_DIR}" checkout --orphan "${PAGES_BRANCH}"
    git -C "${WORKTREE_DIR}" rm -rf . 2>/dev/null || true
fi

# Clean the worktree and copy the built site
find "${WORKTREE_DIR}" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
cp -r "${BUILD_DIR}/." "${WORKTREE_DIR}/"

# Commit and push
cd "${WORKTREE_DIR}"
git add -A
if git diff --cached --quiet; then
    echo "No changes to deploy."
else
    git commit -m "Deploy documentation $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    git push origin "${PAGES_BRANCH}"
    echo "Documentation deployed to '${PAGES_BRANCH}' branch."
fi

cd -
git worktree remove "${WORKTREE_DIR}" 2>/dev/null || true
