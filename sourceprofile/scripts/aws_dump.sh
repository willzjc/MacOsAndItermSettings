# aws-env-dump.sh
# Usage:
#   source ./aws-env-dump.sh
# Output:
#   AWS_FOO='bar'
#   AWS_REGION='us-west-2'
#   ...
#   export AWS_FOO AWS_REGION ...


# ============================================================
# EXCLUSION LIST - Add variable names you want to skip
# ============================================================
EXCLUDE_VARS=(
  AWS_PAGER
  AWS_REGION
  AWS_ROLE_ARN
  # Add more variable names here, one per line
)

_is_excluded() {
  local var="$1"
  local excl
  for excl in "${EXCLUDE_VARS[@]}"; do
    if [ "$var" = "$excl" ]; then
      return 0
    fi
  done
  return 1
}

# If executed (not sourced), we can only see exported env vars.
# This script is intended to be SOURCED so it can also see non-exported shell vars.
_is_sourced() {
  # Works in bash and zsh
  (return 0 2>/dev/null)
}

_shell_quote() {
  # Prints a shell-escaped representation of $1 suitable for re-entry in the same shell.
  if [ -n "${ZSH_VERSION-}" ]; then
    # zsh: ${(qq)...} escapes safely
    local s="$1"
    print -r -- "${(qq)s}"
  else
    # bash: printf %q escapes safely
    printf '%q' "$1"
  fi
}

_aws_var_names_current_shell() {
  if [ -n "${ZSH_VERSION-}" ]; then
    # All parameters (includes non-exported) whose names match AWS*
    print -l -- ${(k)parameters[(I)AWS*]}
  elif [ -n "${BASH_VERSION-}" ]; then
    # All shell variables (includes non-exported) whose names start with AWS
    compgen -v | command grep -E '^AWS'
  else
    # Fallback: best-effort from `set` (may be noisy in some shells)
    set | command sed -n 's/^\(AWS[A-Za-z0-9_]*\)=.*/\1/p'
  fi
}

_aws_var_names_exported_env_only() {
  # Exported environment only
  env | command sed -n 's/^\(AWS[A-Za-z0-9_]*\)=.*/\1/p'
}

alias awsdump=aws_env_dump

aws_env_dump() {
  local names
  if _is_sourced; then
    names="$(_aws_var_names_current_shell)"
  else
    names="$(_aws_var_names_exported_env_only)"
  fi

  # De-dup + stable order
  names="$(printf '%s\n' "$names" | command awk 'NF && !seen[$0]++' | command sort)"

  if [ -z "$names" ]; then
    printf '%s\n' "# (no AWS* variables found)"
    printf '%s\n' "# export (none)"
    return 0
  fi

  # Print VAR=value lines (copy/paste-able), skipping excluded vars
  local var val
  local export_list=()
  while IFS= read -r var; do
    [ -n "$var" ] || continue

    # Skip if excluded
    if _is_excluded "$var"; then
      continue
    fi

    if [ -n "${ZSH_VERSION-}" ]; then
      val="${(P)var}"
    else
      # bash / sh-ish: indirect expansion
      eval "val=\${$var}"
    fi

    printf '%s=%s\n' "$var" "$(_shell_quote "$val")"
    export_list+=("$var")
  done <<< "$names"

  # Last line: export all those variables (no values)
  if [ ${#export_list[@]} -gt 0 ]; then
    printf 'export'
    for var in "${export_list[@]}"; do
      printf ' %s' "$var"
    done
    printf '\n'
  else
    printf '%s\n' "# export (none - all variables excluded)"
  fi
}
