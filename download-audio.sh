#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${HOME}/Music/yt-audio}"
OPUS2TONIE_DIR="${OPUS2TONIE_DIR:-${SCRIPT_DIR}/opus2tonie}"
PYTHON_BIN="${PYTHON_BIN:-${SCRIPT_DIR}/.venv/bin/python3}"
TEDDYCLOUD_URL="${TEDDYCLOUD_URL:-}"
TERMINAL_NOTIFIER_BIN="${TERMINAL_NOTIFIER_BIN:-}"
KEEP_SOURCE_AUDIO="${KEEP_SOURCE_AUDIO:-0}"
TAF_BITRATE="${TAF_BITRATE:-64}"
TAF_CBR="${TAF_CBR:-1}"
TAF_FALLBACK_MODES="${TAF_FALLBACK_MODES:-48:1 32:1}"
WORK_DIR=""
DEFAULT_TITLE="Unbenannt"
NOTIFICATION_TITLE="YT Audio Download"
CURRENT_STEP=""

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
  TAF_BITRATE            bevorzugte Opus-Bitrate fuer opus2tonie, Standard: 64
  TAF_CBR                1 = CBR aktivieren, Standard: 1
  TAF_FALLBACK_MODES     Leerzeichen-getrennte Fallbacks wie 48:1 32:1
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
name = re.sub(r"[/:\\\\?%*|\"<>｜]", "-", name)
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
  if [ -n "$CURRENT_STEP" ]; then
    message="${message} Schritt: ${CURRENT_STEP}."
  fi
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

normalize_library_path() {
  local library_path="$1"

  if [ -z "$library_path" ] || [ "$library_path" = "/" ]; then
    printf '\n'
    return
  fi

  printf '%s\n' "${library_path#/}"
}

build_library_source() {
  local library_path="$1"
  local filename="$2"
  local normalized_path

  normalized_path="$(normalize_library_path "$library_path")"

  if [ -z "$normalized_path" ]; then
    printf 'lib://%s\n' "$filename"
  else
    printf 'lib://%s/%s\n' "$normalized_path" "$filename"
  fi
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
  local response

  index_url="$(teddycloud_api_base)/api/fileIndexV2?path=$(url_encode "$current_path")&special=library"
  response="$(curl --fail --silent --show-error "$index_url")" || {
    print_error "TeddyCloud-Ordner konnten nicht geladen werden: ${current_path:-/}"
    return 1
  }

  printf '%s' "$response" | "$PYTHON_BIN" -c '
import json, sys
data = json.load(sys.stdin)
for item in data.get("files", []):
    if item.get("isDir") and item.get("name") != "..":
        print(item["name"])
'
}

fetch_assignable_tags() {
  local response

  response="$(curl --fail --silent --show-error "$(teddycloud_api_base)/api/getTagIndex")" || {
    print_error "Die TeddyCloud-Tonie-Liste konnte nicht geladen werden."
    return 1
  }

  printf '%s' "$response" | "$PYTHON_BIN" -c '
import json
import sys

data = json.load(sys.stdin)

def clean(value):
    return (value or "").strip()

for tag in data.get("tags", []):
    if tag.get("type") != "tag":
        continue
    if tag.get("hide"):
        continue
    tonie = tag.get("tonieInfo") or {}
    series = clean(tonie.get("series"))
    episode = clean(tonie.get("episode"))
    model = clean(tonie.get("model"))
    uid = clean(tag.get("uid"))
    ruid = clean(tag.get("ruid"))
    source = clean(tag.get("source"))
    exists = bool(tag.get("exists", True))

    label = series or episode or uid or ruid
    if series and episode and episode != series:
        label = f"{series} - {episode}"
    elif episode and not series:
        label = episode
    if model:
        label = f"{label} ({model})"
    if uid:
        label = f"{label} [{uid}]"
    if not exists:
        label = f"{label} [nicht vorhanden]"

    print("\t".join([label, ruid, source]))
'
}

fetch_tag_record_by_ruid() {
  local wanted_ruid="$1"
  local response

  response="$(curl --fail --silent --show-error "$(teddycloud_api_base)/api/getTagIndex")" || {
    print_error "Die TeddyCloud-Tonie-Liste konnte nicht geladen werden."
    return 1
  }

  printf '%s' "$response" | "$PYTHON_BIN" -c '
import json
import sys

data = json.load(sys.stdin)
wanted = sys.argv[1].strip().lower()

def clean(value):
    return (value or "").strip()

for tag in data.get("tags", []):
    if tag.get("type") != "tag":
        continue
    if tag.get("hide"):
        continue
    tonie = tag.get("tonieInfo") or {}
    series = clean(tonie.get("series"))
    episode = clean(tonie.get("episode"))
    model = clean(tonie.get("model"))
    uid = clean(tag.get("uid"))
    ruid = clean(tag.get("ruid"))
    source = clean(tag.get("source"))
    exists = bool(tag.get("exists", True))

    if ruid.lower() != wanted:
        continue

    label = series or episode or uid or ruid
    if series and episode and episode != series:
        label = f"{series} - {episode}"
    elif episode and not series:
        label = episode
    if model:
        label = f"{label} ({model})"
    if uid:
        label = f"{label} [{uid}]"
    if not exists:
        label = f"{label} [nicht vorhanden]"

    print("\t".join([label, ruid, source]))
    break
' "$wanted_ruid"
}

fetch_tag_source_by_ruid() {
  local ruid="$1"
  local response

  response="$(curl --fail --silent --show-error "$(teddycloud_api_base)/api/getTagIndex")" || {
    print_error "Die TeddyCloud-Tonie-Liste konnte nicht zur Verifikation geladen werden."
    return 1
  }

  printf '%s' "$response" | "$PYTHON_BIN" -c '
import json
import sys

data = json.load(sys.stdin)
target_ruid = sys.argv[1].strip().lower()

for tag in data.get("tags", []):
    ruid = (tag.get("ruid") or "").strip().lower()
    if ruid == target_ruid:
        print((tag.get("source") or "").strip())
        break
' "$ruid"
}

assign_uploaded_file_prompt() {
  local answer

  answer="$(osascript <<'EOF'
button returned of (display dialog "Soll die hochgeladene Datei direkt einer vorhandenen Tonie/Figur zugewiesen werden?" with title "YT Audio Upload" buttons {"Nein", "Ja"} default button "Nein")
EOF
)"

  [ "$(trim "$answer")" = "Ja" ]
}

choose_assignment_target() {
  local tags_file choices_file selection selected_index record

  tags_file="$(mktemp "${TMPDIR:-/tmp}/teddycloud-tags.XXXXXX")"
  choices_file="$(mktemp "${TMPDIR:-/tmp}/teddycloud-tag-labels.XXXXXX")"

  fetch_assignable_tags > "$tags_file"
  if [ ! -s "$tags_file" ]; then
    rm -f "$tags_file" "$choices_file"
    print_error "Es wurden keine passenden TeddyCloud-Tags gefunden."
    return 1
  fi

  "$PYTHON_BIN" -c '
import sys

tags_path = sys.argv[1]
choices_path = sys.argv[2]

with open(tags_path, "r", encoding="utf-8") as tags_file, open(choices_path, "w", encoding="utf-8") as choices_file:
    for index, raw_line in enumerate(tags_file, start=1):
        line = raw_line.rstrip("\n")
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        label = parts[0].strip()
        if not label:
            continue
        choices_file.write(f"{index:03d} | {label}\n")
' "$tags_file" "$choices_file"

  if [ ! -s "$choices_file" ]; then
    rm -f "$tags_file" "$choices_file"
    print_error "Die Tonie/Figur-Liste ist leer."
    return 1
  fi

  if ! selection="$(osascript - "$choices_file" "$NOTIFICATION_TITLE" <<'EOF'
on run argv
set choicesPath to item 1 of argv
set dialogTitle to item 2 of argv
set tagChoicesText to read POSIX file choicesPath as «class utf8»
set tagChoices to paragraphs of tagChoicesText
set chosenTag to choose from list tagChoices with prompt "Vorhandene Tonie/Figur waehlen" with title dialogTitle
if chosenTag is false then
  error number -128
end if
return item 1 of chosenTag
end run
EOF
)"
  then
    rm -f "$tags_file" "$choices_file"
    return 1
  fi

  selection="$(trim "$selection")"
  selected_index="$(printf '%s\n' "$selection" | cut -d '|' -f1 | tr -d ' ')"

  if [ -z "$selected_index" ]; then
    rm -f "$tags_file" "$choices_file"
    print_error "Die Tonie/Figur-Auswahl konnte nicht ausgewertet werden."
    return 1
  fi

  record="$("$PYTHON_BIN" -c '
import sys

tags_path = sys.argv[1]
selected_index = int(sys.argv[2])

with open(tags_path, "r", encoding="utf-8") as tags_file:
    for index, raw_line in enumerate(tags_file, start=1):
        if index == selected_index:
            print(raw_line.rstrip("\n"))
            break
' "$tags_file" "$selected_index")"

  rm -f "$tags_file" "$choices_file"

  if [ -z "$record" ]; then
    print_error "Zur ausgewaehlten Tonie/Figur konnte kein passender Datensatz gefunden werden: ${selected_index}"
    return 1
  fi

  printf '%s\n' "$record"
}

confirm_source_overwrite() {
  local label="$1"
  local current_source="$2"
  local new_source="$3"
  local answer

  if [ -z "$current_source" ] || [ "$current_source" = "$new_source" ]; then
    return 0
  fi

  answer="$(osascript - "$label" "$current_source" "$new_source" <<'EOF'
on run argv
set tagLabel to item 1 of argv
set currentSource to item 2 of argv
set newSource to item 3 of argv
set dialogText to "Die ausgewaehlte Tonie/Figur hat bereits eine Quelle." & return & return & "Tonie: " & tagLabel & return & "Aktuell: " & currentSource & return & "Neu: " & newSource & return & return & "Soll die Quelle ueberschrieben werden?"
return button returned of (display dialog dialogText with title "YT Audio Upload" buttons {"Abbrechen", "Ueberschreiben"} default button "Ueberschreiben" cancel button "Abbrechen")
end run
EOF
)"

  [ "$(trim "$answer")" = "Ueberschreiben" ]
}

assign_tag_source() {
  local ruid="$1"
  local new_source="$2"
  local verified_source

  if [ -z "$ruid" ]; then
    print_error "Die Tonie/Figur-Zuweisung wurde ohne gueltige RUID aufgerufen."
    return 1
  fi

  if [ -z "$new_source" ]; then
    print_error "Die neue TeddyCloud-Quelle fuer die Tonie/Figur ist leer."
    return 1
  fi

  curl --fail --silent --show-error \
    -X POST \
    --data-raw "source=$(url_encode "$new_source")" \
    "$(teddycloud_api_base)/content/json/set/${ruid}" >/dev/null || {
      print_error "Die Datei konnte keiner Tonie/Figur zugewiesen werden. RUID: ${ruid}"
      return 1
    }

  verified_source="$(fetch_tag_source_by_ruid "$ruid")" || return 1
  verified_source="$(trim "$verified_source")"

  if [ "$verified_source" != "$new_source" ]; then
    print_error "Die Tonie/Figur-Zuweisung wurde von TeddyCloud nicht wie erwartet gespeichert. Erwartet: ${new_source} | Gefunden: ${verified_source:-<leer>}"
    return 1
  fi
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
    "$create_url" >/dev/null || {
      print_error "Der TeddyCloud-Ordner konnte nicht erstellt werden: ${folder_path}"
      return 1
    }
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
  local bitrate="$TAF_BITRATE"
  local cbr_flag="$TAF_CBR"
  local mode
  local tried_modes=()

  require_file "${OPUS2TONIE_DIR}/opus2tonie.py" "opus2tonie.py"
  require_file "$PYTHON_BIN" "Python aus der Projekt-Umgebung"

  for mode in "${bitrate}:${cbr_flag}" $TAF_FALLBACK_MODES; do
    bitrate="${mode%%:*}"
    cbr_flag="${mode##*:}"
    tried_modes+=("${bitrate}:${cbr_flag}")

    rm -f "$target_file"

    if [ "$cbr_flag" = "1" ]; then
      if "$PYTHON_BIN" "${OPUS2TONIE_DIR}/opus2tonie.py" \
        --ffmpeg "$(command -v ffmpeg)" \
        --opusenc "$(command -v opusenc)" \
        --bitrate "$bitrate" \
        --cbr \
        "$source_file" "$target_file" >&2; then
        break
      fi
    else
      if "$PYTHON_BIN" "${OPUS2TONIE_DIR}/opus2tonie.py" \
        --ffmpeg "$(command -v ffmpeg)" \
        --opusenc "$(command -v opusenc)" \
        --bitrate "$bitrate" \
        "$source_file" "$target_file" >&2; then
        break
      fi
    fi
  done

  if [ ! -f "$target_file" ]; then
    print_error "Es wurde keine TAF-Datei erzeugt. Versucht wurden diese Modi: ${tried_modes[*]}."
    exit 1
  fi
}

upload_taf() {
  local taf_file="$1"
  local library_path="$2"
  local normalized_path
  local upload_url

  normalized_path="$(normalize_library_path "$library_path")"

  upload_url="$(teddycloud_api_base)/api/fileUpload?path=$(url_encode "$normalized_path")&special=library"

  curl --fail --silent --show-error \
    -F "upload=@${taf_file}" \
    "$upload_url" >/dev/null || {
      print_error "Upload nach TeddyCloud fehlgeschlagen fuer Ordner: /${normalized_path}"
      return 1
    }
}

main() {
  local url detected_title edited_title target_library_path source_audio_file final_taf_file
  local library_source tag_record tag_label tag_ruid tag_source
  local assign_after_upload=0

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
  CURRENT_STEP="TeddyCloud-Ordnerauswahl"
  target_library_path="$(select_library_path)"
  library_source="$(build_library_source "$target_library_path" "${edited_title}.taf")"

  CURRENT_STEP="Tonie-Auswahl"
  if assign_uploaded_file_prompt; then
    if ! tag_record="$(choose_assignment_target)"; then
      exit 1
    fi

    tag_label="$(printf '%s' "$tag_record" | cut -f1)"
    tag_ruid="$(printf '%s' "$tag_record" | cut -f2)"
    tag_source="$(printf '%s' "$tag_record" | cut -f3-)"

    if confirm_source_overwrite "$tag_label" "$tag_source" "$library_source"; then
      assign_after_upload=1
    else
      print_error "Die Tonie/Figur-Zuweisung wurde vor dem Download abgebrochen."
      exit 1
    fi
  fi

  CURRENT_STEP="Vorbereitung"
  mkdir -p "$DOWNLOAD_DIR"
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/yt-audio.XXXXXX")"

  CURRENT_STEP="YouTube-Download"
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
  CURRENT_STEP="TAF-Konvertierung"
  create_taf "$source_audio_file" "$final_taf_file"

  if [ "$KEEP_SOURCE_AUDIO" = "1" ]; then
    mv "$source_audio_file" "${DOWNLOAD_DIR}/$(basename "$source_audio_file")"
  fi

  CURRENT_STEP="TeddyCloud-Upload"
  upload_taf "$final_taf_file" "$target_library_path"

  CURRENT_STEP="Tonie-Zuweisung"
  if [ "$assign_after_upload" = "1" ]; then
    assign_tag_source "$tag_ruid" "$library_source"
    echo "Tonie/Figur erfolgreich zugewiesen: ${tag_label}"
  fi

  rm -f "$final_taf_file"

  CURRENT_STEP=""
  echo "TAF in TeddyCloud hochgeladen: ${TEDDYCLOUD_URL}${target_library_path}"
  notify_success "$edited_title"
}

trap cleanup EXIT
trap on_error ERR

main "$@"
