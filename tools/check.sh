#!/usr/bin/env bash
# The one check gate for this repository. Stops at the first failing stage.
set -u -o pipefail

cd "$(dirname "$0")/.."

# Stable sort order for the check scripts.
export LC_ALL=C

echo "==> course import offline tests"
python3 -m unittest discover -s tests -p 'test_*.py'
if [ "$?" -ne 0 ]; then
	echo "CHECK GATE FAILED: course import offline tests"
	exit 1
fi

CHECK_TIMEOUT="${CHECK_TIMEOUT:-120}"
IMPORT_TIMEOUT=120
BAD_RE='SCRIPT ERROR|Assertion failed|^ERROR:'

LOGDIR="$(mktemp -d)"
trap 'rm -rf "$LOGDIR"' EXIT

fail() {
	echo "CHECK GATE FAILED: $*"
	exit 1
}

# Stage 1: build (warnings are errors).
echo "==> build"
if ! dotnet build BronzeTee.Godot.csproj -warnaserror; then
	fail "build (dotnet build exit non-zero)"
fi

# Stage 2: unit tests for every dotnet/*.Tests project.
echo "==> unit tests"
for dir in dotnet/*.Tests; do
	[ -d "$dir" ] || continue
	echo "-- $dir"
	log="$LOGDIR/unit-$(basename "$dir").log"
	dotnet test "$dir" >"$log" 2>&1
	rc=$?
	cat "$log"
	if [ "$rc" -ne 0 ]; then
		fail "unit tests in $dir (dotnet test exit $rc)"
	fi
	if grep -q "No test is available" "$log"; then
		fail "unit tests in $dir: no tests found"
	fi
done

# Godot isolation: stages 3 and 4 write Godot config and data only into the
# temp dir, never into the runner's ~/.config/godot. HOME is left unchanged
# because dotnet and NuGet need it.
mkdir -p "$LOGDIR/config" "$LOGDIR/data" "$LOGDIR/cache"
export XDG_CONFIG_HOME="$LOGDIR/config"
export XDG_DATA_HOME="$LOGDIR/data"
export XDG_CACHE_HOME="$LOGDIR/cache"

# Stage 3: import.
echo "==> import"
log="$LOGDIR/import.log"
timeout "$IMPORT_TIMEOUT" godot --headless --path . --import >"$log" 2>&1
rc=$?
cat "$log"
if grep -E -q "$BAD_RE" "$log"; then
	fail "import: bad output line"
fi
if [ "$rc" -eq 124 ]; then
	fail "import: timeout"
fi
if [ "$rc" -ne 0 ]; then
	fail "import: exit $rc"
fi

# Stage 4: headless checks, one by one in sorted order.
echo "==> checks"
for script in tests/*_check.gd; do
	name="$(basename "$script")"
	log="$LOGDIR/$name.log"
	start="$(date +%s)"
	timeout "$CHECK_TIMEOUT" godot --headless --path . --script "res://tests/$name" >"$log" 2>&1
	rc=$?
	secs=$(( $(date +%s) - start ))
	reason=""
	# A bad output line is checked first: a failing assert can leave Godot
	# running until the time limit, and the log still shows the real cause.
	if grep -E -q "$BAD_RE" "$log"; then
		reason="bad output line"
	elif [ "$rc" -eq 124 ]; then
		reason="timeout"
	elif [ "$rc" -ne 0 ]; then
		reason="exit $rc"
	fi
	if [ -n "$reason" ]; then
		echo "FAIL $name: $reason"
		echo "--- last 30 lines of $name ---"
		tail -n 30 "$log"
		fail "checks: $name ($reason)"
	fi
	cat "$log"
	echo "PASS $name (${secs}s)"
done

echo "CHECK GATE PASSED"
