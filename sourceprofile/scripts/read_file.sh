# put this in ~/.zshrc (or run directly in terminal)
awscreds_env() {
  local profile="${1:-default}"
  local file="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"

  if [[ ! -f "$file" ]]; then
    echo "credentials file not found: $file" >&2
    return 1
  fi

  # Parse only the target profile section, uppercase keys, export
  eval "$(
    awk -v p="$profile" '
      BEGIN { in_profile=0 }
      /^\[.*\]$/ {
        section=$0
        gsub(/^\[|\]$/, "", section)
        in_profile=(section==p)
        next
      }
      in_profile && /^[[:space:]]*[A-Za-z0-9_]+[[:space:]]*=/ {
        key=$0
        sub(/[[:space:]]*=.*/, "", key)
        val=$0
        sub(/^[^=]*=[[:space:]]*/, "", val)

        # trim spaces
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)

        # uppercase key and make it shell-safe
        up=toupper(key)
        gsub(/[^A-Z0-9_]/, "_", up)

        # escape for double-quoted shell export
        gsub(/["\\$`]/, "\\\\&", val)
        printf("export %s=\"%s\"\n", up, val)
      }
    ' "$file"
  )"

  echo "Loaded profile '$profile' from $file into current shell."
}
