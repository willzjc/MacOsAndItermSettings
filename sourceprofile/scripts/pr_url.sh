#!/usr/bin/env bash
#
# git-pr-url.sh — A sourceable bash function to find or create Bitbucket PR URLs.
#
# Usage:
#   1. Source this file:
#        source /path/to/git-pr-url.sh
#      Or add to your ~/.bashrc / ~/.zshrc:
#        source /path/to/git-pr-url.sh
#
#   2. Call the function from any git repo:
#        pr-url            # uses current branch
#        pr-url my-branch  # uses a specific branch
#
#   3. For private repos, export your Bitbucket credentials:
#        export BITBUCKET_USER="your-username"
#        export BITBUCKET_APP_PASSWORD="your-app-password"
#
# Requires: git, curl, jq
#

pr-url() {
  # --- Validate dependencies ---
  local missing=()
  for cmd in git curl jq; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required commands: ${missing[*]}" >&2
    return 1
  fi

  # --- Ensure we're in a git repo ---
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "ERROR: Not inside a git repository." >&2
    return 1
  fi

  # --- Derive workspace/repo from git remote ---
  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null) || {
    echo "ERROR: No git remote 'origin' found." >&2
    return 1
  }

  local workspace repo
  if [[ "$remote_url" =~ bitbucket\.org[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
    workspace="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
  else
    echo "ERROR: Could not parse Bitbucket workspace/repo from remote: $remote_url" >&2
    return 1
  fi

  # --- Determine the branch ---
  local branch="${1:-}"
  if [[ -z "$branch" ]]; then
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || {
      echo "ERROR: Could not determine current branch." >&2
      return 1
    }
    if [[ "$branch" == "HEAD" ]]; then
      echo "ERROR: Detached HEAD state. Specify a branch or check one out." >&2
      return 1
    fi
  fi

  echo "Repo:   ${workspace}/${repo}"
  echo "Branch: ${branch}"
  echo ""

  # --- Query Bitbucket API for existing open PRs ---
  local api_url="https://api.bitbucket.org/2.0/repositories/${workspace}/${repo}/pullrequests"
  local encoded_branch
  encoded_branch=$(printf '%s' "$branch" | jq -sRr @uri)
  local query="source.branch.name=%22${encoded_branch}%22&state=OPEN"

  local response=""
  # Try unauthenticated first, then with credentials if set
  response=$(curl -sf "${api_url}?q=${query}" 2>/dev/null)
  if [[ $? -ne 0 ]] && [[ -n "${BITBUCKET_USER:-}" ]] && [[ -n "${BITBUCKET_APP_PASSWORD:-}" ]]; then
    response=$(curl -sf -u "${BITBUCKET_USER}:${BITBUCKET_APP_PASSWORD}" "${api_url}?q=${query}" 2>/dev/null)
  fi

  if [[ -z "$response" ]]; then
    echo "⚠  Could not query the Bitbucket API (private repo?)."
    echo "   Set BITBUCKET_USER and BITBUCKET_APP_PASSWORD for private repos."
    echo ""
    echo "📝 Create a new PR:"
    echo "   https://bitbucket.org/${workspace}/${repo}/pull-requests/new?source=${encoded_branch}"
    return 0
  fi

  local pr_count
  pr_count=$(echo "$response" | jq '.size // 0')

  if [[ "$pr_count" -gt 0 ]]; then
    echo "✅ Found open PR(s) for this branch:"
    echo ""
    echo "$response" | jq -r '.values[] | "  #\(.id) [\(.state)] \(.title)\n  https://bitbucket.org/'"${workspace}/${repo}"'/pull-requests/\(.id)\n"'
  else
    echo "No open PR found for branch '${branch}'."
    echo ""
    echo "📝 Create a new PR:"
    echo "   https://bitbucket.org/${workspace}/${repo}/pull-requests/new?source=${encoded_branch}"
  fi
}

