#!/bin/bash
# Download the newest working Bronze Tee release and install it on macOS.
# Prefers the newest stable release (vX.Y.Z, not a prerelease); older test-*
# prereleases are only a fallback while no stable release exists.
set -euo pipefail

repo='Rickcern44/bronze-tee'
asset='Bronze-Tee-macOS.zip'
app='/Applications/Bronze Tee.app'
work=$(mktemp -d "${TMPDIR:-/tmp}/bronze-tee-update.XXXXXX")
staged="/Applications/.Bronze-Tee-update-$$.app"
backup="/Applications/.Bronze-Tee-backup-$$.app"
cleanup() {
  if [ -d "$backup" ] && [ ! -e "$app" ]; then
    mv "$backup" "$app" || echo "Restore the previous app from $backup" >&2
  fi
  rm -rf "$work" "$staged"
}
trap cleanup EXIT

if [ "$(uname -s)" != Darwin ]; then
  echo 'Run this script on a Mac.' >&2
  exit 1
fi
if ! command -v python3 >/dev/null; then
  echo 'Python 3 is required. Install it, then run this script again.' >&2
  exit 1
fi
if /usr/bin/osascript -e 'application id "com.cernylabs.bronzetee" is running' | grep -qx true; then
  echo 'Quit Bronze Tee, then run this script again.' >&2
  exit 1
fi
if [ ! -w /Applications ]; then
  echo 'You do not have permission to write to /Applications.' >&2
  exit 1
fi

curl --fail --silent --show-error --location --retry 3 \
  "https://api.github.com/repos/$repo/releases?per_page=100" > "$work/releases.json"
python3 - "$work/releases.json" "$asset" > "$work/release.txt" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    releases = json.load(f)
# The API lists releases newest first; take the first usable stable one, then
# fall back to the first usable prerelease (legacy test-* builds).
for want_prerelease in (False, True):
    for release in releases:
        if release.get('draft') or 'broken' in (release.get('name') or '').lower():
            continue
        if bool(release.get('prerelease')) != want_prerelease:
            continue
        for asset in release.get('assets', []):
            if asset.get('name') == sys.argv[2] and asset.get('digest', '').startswith('sha256:'):
                print(release['tag_name'])
                print(asset['browser_download_url'])
                print(asset['digest'].split(':', 1)[1])
                sys.exit(0)
raise SystemExit('No usable Bronze Tee release with a SHA-256 digest was found.')
PY
tag=$(sed -n '1p' "$work/release.txt")
url=$(sed -n '2p' "$work/release.txt")
digest=$(sed -n '3p' "$work/release.txt")
case "$url" in
  "https://github.com/$repo/releases/download/"*) ;;
  *) echo 'The release download URL is not valid.' >&2; exit 1 ;;
esac
printf 'Downloading Bronze Tee %s...\n' "$tag"
curl --fail --silent --show-error --location --retry 3 "$url" -o "$work/game.zip"
printf '%s  %s\n' "$digest" "$work/game.zip" | shasum -a 256 -c -
ditto -x -k "$work/game.zip" "$work/unpacked"
source_app="$work/unpacked/Bronze Tee.app"
[ -f "$source_app/Contents/MacOS/Bronze Tee" ] || { echo 'The app is missing from the download.' >&2; exit 1; }
codesign --verify --deep --strict "$source_app"
ditto "$source_app" "$staged"
codesign --verify --deep --strict "$staged"
if [ -e "$app" ]; then
  mv "$app" "$backup"
fi
mv "$staged" "$app"
if [ -d "$backup" ]; then
  rm -rf "$backup"
fi
printf 'Installed Bronze Tee %s in /Applications.\n' "$tag"
printf 'Open Bronze Tee from Applications. macOS may ask you to approve it in Privacy & Security.\n'
