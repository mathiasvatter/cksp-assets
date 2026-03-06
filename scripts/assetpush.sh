#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: scripts/assetpush.sh <file-path> [commit-message]"
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

file_path="$1"
commit_message="${2:-add asset $(basename "$file_path")}"
repo_name="cksp-assets"
base_url="https://mathiasvatter.github.io/${repo_name}"

if [[ ! -f "$file_path" ]]; then
  echo "Error: file not found: $file_path"
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: current directory is not a git repository"
  exit 1
fi

git add "$file_path"

if git diff --cached --quiet; then
  echo "No staged changes for: $file_path"
  exit 1
fi

git commit -m "$commit_message"
git push

asset_url="${base_url}/${file_path}"
echo "$asset_url"

if command -v pbcopy >/dev/null 2>&1; then
  printf "%s" "$asset_url" | pbcopy
  echo "URL copied to clipboard (pbcopy)."
elif command -v xclip >/dev/null 2>&1; then
  printf "%s" "$asset_url" | xclip -selection clipboard
  echo "URL copied to clipboard (xclip)."
elif command -v wl-copy >/dev/null 2>&1; then
  printf "%s" "$asset_url" | wl-copy
  echo "URL copied to clipboard (wl-copy)."
else
  echo "Clipboard tool not found. URL printed above."
fi
