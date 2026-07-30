#!/usr/bin/env bash

# Wandelt jedes GIF unterhalb von assets/ in ein MP4 (H.264) plus ein
# JPEG-Poster um. Die Ausgabe landet in assets/video/ und spiegelt dabei die
# Ordnerstruktur unter assets/ wider:
#
#   assets/changelog.gif  ->  assets/video/changelog.mp4
#                             assets/video/changelog.jpg    (Poster)
#                             assets/video/changelog.sha256 (Staleness-Marker)
#
# Die abgeleiteten Dateien werden NICHT committet (siehe .gitignore) - der
# Pages-Workflow erzeugt sie bei jedem Push neu und cacht sie zwischen Runs.
# Deshalb entscheidet nicht die mtime ueber "schon aktuell", sondern der
# SHA-256 des Quell-GIFs: ein Checkout setzt mtimes neu, Hashes bleiben stabil.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

src_dir="assets"
out_dir="assets/video"

# Ueber Environment ueberschreibbar, falls ein Asset mehr Qualitaet braucht.
crf="${GIF_MP4_CRF:-30}"
fps="${GIF_MP4_FPS:-20}"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Error: ffmpeg not found. Install it with 'brew install ffmpeg' or 'apt-get install ffmpeg'." >&2
  exit 1
fi

file_size() {
  wc -c < "$1" | tr -d ' '
}

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

human_size() {
  awk -v b="$1" 'BEGIN {
    if (b >= 1048576)   printf "%.1f MB", b / 1048576;
    else if (b >= 1024) printf "%.0f KB", b / 1024;
    else                printf "%d B", b;
  }'
}

# Git LFS speichert nicht ausgecheckte Dateien als kleine Textzeiger. ffmpeg
# wuerde daran mit einer unverstaendlichen Meldung scheitern, daher vorher
# gegen die GIF-Magic-Bytes pruefen.
is_real_gif() {
  [[ "$(head -c 3 "$1" 2>/dev/null)" == "GIF" ]]
}

converted=0
skipped=0
failed=0
bytes_gif=0
bytes_mp4=0

while IFS= read -r gif; do
  rel="${gif#"$src_dir"/}"

  # Die eigene Ausgabe nie erneut einlesen
  [[ "$rel" == video/* ]] && continue

  if ! is_real_gif "$gif"; then
    echo "  skip (kein GIF-Inhalt, evtl. nicht ausgecheckter LFS-Zeiger): $gif" >&2
    failed=$((failed + 1))
    continue
  fi

  base="${rel%.*}"
  mp4="$out_dir/$base.mp4"
  poster="$out_dir/$base.jpg"
  stamp="$out_dir/$base.sha256"

  mkdir -p "$(dirname "$mp4")"

  current_hash="$(hash_file "$gif")"
  if [[ -f "$mp4" && -f "$poster" && -f "$stamp" && "$(cat "$stamp")" == "$current_hash" ]]; then
    skipped=$((skipped + 1))
    bytes_gif=$((bytes_gif + $(file_size "$gif")))
    bytes_mp4=$((bytes_mp4 + $(file_size "$mp4")))
    continue
  fi

  # yuv420p + gerade Kantenlaengen, sonst weigert sich H.264.
  # 'tune stillimage' passt zu Screencasts: lange statische Passagen, wenig Rauschen.
  # -nostdin ist Pflicht: ohne das liest ffmpeg die restlichen Dateinamen
  # aus der while-Schleife weg.
  if ! ffmpeg -nostdin -y -v error -i "$gif" \
      -vf "fps=$fps,scale=trunc(iw/2)*2:trunc(ih/2)*2:flags=lanczos" \
      -c:v libx264 -crf "$crf" -preset slow -tune stillimage \
      -pix_fmt yuv420p -movflags +faststart -an \
      "$mp4"; then
    echo "  FEHLER bei der Konvertierung: $gif" >&2
    failed=$((failed + 1))
    continue
  fi

  # Erstes Frame als Poster, damit <video preload="none"> etwas anzeigen kann.
  ffmpeg -nostdin -y -v error -i "$gif" \
    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2:flags=lanczos" \
    -frames:v 1 -q:v 4 "$poster"

  printf '%s' "$current_hash" > "$stamp"

  size_gif="$(file_size "$gif")"
  size_mp4="$(file_size "$mp4")"
  bytes_gif=$((bytes_gif + size_gif))
  bytes_mp4=$((bytes_mp4 + size_mp4))
  converted=$((converted + 1))

  printf '  %-46s %9s -> %9s\n' "$rel" "$(human_size "$size_gif")" "$(human_size "$size_mp4")"
done < <(find "$src_dir" -type f -iname '*.gif' | sort)

# Verwaiste Ausgaben entfernen, wenn das Quell-GIF geloescht wurde
removed=0
if [[ -d "$out_dir" ]]; then
  while IFS= read -r derived; do
    rel="${derived#"$out_dir"/}"
    if [[ ! -f "$src_dir/${rel%.*}.gif" ]]; then
      rm -f "$derived"
      removed=$((removed + 1))
    fi
  done < <(find "$out_dir" -type f \( -name '*.mp4' -o -name '*.jpg' -o -name '*.sha256' \) 2>/dev/null | sort)
  find "$out_dir" -type d -empty -delete 2>/dev/null || true
fi

echo
echo "Konvertiert: $converted, unveraendert: $skipped, entfernt: $removed, fehlgeschlagen: $failed"
if [[ $bytes_gif -gt 0 ]]; then
  echo "Gesamt: $(human_size "$bytes_gif") GIF -> $(human_size "$bytes_mp4") MP4"
fi

[[ $failed -eq 0 ]]
