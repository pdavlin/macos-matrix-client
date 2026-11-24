#!/bin/zsh
# Renders .icon documents with ictool and builds a contact sheet in renders/.
# Usage: design/icon/render.sh [name ...]
# A name is AppIcon (this folder) or a folder name in concepts/ without ".icon".
# With no names, it renders AppIcon. SHEET sets the sheet file name
# (default contact-sheet.png). renders/ is not committed.
set -euo pipefail

HERE="${0:A:h}"
OUT="$HERE/renders"
SHEET="${SHEET:-contact-sheet.png}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
IC="${DEVELOPER_DIR:h}/Applications/Icon Composer.app/Contents/Executables/ictool"
RENDITIONS=(Default Dark TintedLight TintedDark ClearLight ClearDark)
mkdir -p "$OUT"

concepts=("$@")
(( ${#concepts} == 0 )) && concepts=(AppIcon)

source_of() {
  if [[ -d "$HERE/$1.icon" ]]; then
    echo "$HERE/$1.icon"
  else
    echo "$HERE/concepts/$1.icon"
  fi
}

render() {
  local name=$1 rendition=$2 size=$3 file=$4
  shift 4
  "$IC" "$(source_of "$name")" --export-image --output-file "$OUT/$file" \
    --platform macOS --rendition "$rendition" --width "$size" --height "$size" --scale 1 "$@" > /dev/null
}

sheet_args=()
for name in $concepts; do
  row=()
  for r in $RENDITIONS; do
    tint=()
    [[ $r == Tinted* ]] && tint=(--tint-color 0.6 --tint-strength 0.75)
    render "$name" "$r" 512 "$name-$r.png" $tint
    row+=("$OUT/$name-$r.png")
  done
  for px in 16 32 64; do
    render "$name" Default $px "$name-${px}px.png"
  done
  render "$name" Default 512 "$name-gen26.png" --design-generation 26
  row+=("$OUT/$name-32px.png" "$OUT/$name-16px.png+$OUT/$name-32px.png+$OUT/$name-64px.png")
  label="${name#concept-}"
  [[ $name == voices-* ]] && label="${${name#voices-}/-/ }"
  sheet_args+=(--row "$label" $row)
done

swift "$HERE/contact-sheet.swift" "$OUT/$SHEET" 256 $sheet_args
echo "wrote $OUT/$SHEET"
