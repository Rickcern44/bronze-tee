#!/usr/bin/env bash
# Validates a commit message or PR title against Conventional Commits 1.0.0
# and the Bronze Tee convention:
#
#   type(scope): RCE-nnn subject
#
# Usage:
#   tools/check-commit-msg.sh <message-file>          # git commit-msg hook
#   tools/check-commit-msg.sh -m "<message>"           # a string
#   tools/check-commit-msg.sh --strict -m "<title>"    # PR titles: no exemptions
#
# Without --strict, merge commits ("Merge ..."), git reverts ('Revert "..."')
# and fixup!/squash!/amend! commits are accepted as-is.
# Exit 0 when valid, 1 when invalid, 2 on usage errors.
set -u -o pipefail

TYPES='feat|fix|perf|refactor|docs|test|build|ci|chore|style|revert'
HEADER_RE="^(${TYPES})(\\([a-z0-9][a-z0-9._/-]*\\))?!?: [^[:space:]].*$"
MAX_HEADER=100

usage() {
	echo "usage: $0 [--strict] (<message-file> | -m <message>)" >&2
	exit 2
}

strict=0
message=""
have_message=0
while [ "$#" -gt 0 ]; do
	case "$1" in
		--strict) strict=1 ;;
		-m)
			[ "$#" -ge 2 ] || usage
			message="$2"
			have_message=1
			shift
			;;
		-h|--help) usage ;;
		*)
			[ "$have_message" -eq 0 ] || usage
			[ -f "$1" ] || { echo "check-commit-msg: no such file: $1" >&2; exit 2; }
			message="$(cat "$1")"
			have_message=1
			;;
	esac
	shift
done
[ "$have_message" -eq 1 ] || usage

# Drop everything from git's scissors line, then comment lines, as git does.
cleaned="$(printf '%s\n' "$message" \
	| sed '/^# -\{24\} >8 -\{24\}$/,$d' \
	| grep -v '^#' || true)"
# Drop leading blank lines.
cleaned="$(printf '%s\n' "$cleaned" | sed '/./,$!d')"
header="$(printf '%s\n' "$cleaned" | head -n 1)"
header="${header%$'\r'}"
second="$(printf '%s\n' "$cleaned" | sed -n '2p')"

fail() {
	cat >&2 <<EOF
ERROR: $1
  got:      "${header}"
  expected: type(scope): RCE-nnn subject
  types:    ${TYPES//|/, }
  examples: feat(course): RCE-169 bake surface maps for course features
            fix(physics)!: RCE-181 change spin units to rpm
            docs: update the release guide
See README.md "Versioning and releases".
EOF
	exit 1
}

if [ -z "$header" ]; then
	fail "empty commit message"
fi

if [ "$strict" -eq 0 ]; then
	case "$header" in
		"Merge "*|"Revert \""*|"fixup! "*|"squash! "*|"amend! "*) exit 0 ;;
	esac
fi

if ! printf '%s\n' "$header" | grep -Eq "$HEADER_RE"; then
	if printf '%s\n' "$header" | grep -Eq '^RCE-[0-9]+:'; then
		fail "the Linear key goes after the type, not in front of it"
	fi
	if printf '%s\n' "$header" | grep -Eq "^[A-Z]+[a-z]*(\\(|!?:)" \
		&& printf '%s\n' "$header" | tr '[:upper:]' '[:lower:]' | grep -Eq "$HEADER_RE"; then
		fail "the type and scope must be lowercase"
	fi
	fail "the subject line is not a Conventional Commit"
fi

if [ "${#header}" -gt "$MAX_HEADER" ]; then
	fail "the subject line is ${#header} characters; keep it at ${MAX_HEADER} or fewer"
fi

if [ -n "$second" ]; then
	fail "leave a blank line between the subject and the body"
fi

exit 0
