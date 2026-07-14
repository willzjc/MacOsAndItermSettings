#!/usr/bin/env zsh

# === Configuration ===
# Add folder names to ignore (relative names, not full paths)
IGNORE_DIRS=(
    "node_modules"
    ".git"
    "vendor"
    "2025"
    "2026"
    # Add more here as needed
)

# Compressed file extensions to skip
COMPRESSED_EXTS=(
    "gz" "bz2" "xz" "zst" "zip" "7z" "rar"
    "tar" "tgz" "tbz2" "txz"
    "jpg" "jpeg" "png" "mp4" "mp3" "mkv" "webm" "webp"
)

find_and_compress() {
    local search_dir="${1:-$HOME/text/.}"
    local max_size_mb="${2:-5}"
    local compressed=0
    local skipped=0
    local failed=0

    # Validate directory
    if [[ ! -d "$search_dir" ]]; then
        echo "Error: '$search_dir' is not a valid directory." >&2
        return 1
    fi

    # Check gzip is available
    if ! command -v gzip &>/dev/null; then
        echo "Error: gzip not found." >&2
        return 1
    fi

    # Build prune args from IGNORE_DIRS
    local prune_args=()
    for dir in $IGNORE_DIRS; do
        prune_args+=(-name "$dir" -o)
    done

    # Build the find command into an array
    local find_cmd=(find -P "$search_dir")

    if (( $#prune_args > 0 )); then
        prune_args[-1]=()  # remove trailing -o
        find_cmd+=(\( $prune_args \) -prune -o)
    fi

    find_cmd+=(-type f -size +"${max_size_mb}"M -print0)

    # Helper: check if extension is already compressed
    _is_compressed_ext() {
        local ext="${1:e:l}"  # :e = extension, :l = lowercase
        for cext in $COMPRESSED_EXTS; do
            [[ "$ext" == "$cext" ]] && return 0
        done
        return 1
    }

    echo "Searching '$search_dir' for files > ${max_size_mb}MB..."
    echo "-------------------------------------------"

    local file
    while IFS= read -r -d $'\0' file; do
        # Skip already-compressed extensions
        if _is_compressed_ext "$file"; then
            echo "[SKIP] $file (already compressed format)"
            ((skipped++))
            continue
        fi

        # Compress and remove original
        if gzip -f "$file"; then
            echo "[GZIP] $file -> ${file}.gz"
            ((compressed++))
        else
            echo "[FAIL] $file" >&2
            ((failed++))
        fi
    done < <(${find_cmd[@]})

    echo "-------------------------------------------"
    echo "Done. Compressed: $compressed | Skipped: $skipped | Failed: $failed"
}
