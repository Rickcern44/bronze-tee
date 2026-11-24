#!/usr/bin/env bash
# Prints the version GitVersion computes from git tags, and stamps it into the
# Godot project for exports.
#
#   tools/version.sh               # print the main version fields
#   tools/version.sh --get NAME    # print one field (e.g. FullSemVer, BundleVersion)
#   tools/version.sh --json        # print the full GitVersion JSON
#   tools/version.sh --stamp       # write the version into project.godot and
#                                  # export_presets.cfg (export time / CI only)
#   tools/version.sh --restore     # put the committed placeholders back
#
# Stamped files must never be committed. The committed values are neutral
# placeholders (display "0.0.0-dev", bundle "0.0.0"); --stamp refuses to run
# when either file has local edits so --restore can never lose work.
#
# When GITHUB_OUTPUT is set, --stamp also writes the fields as step outputs.
# Needs: dotnet tool restore (GitVersion.Tool from .config/dotnet-tools.json),
# python3, and a clone with full history and tags (fetch-depth: 0 in CI).
set -euo pipefail

cd "$(dirname "$0")/.."

STAMPED_FILES=(project.godot export_presets.cfg)

usage() {
	sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

gitversion_json() {
	if ! json="$(dotnet tool run dotnet-gitversion /output json 2>&1)"; then
		echo "$json" >&2
		echo "version.sh: GitVersion failed. Run 'dotnet tool restore' and make sure the clone has full history and tags." >&2
		exit 1
	fi
	printf '%s\n' "$json"
}

# Reads GitVersion JSON on stdin and prints "Name=value" lines, including the
# derived fields this project uses.
fields() {
	python3 -c '
import json, sys
v = json.load(sys.stdin)
out = {
    "FullSemVer": v["FullSemVer"],
    "SemVer": v["SemVer"],
    "MajorMinorPatch": v["MajorMinorPatch"],
    "PreReleaseTag": v["PreReleaseTag"],
    "InformationalVersion": v["InformationalVersion"],
    "ShortSha": v["ShortSha"],
    "BranchName": v["BranchName"],
    # CFBundleVersion: up to three dot-separated integers.
    "BundleVersion": v["MajorMinorPatch"],
    # In-game display string: SemVer plus the commit as build metadata.
    "DisplayVersion": "%s+%s" % (v["SemVer"], v["ShortSha"]),
}
for key, value in out.items():
    print("%s=%s" % (key, value))
'
}

field() {
	local name="$1" lines="$2" line
	while IFS= read -r line; do
		if [ "${line%%=*}" = "$name" ]; then
			printf '%s\n' "${line#*=}"
			return 0
		fi
	done <<< "$lines"
	echo "version.sh: unknown field $name" >&2
	exit 2
}

stamp() {
	if ! git diff --quiet HEAD -- "${STAMPED_FILES[@]}"; then
		echo "version.sh: ${STAMPED_FILES[*]} have local changes; commit or restore them before stamping." >&2
		exit 1
	fi
	local lines display short bundle
	lines="$(gitversion_json | fields)"
	display="$(field DisplayVersion "$lines")"
	short="$(field MajorMinorPatch "$lines")"
	bundle="$(field BundleVersion "$lines")"
	python3 - "$display" "$short" "$bundle" <<'PY'
import re, sys
display, short, bundle = sys.argv[1:]

def sub(path, pattern, value, count_expected=1):
    text = open(path, encoding="utf-8").read()
    new, count = re.subn(pattern, lambda m: m.group(1) + value + '"', text, flags=re.M)
    if count != count_expected:
        sys.exit("version.sh: expected %d match for %s in %s, found %d" % (count_expected, pattern, path, count))
    open(path, "w", encoding="utf-8").write(new)

sub("project.godot", r'^(config/version=")[^"]*"', display)
sub("export_presets.cfg", r'^(application/short_version=")[^"]*"', short)
sub("export_presets.cfg", r'^(application/version=")[^"]*"', bundle)
PY
	echo "stamped ${STAMPED_FILES[*]}: display=$display short_version=$short version=$bundle"
	echo "do not commit these files; run tools/version.sh --restore to undo"
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		printf '%s\n' "$lines" >> "$GITHUB_OUTPUT"
	fi
}

case "${1:-}" in
	"")
		gitversion_json | fields
		;;
	--get)
		[ "$#" -eq 2 ] || usage
		field "$2" "$(gitversion_json | fields)"
		;;
	--json)
		gitversion_json
		;;
	--stamp)
		stamp
		;;
	--restore)
		git checkout -- "${STAMPED_FILES[@]}"
		echo "restored ${STAMPED_FILES[*]}"
		;;
	*)
		usage
		;;
esac
