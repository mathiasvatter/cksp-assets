#!/usr/bin/env bash
# Compress a video to MP4 while preserving its resolution.
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  printf 'Usage: %s INPUT [OUTPUT.mp4]\n' "${0##*/}" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  printf 'Error: ffmpeg is required (macOS: brew install ffmpeg).\n' >&2
  exit 1
fi

input="$1"
if [[ ! -f "$input" ]]; then
  printf 'Error: input file not found: %s\n' "$input" >&2
  exit 1
fi

output="${2:-${input%.*}-kompakt.mp4}"
# Prefix relative paths so names beginning with a dash are safe.
[[ "$input" = /* ]] || input="./$input"
[[ "$output" = /* ]] || output="./$output"

if [[ "$output" != *.[mM][pP]4 ]]; then
  printf 'Error: output must have an .mp4 extension.\n' >&2
  exit 1
fi
if [[ -e "$output" ]]; then
  printf 'Error: output already exists: %s\n' "$output" >&2
  exit 1
fi

ffmpeg -hide_banner -nostdin -n -i "$input" \
  -map 0:v:0 -map '0:a?' \
  -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p \
  -c:a aac -b:a 192k -movflags +faststart "$output"

printf '\nSaved: %s\n' "$output"
