#!/usr/bin/env bash
# Runs one playtest under Xvfb with Godot config, data and cache isolated,
# then scans the captured output for error lines.
# Usage: ./tools/playtest.sh <slug>
set -u -o pipefail

cd "$(dirname "$0")/.."

if [ $# -ne 1 ]; then
	echo "usage: $0 <slug>" >&2
	exit 2
fi

slug="$1"
script="tests/playtest/${slug}_playtest.gd"
if [ ! -f "$script" ]; then
	echo "no such playtest: $script" >&2
	exit 2
fi

LOGDIR="$(mktemp -d)"
trap 'rm -rf "$LOGDIR"' EXIT

# Godot never writes to the runner's ~/.config, ~/.local/share or ~/.cache.
# HOME is left unchanged.
mkdir -p "$LOGDIR/config" "$LOGDIR/data" "$LOGDIR/cache"
export XDG_CONFIG_HOME="$LOGDIR/config"
export XDG_DATA_HOME="$LOGDIR/data"
export XDG_CACHE_HOME="$LOGDIR/cache"

xvfb-run -a -s "-screen 0 1280x720x24" timeout 300 \
	godot --audio-driver Dummy --path . --script "res://$script" 2>&1 | tee "$LOGDIR/out.log"
rc=${PIPESTATUS[0]}

if grep -E -q 'SCRIPT ERROR|Assertion failed|^ERROR:' "$LOGDIR/out.log"; then
	echo "FAIL log scan:"
	grep -E 'SCRIPT ERROR|Assertion failed|^ERROR:' "$LOGDIR/out.log"
	exit 1
fi
if [ "$rc" -ne 0 ]; then
	echo "FAIL playtest: exit $rc"
	exit "$rc"
fi
echo "PLAYTEST PASSED"
