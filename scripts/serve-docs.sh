#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_BASE_URL="${DOCS_BASE_URL:-http://localhost:1313/}"

command -v hugo >/dev/null 2>&1 || {
  echo "Hugo extended is required: https://gohugo.io/installation/" >&2
  exit 1
}
command -v npm >/dev/null 2>&1 || {
  echo "Node.js and npm are required for Docsy assets." >&2
  exit 1
}

if [[ ! -f "${ROOT_DIR}/themes/docsy/theme.toml" ]]; then
  git -C "${ROOT_DIR}" submodule update --init --recursive themes/docsy
fi
if [[ ! -d "${ROOT_DIR}/node_modules" ]]; then
  npm --prefix "${ROOT_DIR}" install --no-package-lock
fi

cd "${ROOT_DIR}"
hugo server --buildDrafts --disableFastRender --baseURL "${DOCS_BASE_URL}" "$@"
