#!/usr/bin/env zsh
# Remove zsh history *events* that contain AWS credential material (including
# multi-line assume-role / export blocks that start with AWS_ACCOUNT_ID=, etc.)
#
# After editing the file, replaces THIS shell's in-memory history from disk
# (fc -R). Otherwise fzf/Ctrl+R still show old events even when the file is clean.
#
# Usage: source ~/.zsh/prune-aws-history.zsh
#        prune-aws-history

prune-aws-history() {
  emulate -L zsh
  local _PRUNE_AWS_HISTORY_AWK
  read -r -d '' _PRUNE_AWS_HISTORY_AWK <<'AWK'
# History file: events start with ": <epoch>:<duration>;<cmd>". Continuation
# lines do not start with ": <digits>:".
function is_sensitive(s) {
  return s ~ /AWS_SECRET_ACCESS_KEY/ \
      || s ~ /AWS_SESSION_TOKEN/ \
      || s ~ /AWS_SECURITY_TOKEN/ \
      || s ~ /AWS_ACCESS_KEY_ID[=']/ \
      || s ~ /export AWS_ACCESS_KEY_ID/ \
      || s ~ /AWS_ACCOUNT_ID[=']/ \
      || s ~ /export AWS_ACCOUNT_ID/
}
function flush(   i) {
  if (n == 0) return
  if (!sensitive) {
    for (i = 1; i <= n; i++) print lines[i]
  }
  delete lines
  n = 0
  sensitive = 0
}
/^: [0-9]+:[0-9]+;/ {
  flush()
}
{
  lines[++n] = $0
  if (is_sensitive($0)) sensitive = 1
}
END {
  flush()
}
AWK

  local hist="${HISTFILE:-$HOME/.zsh_history}"
  if [[ ! -f "$hist" ]]; then
    print -u2 "prune-aws-history: no history file: $hist"
    return 1
  fi

  # zsh event numbers (fc -l / fzf) are in RAM; pruning the file alone does not
  # remove them. fc -R replaces the session list from disk (drops stale RAM).
  local quick='AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN|AWS_SECURITY_TOKEN|AWS_ACCESS_KEY_ID=|AWS_ACCESS_KEY_ID='"'"'|export AWS_ACCESS_KEY_ID|AWS_ACCOUNT_ID=|AWS_ACCOUNT_ID='"'"'|export AWS_ACCOUNT_ID'
  if ! LC_ALL=C command grep -qE "$quick" "$hist" 2>/dev/null; then
    print "prune-aws-history: OK: no matching AWS patterns in $hist on disk (file already clean)"
    if builtin fc -R "$hist" 2>/dev/null; then
      print "prune-aws-history: reloaded this shell from disk (fc -R); fzf/Ctrl+R should match file now"
    else
      print -u2 "prune-aws-history: fc -R failed; run: fc -R $hist"
    fi
    return 0
  fi

  local before after tmp backup
  before=$(wc -l <"$hist" | tr -d ' ')
  tmp=$(mktemp) || return 1
  LC_ALL=C command awk "$_PRUNE_AWS_HISTORY_AWK" "$hist" >"$tmp" || { rm -f "$tmp"; return 1 }
  after=$(wc -l <"$tmp" | tr -d ' ')

  if [[ "$before" -eq "$after" ]]; then
    rm -f "$tmp"
    print "prune-aws-history: OK: awk made no changes ($hist)"
    if builtin fc -R "$hist" 2>/dev/null; then
      print "prune-aws-history: reloaded this shell from disk (fc -R)"
    else
      print -u2 "prune-aws-history: fc -R failed; run: fc -R $hist"
    fi
    return 0
  fi

  backup="${hist}.bak.$(date +%Y%m%d%H%M%S)"
  cp "$hist" "$backup" || { rm -f "$tmp"; return 1 }
  mv "$tmp" "$hist" || return 1
  chmod 600 "$hist" 2>/dev/null

  print "prune-aws-history: removed $((before - after)) line(s), kept $after ($before -> $after)"
  print "prune-aws-history: backup $backup"
  if builtin fc -R "$hist" 2>/dev/null; then
    print "prune-aws-history: reloaded this shell from disk (fc -R)"
  else
    print -u2 "prune-aws-history: fc -R failed; run: fc -R $hist"
  fi
}

