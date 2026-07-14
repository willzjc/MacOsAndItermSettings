#!/usr/bin/env bash
# cleanup.sh: Defines cleanup() to zip logs folders and large files under ~/text/yyyymmdd.
# - Only processes direct children of ~/text that match yyyymmdd (8 digits).
# - Moves yyyymmdd folders older than 2 weeks (by name) into ~/text/yyyy/ (e.g. 2026/).
# - Recursively finds and zips "logs" (and similar) subfolders; does not follow symlinks.
# - Zips any file > 2MB into same folder as <name>.zip.
# Usage: source ~/.sourceprofile/scripts/cleanup.sh   then run: cleanup
#        Or run directly: ~/.sourceprofile/scripts/cleanup.sh

cleanup() {
  set -euo pipefail
  local TEXT_DIR="${TEXT_DIR:-$HOME/text}"
  local LOG_DIR_NAMES=(logs log)
  local MIN_SIZE_BYTES=$((2 * 1024 * 1024))

  if [[ ! -d "$TEXT_DIR" ]]; then
    echo "Directory does not exist: $TEXT_DIR" >&2
    return 1
  fi

  cd "$TEXT_DIR" || return 1

  # Cutoff: 2 weeks ago (by date, not mtime). macOS uses -v-2w; GNU uses -d '2 weeks ago'
  local cutoff
  if date -v-2w +%Y%m%d &>/dev/null; then
    cutoff=$(date -v-2w +%Y%m%d)
  else
    cutoff=$(date -d '2 weeks ago' +%Y%m%d)
  fi

  # Only iterate over yyyymmdd folders (8 digits); ignore everything else
  for dir in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]; do
    [[ ! -d "$dir" || -L "$dir" ]] && continue
    full_dir="$TEXT_DIR/$dir"
    local yyyy="${dir:0:4}"

    # Move folder to yyyy/ if its name (date) is older than 2 weeks
    if [[ "$dir" -lt "$cutoff" ]]; then
      mkdir -p "$TEXT_DIR/$yyyy"
      mv "$full_dir" "$TEXT_DIR/$yyyy/$dir"
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] moved: $dir -> $yyyy/$dir"
      continue
    fi

    # Recursively find and zip logs-style subfolders (find does not follow symlinks)
    while IFS= read -r -d '' logdir; do
      [[ ! -d "$logdir" || -L "$logdir" ]] && continue
      dirpart=$(dirname "$logdir")
      logname=$(basename "$logdir")
      (cd "$dirpart" && zip -r -q -y "$logname.zip" "$logname") 2>/dev/null || true
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] zipped folder: $logdir -> $logname.zip"
      # -y: store symlinks as links, do not follow (avoids nesting)
    done < <(find "$full_dir" -type d \( -name "logs" -o -name "log" \) -print0 2>/dev/null)

    # Recursively find files > 2MB and zip in same folder as <filename>.zip (find does not follow symlinks)
    while IFS= read -r -d '' f; do
      dirpart=$(dirname "$f")
      base=$(basename "$f")
      [[ "$base" == *.zip ]] && continue
      zip_path="$dirpart/$base.zip"
      [[ -f "$zip_path" ]] && continue
      (cd "$dirpart" && zip -q -y "$base.zip" "$base") 2>/dev/null || true
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] zipped file: $f -> $base.zip"
    done < <(find "$full_dir" -type f -size +${MIN_SIZE_BYTES}c ! -name "*.zip" -print0 2>/dev/null)
  done
}

# Run when executed as a script
if [[ "${BASH_SOURCE[0]:-}" != "${0:-}" ]]; then
  : # sourced: function is defined, do nothing
else
  cleanup "$@"
fi
