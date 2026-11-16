#!/usr/bin/env bash
# Convert a screen recording (e.g. MP4) to a small GIF, optionally with a
# caption bar above the video. See scripts/README.md for the whole workflow.
#
#   scripts/mp4-to-gif.sh [-c CAPTIONS] INPUT [OUTPUT.gif]
#
# CAPTIONS is a text file, one caption per line: a start time in seconds,
# then the text. Each caption stays until the next one starts. Lines starting
# with # and empty lines are ignored.
#
#   0     Hover for every reference
#   9.5   Hold Cmd to preview the declaration
#
# The defaults are tuned for editor screencasts (flat dark background, text):
# few colours, no dithering, and frames that do not change are dropped
# instead of stored again. Tunable via environment:
#   GIF_FPS       frame rate                       (default: 10)
#   GIF_WIDTH     scale to this width, keep ratio  (default: original width)
#   GIF_COLORS    palette size, 2-256              (default: 32)
#   GIF_DITHER    paletteuse dither mode           (default: none)
#   CAPTION_BG    caption bar colour               (default: 0x1f1f1f, VS Code Dark Modern)
#   CAPTION_FG    caption text colour              (default: 0xe6e6e6)
#   CAPTION_FONT  font file                        (default: Helvetica Neue)
set -euo pipefail

usage() {
  printf 'Usage: %s [-c CAPTIONS] INPUT [OUTPUT.gif]\n' "${0##*/}" >&2
  exit 1
}

captions=""
while getopts "c:h" opt; do
  case "$opt" in
    c) captions="$OPTARG" ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[[ $# -ge 1 && $# -le 2 ]] || usage

for tool in ffmpeg ffprobe; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'Error: %s is required (macOS: brew install ffmpeg).\n' "$tool" >&2
    exit 1
  fi
done

input="$1"
if [[ ! -f "$input" ]]; then
  printf 'Error: input file not found: %s\n' "$input" >&2
  exit 1
fi
if [[ -n "$captions" && ! -f "$captions" ]]; then
  printf 'Error: captions file not found: %s\n' "$captions" >&2
  exit 1
fi

output="${2:-${input%.*}.gif}"
# Prefix relative paths so names beginning with a dash are safe.
[[ "$input" = /* ]] || input="./$input"
[[ "$output" = /* ]] || output="./$output"

if [[ "$output" != *.[gG][iI][fF] ]]; then
  printf 'Error: output must have a .gif extension.\n' >&2
  exit 1
fi
if [[ -e "$output" ]]; then
  printf 'Error: output already exists: %s\n' "$output" >&2
  exit 1
fi

fps="${GIF_FPS:-10}"
colors="${GIF_COLORS:-32}"
dither="${GIF_DITHER:-none}"
if [[ -n "${GIF_WIDTH:-}" ]]; then
  scale="scale=${GIF_WIDTH}:-2:flags=lanczos"
else
  scale="scale=iw:ih:flags=lanczos"
fi

# Caption bar: drawn at the source resolution, before scaling, so it scales
# together with the video and keeps its proportions at any GIF_WIDTH.
caption_filter=""
tmp=""
cleanup() { [[ -z "$tmp" ]] || rm -rf "$tmp"; }
trap cleanup EXIT

if [[ -n "$captions" ]]; then
  bg="${CAPTION_BG:-0x1f1f1f}"
  fg="${CAPTION_FG:-0xe6e6e6}"
  font="${CAPTION_FONT:-/System/Library/Fonts/HelveticaNeue.ttc}"
  if [[ ! -f "$font" ]]; then
    printf 'Error: font not found: %s (set CAPTION_FONT)\n' "$font" >&2
    exit 1
  fi

  height="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$input")"
  duration="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$input")"
  bar=$(( height * 12 / 100 ))
  (( bar >= 32 )) || bar=32
  size=$(( bar * 45 / 100 ))

  tmp="$(mktemp -d)"
  # Parse "start text" lines into a sorted "start<TAB>text" list.
  awk '!/^[[:space:]]*(#|$)/ {
         t = $1; $1 = ""; sub(/^[[:space:]]+/, "")
         if (t !~ /^[0-9]+(\.[0-9]+)?$/) { print "Error: bad start time: " t > "/dev/stderr"; exit 1 }
         printf "%s\t%s\n", t, $0
       }' "$captions" | sort -n -k1,1 > "$tmp/list"

  starts=()
  n=0
  while IFS=$'\t' read -r start text; do
    starts+=("$start")
    # Text goes through textfile= so it needs no filtergraph escaping.
    printf '%s' "$text" > "$tmp/caption$n.txt"
    n=$((n + 1))
  done < "$tmp/list"
  if (( n == 0 )); then
    printf 'Error: no captions in %s\n' "$captions" >&2
    exit 1
  fi

  caption_filter="pad=iw:ih+${bar}:0:${bar}:color=${bg}"
  for (( i = 0; i < n; i++ )); do
    if (( i + 1 < n )); then end="${starts[$((i + 1))]}"; else end="$duration"; fi
    caption_filter+=",drawtext=fontfile='${font}':textfile='${tmp}/caption${i}.txt'"
    caption_filter+=":fontsize=${size}:fontcolor=${fg}"
    caption_filter+=":x=(w-text_w)/2:y=(${bar}-${size})/2"
    caption_filter+=":enable='gte(t\\,${starts[$i]})*lt(t\\,${end})'"
  done
  caption_filter+=","
fi

# stats_mode=diff weights the palette towards moving parts, which suits
# screencasts; diff_mode=rectangle only redraws changed regions, which keeps
# static areas stable and the file smaller. mpdecimate drops frames that are
# (nearly) identical to the previous one, and -fps_mode vfr turns the gap into
# a longer frame delay instead of a stored duplicate.
ffmpeg -hide_banner -nostdin -n -i "$input" \
  -filter_complex "[0:v]${caption_filter}fps=${fps},${scale},mpdecimate,split[a][b];[a]palettegen=max_colors=${colors}:stats_mode=diff[p];[b][p]paletteuse=dither=${dither}:diff_mode=rectangle" \
  -fps_mode vfr -loop 0 "$output"

bytes="$(wc -c < "$output" | tr -d ' ')"
printf '\nSaved: %s (%s)\n' "$output" \
  "$(awk -v b="$bytes" 'BEGIN { printf (b >= 1048576 ? "%.1f MB" : "%.0f KB"), (b >= 1048576 ? b/1048576 : b/1024) }')"
