#!/usr/bin/env bash
# Installs the git hooks for this repo. Run once per clone.
#   pre-commit: runs the check gate (tools/check.sh)
#   commit-msg: enforces Conventional Commits (tools/check-commit-msg.sh)
set -eu

cd "$(dirname "$0")/.."

hooks="$(git rev-parse --git-path hooks)"
mkdir -p "$hooks"

hook="$hooks/pre-commit"
printf '#!/usr/bin/env bash\nexec ./tools/check.sh\n' > "$hook"
chmod +x "$hook"
echo "installed $hook"

hook="$hooks/commit-msg"
printf '#!/usr/bin/env bash\nexec ./tools/check-commit-msg.sh "$1"\n' > "$hook"
chmod +x "$hook"
echo "installed $hook"
