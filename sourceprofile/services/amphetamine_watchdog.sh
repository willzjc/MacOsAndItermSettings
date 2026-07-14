#!/bin/sh
# Relaunch Amphetamine.app if it gets killed.
# Singleton enforced by run-services.sh.

while true; do
	if ! pgrep -x "Amphetamine" >/dev/null 2>&1; then
		open -ga "Amphetamine"
	fi
	sleep 10
done
