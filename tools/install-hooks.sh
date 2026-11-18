#!/usr/bin/env bash
# Installs the git pre-commit hook that runs the check gate. Run once per clone.
set -eu

cd "$(dirname "$0")/.."

hook=".git/hooks/pre-commit"
printf '#!/usr/bin/env bash\nexec ./tools/check.sh\n' > "$hook"
chmod +x "$hook"
echo "installed $hook"
