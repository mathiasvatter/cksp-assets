#!/usr/bin/env bash

# Erzeugt die abgeleiteten Video-Dateien unterhalb von assets/video/. Die
# Ausgabe spiegelt dabei die Ordnerstruktur unter assets/ wider:
#
#   GIF-Quelle:
#   assets/changelog.gif  ->  assets/video/changelog.mp4
#                             assets/video/changelog.jpg    (Poster)
#                             assets/video/changelog.sha256 (Staleness-Marker)
#
#   MP4-Quelle: schon webtauglich, deshalb wird nur das Poster gebraucht.
#   assets/demo.mp4       ->  assets/video/demo.jpg
#                             assets/video/demo.sha256
#
# Die abgeleiteten Dateien werden NICHT committet (siehe .gitignore) - der
# Pages-Workflow erzeugt sie bei jedem Push neu und cacht sie zwischen Runs.
# Deshalb entscheidet nicht die mtime ueber "schon aktuell", sondern der
# SHA-256 der Quelldatei: ein Checkout setzt mtimes neu, Hashes bleiben stabil.

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
# gegen die Magic Bytes pruefen.
is_real_gif() {
  [[ "$(head -c 3 "$1" 2>/dev/null)" == "GIF" ]]
}

# Bei MP4/MOV steht die Boxgroesse voran, der Typ folgt ab Byte 5.
is_real_mp4() {
  [[ "$(head -c 8 "$1" 2>/dev/null | tail -c 4)" == "ftyp" ]]
}

# Erstes Frame als Poster, damit <video preload="none"> etwas anzeigen kann.
write_poster() {
  ffmpeg -nostdin -y -v error -i "$1" \
    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2:flags=lanczos" \
    -frames:v 1 -q:v 4 "$2"
}

converted=0
skipped=0
failed=0
bytes_gif=0
bytes_mp4=0

# GIF und MP4 gleichen Namens wuerden sich Poster und Marker gegenseitig
# ueberschreiben. Lieber laut abbrechen als still das falsche Poster liefern.
while IFS= read -r gif; do
  rel="${gif#"$src_dir"/}"
  [[ "$rel" == video/* ]] && continue
  if [[ -f "$src_dir/${rel%.*}.mp4" ]]; then
    echo "Error: '$gif' und '$src_dir/${rel%.*}.mp4' teilen sich denselben Basisnamen." >&2
    echo "       Die abgeleiteten Dateien wuerden kollidieren - eine der beiden umbenennen." >&2
    exit 1
  fi
done < <(find "$src_dir" -type f -iname '*.gif' | sort)

# --- GIF-Quellen: MP4 + Poster erzeugen ------------------------------------
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

  write_poster "$gif" "$poster"

  printf '%s' "$current_hash" > "$stamp"

  size_gif="$(file_size "$gif")"
  size_mp4="$(file_size "$mp4")"
  bytes_gif=$((bytes_gif + size_gif))
  bytes_mp4=$((bytes_mp4 + size_mp4))
  converted=$((converted + 1))

  printf '  %-46s %9s -> %9s\n' "$rel" "$(human_size "$size_gif")" "$(human_size "$size_mp4")"
done < <(find "$src_dir" -type f -iname '*.gif' | sort)

# --- MP4-Quellen: nur das Poster ------------------------------------------
# Ein eingechecktes MP4 ist bereits das Auslieferungsformat. Neu zu encodieren
# wuerde die Qualitaet nur ein zweites Mal beschaedigen, also bleibt es liegen.
postered=0
while IFS= read -r mp4src; do
  rel="${mp4src#"$src_dir"/}"

  [[ "$rel" == video/* ]] && continue

  if ! is_real_mp4 "$mp4src"; then
    echo "  skip (kein MP4-Inhalt, evtl. nicht ausgecheckter LFS-Zeiger): $mp4src" >&2
    failed=$((failed + 1))
    continue
  fi

  base="${rel%.*}"
  poster="$out_dir/$base.jpg"
  stamp="$out_dir/$base.sha256"

  mkdir -p "$(dirname "$poster")"

  current_hash="$(hash_file "$mp4src")"
  if [[ -f "$poster" && -f "$stamp" && "$(cat "$stamp")" == "$current_hash" ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  if ! write_poster "$mp4src" "$poster"; then
    echo "  FEHLER beim Poster: $mp4src" >&2
    failed=$((failed + 1))
    continue
  fi

  printf '%s' "$current_hash" > "$stamp"
  postered=$((postered + 1))

  printf '  %-46s %9s   (Poster)\n' "$rel" "$(human_size "$(file_size "$mp4src")")"
done < <(find "$src_dir" -type f -iname '*.mp4' | sort)

# Verwaiste Ausgaben entfernen, wenn die Quelldatei geloescht wurde
removed=0
if [[ -d "$out_dir" ]]; then
  while IFS= read -r derived; do
    rel="${derived#"$out_dir"/}"
    base="${rel%.*}"
    if [[ ! -f "$src_dir/$base.gif" && ! -f "$src_dir/$base.mp4" ]]; then
      rm -f "$derived"
      removed=$((removed + 1))
    fi
  done < <(find "$out_dir" -type f \( -name '*.mp4' -o -name '*.jpg' -o -name '*.sha256' \) 2>/dev/null | sort)
  find "$out_dir" -type d -empty -delete 2>/dev/null || true
fi

echo
echo "Konvertiert: $converted, Poster: $postered, unveraendert: $skipped, entfernt: $removed, fehlgeschlagen: $failed"
if [[ $bytes_gif -gt 0 ]]; then
  echo "Gesamt: $(human_size "$bytes_gif") GIF -> $(human_size "$bytes_mp4") MP4"
fi

[[ $failed -eq 0 ]]
