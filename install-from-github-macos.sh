#!/usr/bin/env bash

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/kasary/YT-to-TAF-to-Teddycloud.git}"
TARGET_DIR="${TARGET_DIR:-YT-to-TAF-to-Teddycloud}"

print_step() {
  printf '\n==> %s\n' "$1"
}

require_command() {
  local command_name="$1"
  local hint="${2:-}"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Error: ${command_name} was not found.${hint:+ ${hint}}" >&2
    exit 1
  fi
}

main() {
  require_command git

  if [ -e "$TARGET_DIR" ]; then
    echo "Error: target directory already exists: $TARGET_DIR" >&2
    exit 1
  fi

  print_step "Cloning repository"
  git clone "$REPO_URL" "$TARGET_DIR"

  print_step "Running macOS setup"
  cd "$TARGET_DIR"
  chmod +x setup-macos.sh
  ./setup-macos.sh
}

main "$@"
