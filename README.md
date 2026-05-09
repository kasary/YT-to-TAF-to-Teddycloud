# YouTube to TAF for TeddyCloud

## English

This repository contains a macOS-focused script that:

1. accepts a YouTube URL
2. lets you review and edit the detected title
3. lets you choose a TeddyCloud target folder
4. optionally lets you choose an existing TeddyCloud Tonie/tag
5. downloads the audio with `yt-dlp`
6. converts it to `.taf` with `opus2tonie`
7. uploads the file to TeddyCloud
8. assigns the uploaded file to the selected Tonie/tag
9. removes the local `.taf` again after a successful upload

### Requirements

```bash
brew install yt-dlp ffmpeg opus-tools terminal-notifier
python3 -m venv .venv
./.venv/bin/pip install "protobuf<3.21"
git clone https://github.com/bailli/opus2tonie.git
```

### Quick setup

If the repository is already cloned locally, run:

```bash
chmod +x setup-macos.sh
./setup-macos.sh
```

The setup script installs the required Homebrew packages, creates the local Python virtual environment, installs `protobuf<3.21`, and clones `opus2tonie` next to the project if needed.

### Bootstrap install from GitHub

If you want a single script that clones this repository first and then runs the local setup:

```bash
curl -LO https://raw.githubusercontent.com/kasary/YT-to-TAF-to-Teddycloud/main/install-from-github-macos.sh
chmod +x install-from-github-macos.sh
./install-from-github-macos.sh
```

By default it clones into `./YT-to-TAF-to-Teddycloud`.

### Configuration

The script uses environment variables instead of hardcoded personal settings:

```bash
export TEDDYCLOUD_URL="http://YOUR-TEDDYCLOUD-HOST/web"
```

Optional:

```bash
export DOWNLOAD_DIR="$HOME/Music/yt-audio"
export KEEP_SOURCE_AUDIO=1
export TAF_BITRATE=64
export TAF_CBR=1
export TAF_FALLBACK_MODES="48:1 32:1"
export OPUS2TONIE_DIR="$PWD/opus2tonie"
export PYTHON_BIN="$PWD/.venv/bin/python3"
export TERMINAL_NOTIFIER_BIN="/opt/homebrew/bin/terminal-notifier"
```

### Usage

```bash
./download-audio.sh "https://youtube.com/watch?v=..."
```

Or via `stdin`:

```bash
printf '%s\n' "https://youtube.com/watch?v=..." | ./download-audio.sh
```

### Behavior

- The title is detected immediately and can be edited before the download starts.
- The TeddyCloud target folder is chosen from the live library structure.
- If needed, a new TeddyCloud folder can be created during the flow.
- The optional Tonie/tag selection happens before the download so the final assignment can run deterministically after upload.
- The Tonie/tag list is loaded from the live TeddyCloud tag index.
- Tags with `exists = false` can also be displayed and assigned.
- If the selected Tonie/tag already has another source, the script asks before overwriting it.
- The assignment is verified against TeddyCloud after upload.
- TAF creation starts with `64 kbps CBR` and automatically retries smaller fallback modes if needed.
- On success, a `Title - finished` notification is shown.
- If `terminal-notifier` is available, the success notification is clickable and opens `/web/tonies`.
- The generated `.taf` is removed locally after a successful upload.

### macOS Shortcut

In the macOS Shortcuts app:

1. add `Ask for Input` or use a Share Sheet URL
2. add `Run Shell Script`
3. shell: `/bin/zsh`
4. pass input to `stdin`
5. script:

```zsh
export TEDDYCLOUD_URL="http://YOUR-TEDDYCLOUD-HOST/web"
/bin/bash "/ABSOLUTE/PATH/TO/download-audio.sh"
```

### Notes

- The repository expects `opus2tonie` as an external cloned directory next to the script and does not version it.
- A local Python virtual environment is used on purpose so `protobuf<3.21` stays compatible with `opus2tonie`.
- The current interaction flow is macOS-focused because dialogs and notifications use `osascript`.

---

## Deutsch

Dieses Repository enthaelt ein macOS-fokussiertes Script, das:

1. einen YouTube-Link entgegennimmt
2. den erkannten Titel pruefen und bearbeiten laesst
3. einen TeddyCloud-Zielordner waehlen laesst
4. optional direkt einen vorhandenen TeddyCloud-Tonie/Tag waehlen laesst
5. Audio mit `yt-dlp` herunterlaedt
6. mit `opus2tonie` eine `.taf` erzeugt
7. die Datei zu TeddyCloud hochlaedt
8. die hochgeladene Datei dem ausgewaehlten Tonie/Tag zuweist
9. die lokale `.taf` nach erfolgreichem Upload wieder entfernt

### Voraussetzungen

```bash
brew install yt-dlp ffmpeg opus-tools terminal-notifier
python3 -m venv .venv
./.venv/bin/pip install "protobuf<3.21"
git clone https://github.com/bailli/opus2tonie.git
```

### Schnellstart Setup

Wenn das Repository bereits lokal geklont wurde, einfach ausfuehren:

```bash
chmod +x setup-macos.sh
./setup-macos.sh
```

Das Setup-Script installiert die benoetigten Homebrew-Pakete, legt die lokale Python-Umgebung an, installiert `protobuf<3.21` und klont bei Bedarf `opus2tonie` neben das Projekt.

### Bootstrap-Installation direkt von GitHub

Wenn du lieber ein einzelnes Script verwenden willst, das zuerst dieses Repository klont und danach direkt das lokale Setup startet:

```bash
curl -LO https://raw.githubusercontent.com/kasary/YT-to-TAF-to-Teddycloud/main/install-from-github-macos.sh
chmod +x install-from-github-macos.sh
./install-from-github-macos.sh
```

Standardmaessig wird dabei nach `./YT-to-TAF-to-Teddycloud` geklont.

### Konfiguration

Das Script nutzt Umgebungsvariablen statt persoenlicher Hardcodings:

```bash
export TEDDYCLOUD_URL="http://DEIN-TEDDYCLOUD-HOST/web"
```

Optional:

```bash
export DOWNLOAD_DIR="$HOME/Music/yt-audio"
export KEEP_SOURCE_AUDIO=1
export TAF_BITRATE=64
export TAF_CBR=1
export TAF_FALLBACK_MODES="48:1 32:1"
export OPUS2TONIE_DIR="$PWD/opus2tonie"
export PYTHON_BIN="$PWD/.venv/bin/python3"
export TERMINAL_NOTIFIER_BIN="/opt/homebrew/bin/terminal-notifier"
```

### Nutzung

```bash
./download-audio.sh "https://youtube.com/watch?v=..."
```

Oder per `stdin`:

```bash
printf '%s\n' "https://youtube.com/watch?v=..." | ./download-audio.sh
```

### Verhalten

- Der Titel wird direkt erkannt und kann vor dem Download angepasst werden.
- Der TeddyCloud-Zielordner wird aus der echten Library-Struktur ausgewaehlt.
- Falls noetig, kann im Ablauf direkt ein neuer TeddyCloud-Ordner erstellt werden.
- Die optionale Tonie/Tag-Auswahl passiert vor dem Download, damit die finale Zuweisung nach dem Upload deterministisch ausgefuehrt werden kann.
- Die Tonie/Tag-Liste wird aus dem echten TeddyCloud-Tag-Index geladen.
- Auch Tags mit `exists = false` koennen angezeigt und zugewiesen werden.
- Wenn der ausgewaehlte Tonie/Tag bereits eine andere Quelle hat, wird vor dem Ueberschreiben gefragt.
- Die Zuweisung wird nach dem Upload direkt gegen TeddyCloud verifiziert.
- Die TAF-Erzeugung startet mit `64 kbps CBR` und versucht bei Bedarf automatisch kleinere Fallback-Modi.
- Bei Erfolg erscheint eine Benachrichtigung im Format `Titel - fertig`.
- Wenn `terminal-notifier` verfuegbar ist, ist die Erfolgs-Benachrichtigung klickbar und oeffnet `/web/tonies`.
- Die erzeugte `.taf` wird nach erfolgreichem Upload lokal wieder entfernt.

### macOS Kurzbefehl

In der macOS-App `Kurzbefehle`:

1. `Eingabe abfragen` hinzufuegen oder eine Share-Sheet-URL verwenden
2. `Shell-Skript ausfuehren` hinzufuegen
3. Shell: `/bin/zsh`
4. Eingabe an `stdin` uebergeben
5. Script:

```zsh
export TEDDYCLOUD_URL="http://DEIN-TEDDYCLOUD-HOST/web"
/bin/bash "/ABSOLUTER/PFAD/ZU/download-audio.sh"
```

### Hinweise

- Das Repository erwartet `opus2tonie` als extern geklonten Ordner neben dem Script und versioniert ihn nicht mit.
- Fuer die TAF-Erzeugung wird bewusst eine lokale Python-Umgebung verwendet, damit `protobuf<3.21` kompatibel zu `opus2tonie` bleibt.
- Der aktuelle Interaktionsfluss ist macOS-fokussiert, weil Dialoge und Benachrichtigungen `osascript` verwenden.
