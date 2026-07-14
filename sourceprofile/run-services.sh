# Start all services in ~/.sourceprofile/services/ as singletons.
# Each service runs at most one instance; if already running, it is skipped.
# Run from source.sh on interactive shell startup.

WZJC_SERVICES_DIR="${HOME}/.sourceprofile/services"
WZJC_PID_DIR="${TMPDIR:-/tmp}/wzjc-services"
mkdir -p "$WZJC_PID_DIR" 2>/dev/null

if [ ! -d "$WZJC_SERVICES_DIR" ]; then
	return 0
fi

for f in "$WZJC_SERVICES_DIR"/*; do
	[ -f "$f" ] || continue
	[ -x "$f" ] || continue
	name=$(basename "$f")
	pidfile="${WZJC_PID_DIR}/${name}.pid"
	if [ -f "$pidfile" ]; then
		pid=$(cat "$pidfile" 2>/dev/null)
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			continue
		fi
		rm -f "$pidfile"
	fi
	( "$f"; rm -f "$pidfile" ) &
	echo $! > "$pidfile"
done
