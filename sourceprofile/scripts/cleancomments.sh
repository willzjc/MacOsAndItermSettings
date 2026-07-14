#!/bin/bash
#
# Git function to remove "Co-authored-by: Cursor" lines from all commits that have it (current branch).
# Uses one rebase instead of filter-branch, so it's fast.
#
# Usage:
#   source cleancomments.sh
#   cleancomments
#
# Or add to your ~/.zshrc or ~/.bashrc:
#   source /path/to/source-analyzer/cleancomments.sh

cleancomments() {
    local repo_dir
    repo_dir="$(git rev-parse --show-toplevel 2>/dev/null)"

    if [ -z "$repo_dir" ]; then
        echo "❌ Error: Not in a git repository"
        return 1
    fi

    echo "🧹 Finding commits with 'Co-authored-by: Cursor'..."
    echo "   Repository: $repo_dir"
    echo ""

    # Find all commit hashes (current branch) that have the line - same fast scan as before
    local bad_commits
    bad_commits=$(git log --format="%H" HEAD 2>/dev/null | while read -r c; do
        git log -1 --format="%B" "$c" 2>/dev/null | grep -q "Co-authored-by: Cursor" && echo "$c"
    done)

    local count
    count=$(echo "$bad_commits" | grep -c . 2>/dev/null || echo "0")

    if [ "$count" -eq 0 ]; then
        echo "✅ No co-author lines found. Nothing to clean."
        return 0
    fi

    echo "   Found $count commit(s) with co-author lines"
    echo ""

    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD -- 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        echo "❌ Error: You have uncommitted changes. Commit or stash them first."
        return 1
    fi

    echo "🔄 Rewriting those commits (one rebase)..."
    echo ""

    # Rebase: reword only the commits that have the line.
    export CLEANCOMMENTS_BAD="$bad_commits"

    # Use temp scripts so git passes the path as $1 correctly
    local seq_script msg_script
    seq_script=$(mktemp)
    msg_script=$(mktemp)
    trap "rm -f '$seq_script' '$msg_script'" RETURN

    cat > "$seq_script" << 'SEQSCRIPT'
#!/bin/sh
tmp=$(mktemp)
while IFS= read -r line; do
    case "$line" in
        pick\ *)
            hash=$(echo "$line" | awk '{print $2}')
            if echo "$CLEANCOMMENTS_BAD" | grep -q "^${hash}$"; then
                echo "reword ${line#pick }"
            else
                echo "$line"
            fi
            ;;
        *)
            echo "$line"
            ;;
    esac
done < "$1" > "$tmp" && mv "$tmp" "$1"
SEQSCRIPT
    printf '%s\n' '#!/bin/sh' 'tmp=$(mktemp); sed "/^Co-authored-by: Cursor <cursoragent@cursor.com>$/d" "$1" > "$tmp" && mv "$tmp" "$1"' > "$msg_script"
    chmod +x "$seq_script" "$msg_script"

    export GIT_SEQUENCE_EDITOR="$seq_script"
    export GIT_EDITOR="$msg_script"

    if ! git rebase -i --root 2>&1; then
        echo ""
        echo "❌ Rebase stopped (maybe conflict or user aborted). To retry: git rebase --continue"
        echo "   To abort: git rebase --abort"
        unset GIT_SEQUENCE_EDITOR GIT_EDITOR CLEANCOMMENTS_BAD
        rm -f "$seq_script" "$msg_script"
        return 1
    fi

    unset GIT_SEQUENCE_EDITOR GIT_EDITOR CLEANCOMMENTS_BAD
    rm -f "$seq_script" "$msg_script"

    echo "✅ Removed co-author line from $count commit(s)."
    echo ""
    echo "⚠️  If you already pushed, update with: git push --force-with-lease origin <branch-name>"
}
