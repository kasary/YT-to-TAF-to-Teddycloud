#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${HOME}/Music/yt-audio}"
OPUS2TONIE_DIR="${OPUS2TONIE_DIR:-${SCRIPT_DIR}/opus2tonie}"
PYTHON_BIN="${PYTHON_BIN:-${SCRIPT_DIR}/.venv/bin/python3}"
TEDDYCLOUD_URL="${TEDDYCLOUD_URL:-}"
TERMINAL_NOTIFIER_BIN="${TERMINAL_NOTIFIER_BIN:-}"
KEEP_SOURCE_AUDIO="${KEEP_SOURCE_AUDIO:-0}"
WORK_DIR=""
DEFAULT_TITLE="Unbenannt"
NOTIFICATION_TITLE="YT Audio Download"

trim() {
  local value="$1"
  value="${value//$'\r'/}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

print_error() {
  echo "Fehler: $1" >&2
}

usage() {
  cat <<EOF
Verwendung:
  $(basename "$0") <youtube-url>

Konfiguration ueber Umgebungsvariablen:
  TEDDYCLOUD_URL         z. B. http://192.168.178.180/web
  DOWNLOAD_DIR           lokaler Arbeitsordner fuer fertige .taf-Dateien
  KEEP_SOURCE_AUDIO      1 = .wav zusaetzlich behalten
  OPUS2TONIE_DIR         Pfad zum geklonten opus2tonie-Repo
  PYTHON_BIN             Python aus deiner virtuellen Umgebung
  TERMINAL_NOTIFIER_BIN  optionaler expliziter Pfad zu terminal-notifier
EOF
}

cleanup() {
  if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
}

url_encode() {
  "$PYTHON_BIN" -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

sanitize_filename() {
  "$PYTHON_BIN" -c '
import re, sys
name = sys.argv[1].strip()
name = re.sub(r"[/:\\\\?%*|\"<>]", "-", name)
name = re.sub(r"\s+", " ", name).strip()
print(name)
' "$1"
}

resolve_terminal_notifier() {
  if [ -n "$TERMINAL_NOTIFIER_BIN" ] && [ -x "$TERMINAL_NOTIFIER_BIN" ]; then
    printf '%s\n' "$TERMINAL_NOTIFIER_BIN"
    return
  fi

  if command -v terminal-notifier >/dev/null 2>&1; then
    command -v terminal-notifier
    return
  fi

  if [ -x /opt/homebrew/bin/terminal-notifier ]; then
    printf '%s\n' /opt/homebrew/bin/terminal-notifier
  fi
}

notify_error() {
  local message="$1"
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"${message}\" with title \"${NOTIFICATION_TITLE}\"" >/dev/null 2>&1 || true
  fi
}

notify_success() {
  local title="$1"
  local tonies_url notifier

  notifier="$(resolve_terminal_notifier)"
  tonies_url="$(teddycloud_tonies_url)"

  if [ -n "$notifier" ] && [ -n "$tonies_url" ]; then
    "$notifier" \
      -title "$NOTIFICATION_TITLE" \
      -message "${title} - fertig" \
      -sound default \
      -open "$tonies_url" >/dev/null 2>&1 || true
    return
  fi

  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"${title} - fertig\" with title \"${NOTIFICATION_TITLE}\" sound name \"default\"" >/dev/null 2>&1 || true
  fi
}

on_error() {
  local exit_code=$?
  local message="Download, TAF-Konvertierung oder Upload fehlgeschlagen."
  print_error "$message"
  notify_error "$message"
  exit "$exit_code"
}

require_command() {
  local command_name="$1"
  local hint="${2:-}"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    print_error "${command_name} wurde nicht gefunden.${hint:+ ${hint}}"
    exit 1
  fi
}

require_file() {
  local path="$1"
  local description="$2"
  if [ ! -e "$path" ]; then
    print_error "${description} wurde nicht gefunden unter ${path}."
    exit 1
  fi
}

teddycloud_api_base() {
  if [ -z "$TEDDYCLOUD_URL" ]; then
    print_error "TEDDYCLOUD_URL ist nicht gesetzt."
    exit 1
  fi

  local base_url
  base_url="${TEDDYCLOUD_URL%/}"
  printf '%s\n' "${base_url%/web}"
}

teddycloud_tonies_url() {
  if [ -z "$TEDDYCLOUD_URL" ]; then
    return
  fi

  local web_url
  web_url="${TEDDYCLOUD_URL%/}"
  if [[ "$web_url" != */web ]]; then
    web_url="${web_url}/web"
  fi
  printf '%s/tonies\n' "$web_url"
}

detect_title() {
  local url="$1"
  local title

  title="$(yt-dlp --print title --skip-download "$url" 2>/dev/null | head -n 1 || true)"
  title="$(trim "$title")"

  if [ -z "$title" ]; then
    title="$DEFAULT_TITLE"
  fi

  printf '%s\n' "$title"
}

edit_title() {
  local detected_title="$1"
  local edited_title

  edited_title="$(osascript - "$detected_title" <<'EOF'
on run argv
set detectedTitle to item 1 of argv
set dialogResult to display dialog "Titel anpassen oder einfach mit OK bestaetigen" default answer detectedTitle with title "YT Audio Titel"
return text returned of dialogResult
end run
EOF
)"
  edited_title="$(trim "$edited_title")"

  if [ -z "$edited_title" ]; then
    print_error "Kein Titel angegeben."
    exit 1
  fi

  sanitize_filename "$edited_title"
}

fetch_library_dirs() {
  local current_path="$1"
  local index_url

  index_url="$(teddycloud_api_base)/api/fileIndexV2?path=$(url_encode "$current_path")&special=library"

  curl --fail --silent --show-error "$index_url" | "$PYTHON_BIN" -c '
import json, sys
data = json.load(sys.stdin)
for item in data.get("files", []):
    if item.get("isDir") and item.get("name") != "..":
        print(item["name"])
'
}

collect_library_paths() {
  local current_path="$1"
  local child_name next_path

  while IFS= read -r child_name; do
    [ -z "$child_name" ] && continue
    if [ -z "$current_path" ]; then
      next_path="/$child_name"
    else
      next_path="$current_path/$child_name"
    fi

    printf '%s\n' "$next_path"
    collect_library_paths "$next_path"
  done < <(fetch_library_dirs "$current_path")
}

create_library_dir() {
  local folder_path="$1"
  local create_url

  create_url="$(teddycloud_api_base)/api/dirCreate?special=library"

  curl --fail --silent --show-error \
    -X POST \
    --data-raw "$folder_path" \
    "$create_url" >/dev/null
}

select_library_path() {
  local options_file selection new_folder_name new_path

  options_file="$(mktemp "${TMPDIR:-/tmp}/teddycloud-folders.XXXXXX")"
  {
    printf '/\n'
    collect_library_paths ""
    printf '[Neuen Ordner erstellen]\n'
  } | awk '!seen[$0]++' > "$options_file"

  selection="$(osascript <<EOF
set folderChoices to paragraphs of (do shell script "cat " & quoted form of "$options_file")
set chosenFolder to choose from list folderChoices with prompt "TeddyCloud-Zielordner waehlen" with title "${NOTIFICATION_TITLE}" default items {"/"}
if chosenFolder is false then
  error number -128
end if
return item 1 of chosenFolder
EOF
)"
  rm -f "$options_file"
  selection="$(trim "$selection")"

  if [ "$selection" != "[Neuen Ordner erstellen]" ]; then
    printf '%s\n' "$selection"
    return
  fi

  new_folder_name="$(osascript <<'EOF'
set dialogResult to display dialog "Neuen TeddyCloud-Ordner anlegen. Gib den relativen Pfad an, z. B. Bibi Blocksberg/Neue Folge" default answer "" with title "YT Audio Upload"
return text returned of dialogResult
EOF
)"
  new_folder_name="$(trim "$new_folder_name")"

  if [ -z "$new_folder_name" ]; then
    print_error "Kein Ordnername angegeben."
    exit 1
  fi

  if [[ "$new_folder_name" = /* ]]; then
    new_path="$new_folder_name"
  else
    new_path="/$new_folder_name"
  fi

  create_library_dir "$new_path"
  printf '%s\n' "$new_path"
}

create_taf() {
  local source_file="$1"
  local target_file="$2"

  require_file "${OPUS2TONIE_DIR}/opus2tonie.py" "opus2tonie.py"
  require_file "$PYTHON_BIN" "Python aus der Projekt-Umgebung"

  "$PYTHON_BIN" "${OPUS2TONIE_DIR}/opus2tonie.py" \
    --ffmpeg "$(command -v ffmpeg)" \
    --opusenc "$(command -v opusenc)" \
    "$source_file" "$target_file" >&2

  if [ ! -f "$target_file" ]; then
    print_error "Es wurde keine TAF-Datei erzeugt."
    exit 1
  fi
}

upload_taf() {
  local taf_file="$1"
  local library_path="$2"
  local upload_url

  if [ "$library_path" = "/" ]; then
    library_path=""
  fi

  upload_url="$(teddycloud_api_base)/api/fileUpload?path=$(url_encode "$library_path")&special=library"

  curl --fail --silent --show-error \
    -F "$(basename "$taf_file")=@${taf_file}" \
    "$upload_url" >/dev/null
}

main() {
  local url detected_title edited_title target_library_path source_audio_file final_taf_file

  require_command yt-dlp
  require_command ffmpeg "Installiere es z. B. mit: brew install ffmpeg"
  require_command opusenc "Installiere es z. B. mit: brew install opus-tools"
  require_command curl
  require_command osascript

  url="${1:-}"
  if [ -z "$url" ] && [ ! -t 0 ]; then
    url="$(cat)"
  fi
  url="$(trim "$url")"

  if [ -z "$url" ]; then
    usage
    exit 1
  fi

  if [ -z "$TEDDYCLOUD_URL" ]; then
    print_error "TEDDYCLOUD_URL ist nicht gesetzt."
    exit 1
  fi

  detected_title="$(detect_title "$url")"
  edited_title="$(edit_title "$detected_title")"
  target_library_path="$(select_library_path)"

  mkdir -p "$DOWNLOAD_DIR"
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/yt-audio.XXXXXX")"

  yt-dlp \
    --extract-audio \
    --audio-format wav \
    --output "${WORK_DIR}/%(title)s.%(ext)s" \
    "$url"

  source_audio_file="$(find "$WORK_DIR" -maxdepth 1 -type f -name '*.wav' | head -n 1)"
  if [ -z "$source_audio_file" ]; then
    print_error "Nach dem Download wurde keine WAV-Datei gefunden."
    exit 1
  fi

  final_taf_file="${DOWNLOAD_DIR}/${edited_title}.taf"
  create_taf "$source_audio_file" "$final_taf_file"

  if [ "$KEEP_SOURCE_AUDIO" = "1" ]; then
    mv "$source_audio_file" "${DOWNLOAD_DIR}/$(basename "$source_audio_file")"
  fi

  upload_taf "$final_taf_file" "$target_library_path"
  rm -f "$final_taf_file"

  echo "TAF in TeddyCloud hochgeladen: ${TEDDYCLOUD_URL}${target_library_path}"
  notify_success "$edited_title"
}

trap cleanup EXIT
trap on_error ERR

main "$@"
