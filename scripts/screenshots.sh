#!/bin/zsh
# Renders README screenshots into docs/screenshots using sample data (never your real history).
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
swift build -c release >/dev/null
BIN="$(swift build -c release --show-bin-path)/Paster"
OUT="$ROOT/docs/screenshots"
LANG_ARG="${PASTER_SCREENSHOT_LANG:-zhHant}"
mkdir -p "$OUT"
DATA="$(mktemp -d)"
trap 'rm -rf "$DATA"' EXIT
render() { PASTER_DATA_DIR="$DATA" "$BIN" --snapshot "$OUT/$1.png" --scene "$2" ${3:-} -appLanguage "$LANG_ARG"; }
render panel-dark strip
render panel-light strip --light
render search search
render pinboard pinboard
render preview preview
render preferences-general prefs-general
render preferences-privacy prefs-privacy
