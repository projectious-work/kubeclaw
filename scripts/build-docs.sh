#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_BASE_URL="${DOCS_BASE_URL:-https://projectious-work.github.io/kubeclaw/}"
BUILD_DIR="${ROOT_DIR}/public"

BUILD_ARGS=("$@")
for ((i = 0; i < ${#BUILD_ARGS[@]}; i++)); do
  case "${BUILD_ARGS[i]}" in
    --destination)
      if ((i + 1 >= ${#BUILD_ARGS[@]})); then
        echo "--destination requires a value." >&2
        exit 1
      fi
      BUILD_DIR="${BUILD_ARGS[i + 1]}"
      ;;
    --destination=*)
      BUILD_DIR="${BUILD_ARGS[i]#--destination=}"
      ;;
  esac
done

if [[ "${BUILD_DIR}" != /* ]]; then
  BUILD_DIR="${ROOT_DIR}/${BUILD_DIR}"
fi

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
  # Prefer the lockfile so Docsy's transitive dependencies are pinned too;
  # package.json only pins the direct ones.
  if [[ -f "${ROOT_DIR}/package-lock.json" ]]; then
    npm --prefix "${ROOT_DIR}" ci
  else
    npm --prefix "${ROOT_DIR}" install --no-package-lock
  fi
fi

cd "${ROOT_DIR}"
hugo --gc --minify --cleanDestinationDir --baseURL "${DOCS_BASE_URL}" \
  "${BUILD_ARGS[@]}"

# GitHub Pages must serve Hugo's prebuilt output without Jekyll processing.
: > "${BUILD_DIR}/.nojekyll"
