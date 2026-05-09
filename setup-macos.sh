#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${VENV_DIR:-${SCRIPT_DIR}/.venv}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
OPUS2TONIE_DIR="${OPUS2TONIE_DIR:-${SCRIPT_DIR}/opus2tonie}"
OPUS2TONIE_REPO="${OPUS2TONIE_REPO:-https://github.com/bailli/opus2tonie.git}"

print_step() {
  printf '\n==> %s\n' "$1"
}

require_command() {
  local command_name="$1"
  local hint="${2:-}"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Fehler: ${command_name} wurde nicht gefunden.${hint:+ ${hint}}" >&2
    exit 1
  fi
}

brew_install_if_missing() {
  local package_name="$1"
  local binary_name="${2:-$1}"

  if command -v "$binary_name" >/dev/null 2>&1; then
    printf 'Bereits vorhanden: %s\n' "$binary_name"
    return
  fi

  print_step "Installiere ${package_name}"
  brew install "$package_name"
}

setup_python_venv() {
  print_step "Richte Python-Umgebung ein"

  if [ ! -d "$VENV_DIR" ]; then
    "$PYTHON_BIN" -m venv "$VENV_DIR"
  fi

  "${VENV_DIR}/bin/python3" -m pip install --upgrade pip
  "${VENV_DIR}/bin/python3" -m pip install "protobuf<3.21"
}

setup_opus2tonie() {
  print_step "Richte opus2tonie ein"

  if [ -d "${OPUS2TONIE_DIR}/.git" ]; then
    printf 'Bereits vorhanden: %s\n' "$OPUS2TONIE_DIR"
    return
  fi

  if [ -e "$OPUS2TONIE_DIR" ]; then
    echo "Fehler: ${OPUS2TONIE_DIR} existiert bereits, ist aber kein Git-Checkout." >&2
    exit 1
  fi

  git clone "$OPUS2TONIE_REPO" "$OPUS2TONIE_DIR"
}

print_next_steps() {
  cat <<EOF

Setup abgeschlossen.

Naechste Schritte:
1. TeddyCloud-URL setzen:
   export TEDDYCLOUD_URL="http://DEIN-TEDDYCLOUD-HOST/web"

2. Script testen:
   ./download-audio.sh "https://youtube.com/watch?v=..."

Optional:
- Wenn du einen anderen Download-Ordner willst:
  export DOWNLOAD_DIR="\$HOME/Music/yt-audio"
- Wenn terminal-notifier nicht automatisch gefunden wird:
  export TERMINAL_NOTIFIER_BIN="\$(command -v terminal-notifier)"
EOF
}

main() {
  cd "$SCRIPT_DIR"

  require_command brew "Installiere Homebrew zuerst: https://brew.sh/"
  require_command git

  print_step "Installiere Abhaengigkeiten"
  brew_install_if_missing yt-dlp
  brew_install_if_missing ffmpeg
  brew_install_if_missing opus-tools opusenc
  brew_install_if_missing terminal-notifier
  brew_install_if_missing python python3
  brew_install_if_missing curl

  setup_python_venv
  setup_opus2tonie
  print_next_steps
}

main "$@"
