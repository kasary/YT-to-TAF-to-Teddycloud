# YouTube zu TAF fuer TeddyCloud

Dieses Projekt enthaelt ein macOS-Script, das:

1. einen YouTube-Link entgegennimmt
2. den Titel vorab erkennen und bearbeiten laesst
3. Audio mit `yt-dlp` herunterlaedt
4. mit `opus2tonie` eine `.taf` erzeugt
5. die Datei in einen ausgewaehlten TeddyCloud-Ordner hochlaedt
6. die lokale `.taf` danach wieder entfernt

## Voraussetzungen

```bash
brew install yt-dlp ffmpeg opus-tools terminal-notifier
python3 -m venv .venv
./.venv/bin/pip install "protobuf<3.21"
git clone https://github.com/bailli/opus2tonie.git
```

## Konfiguration

Das Script nutzt Umgebungsvariablen statt persoenlicher Hardcodings:

```bash
export TEDDYCLOUD_URL="http://192.168.178.180/web"
```

Optional:

```bash
export DOWNLOAD_DIR="$HOME/Music/yt-audio"
export KEEP_SOURCE_AUDIO=1
export OPUS2TONIE_DIR="$PWD/opus2tonie"
export PYTHON_BIN="$PWD/.venv/bin/python3"
export TERMINAL_NOTIFIER_BIN="/opt/homebrew/bin/terminal-notifier"
```

## Nutzung

```bash
./download-audio.sh "https://youtube.com/watch?v=..."
```

Oder per `stdin`:

```bash
printf '%s\n' "https://youtube.com/watch?v=..." | ./download-audio.sh
```

## Verhalten

- Der Titel wird direkt nach dem Link erkannt und kann vor dem Download angepasst werden.
- Der Zielordner in TeddyCloud wird per Dialog aus der echten Library-Struktur ausgewaehlt.
- Wenn kein passender Ordner existiert, kann direkt ein neuer angelegt werden.
- Bei Erfolg erscheint eine Benachrichtigung `Titel - fertig`.
- Wenn `terminal-notifier` verfuegbar ist, ist die Erfolgs-Benachrichtigung klickbar und oeffnet `/web/tonies`.

## Kurzbefehl

In macOS `Kurzbefehle`:

1. `Eingabe abfragen` oder Share-Sheet-URL verwenden
2. `Shell-Skript ausfuehren`
3. Shell: `/bin/zsh`
4. Eingabe an `stdin` uebergeben
5. Script:

```zsh
export TEDDYCLOUD_URL="http://192.168.178.180/web"
/bin/bash "/ABSOLUTER/PFAD/ZU/download-audio.sh"
```
