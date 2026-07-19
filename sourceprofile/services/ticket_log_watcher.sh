#!/bin/sh
# Ticket log watcher: numbers new .log files and keeps current.log symlinked.
# Runs from ~/.sourceprofile/scripts; singleton enforced by run-services.sh and script's own lock.
WATCHER_PY="$HOME/.sourceprofile/scripts/ticket_log_watcher.py"

# If a watcher is already running (manual/run-services), do nothing quietly.
if pgrep -f "ticket_log_watcher.py" >/dev/null 2>&1; then
  exit 0
fi

# Only pass directories that currently exist to avoid startup warnings.
set -- "$WATCHER_PY"
[ -d "$HOME/today/logs" ] && set -- "$@" "$HOME/today/logs"
[ -d "$HOME/git/empliment/tickets/current-ticket/logs" ] && set -- "$@" "$HOME/git/empliment/tickets/current-ticket/logs"

# No watched dirs yet (common on fresh shells); skip startup quietly.
[ "$#" -le 1 ] && exit 0

exec python3 "$@"
