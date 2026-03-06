#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: scripts/assetpush.sh [file-path] [commit-message]"
}

repo_name="cksp-assets"
base_url="https://mathiasvatter.github.io/${repo_name}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: current directory is not a git repository"
  exit 1
fi

single_file_mode=false
file_path=""

if [[ $# -gt 0 && -f "$1" ]]; then
  single_file_mode=true
  file_path="$1"
  shift
fi

if [[ "$single_file_mode" == true ]]; then
  commit_message="${1:-add asset $(basename "$file_path")}"
  git add "$file_path"
else
  if [[ $# -gt 1 ]]; then
    usage
    exit 1
  fi
  commit_message="${1:-update assets}"
  git add -A
fi

if git diff --cached --quiet; then
  echo "No staged changes."
  exit 1
fi

asset_paths=()
if [[ "$single_file_mode" == true ]]; then
  if [[ "$file_path" == assets/* ]]; then
    asset_paths+=("$file_path")
  fi
else
  while IFS= read -r path; do
    asset_paths+=("$path")
  done < <(git diff --cached --name-only --diff-filter=AMR -- assets)
fi

git commit -m "$commit_message"
git push

asset_urls=()
for path in "${asset_paths[@]}"; do
  asset_urls+=("${base_url}/${path}")
done

if [[ ${#asset_urls[@]} -eq 0 ]]; then
  echo "Push complete. No added/updated files under assets/ in this commit."
  exit 0
fi

for url in "${asset_urls[@]}"; do
  echo "$url"
done

if command -v pbcopy >/dev/null 2>&1; then
  printf "%s\n" "${asset_urls[@]}" | pbcopy
  echo "URL copied to clipboard (pbcopy)."
elif command -v xclip >/dev/null 2>&1; then
  printf "%s\n" "${asset_urls[@]}" | xclip -selection clipboard
  echo "URL copied to clipboard (xclip)."
elif command -v wl-copy >/dev/null 2>&1; then
  printf "%s\n" "${asset_urls[@]}" | wl-copy
  echo "URL copied to clipboard (wl-copy)."
else
  echo "Clipboard tool not found. URLs printed above."
fi
