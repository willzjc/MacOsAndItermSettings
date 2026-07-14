#!/bin/sh
# Ticket log watcher: numbers new .log files and keeps current.log symlinked.
# Runs from ~/tickets; singleton enforced by run-services.sh and script's own lock.
exec python3 "$HOME/tickets/ticket_log_watcher.py"
