#!/bin/bash
# Build Bronze Tee from source on macOS and install it in /Applications.
#
#   tools/utils/build-macos.sh              # update main, build, sign, test, install
#   tools/utils/build-macos.sh --no-pull    # build the current checkout as is
#   tools/utils/build-macos.sh --check      # also run ./tools/check.sh first
#
# Needs Godot 4.7.2 .NET (GODOT_BIN, `godot` on PATH, or Godot.app in
# /Applications or ~/Applications), the .NET 10 SDK and the Godot 4.7.2 .NET
# export templates. Stamps the GitVersion version into project.godot and
# export_presets.cfg for the export only; they are always restored.
# CI does not sign or smoke-test the app, so this script does both locally.
set -euo pipefail

app='/Applications/Bronze Tee.app'
godot_version='4.7.2'
pull=1
check=0

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}
for arg in "$@"; do
  case "$arg" in
    --no-pull) pull=0 ;;
    --check) check=1 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

if [ "$(uname -s)" != Darwin ]; then
  echo 'Run this script on a Mac.' >&2
  exit 1
fi

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"

work=$(mktemp -d "${TMPDIR:-/tmp}/bronze-tee-build.XXXXXX")
staged="/Applications/.Bronze-Tee-build-$$.app"
backup="/Applications/.Bronze-Tee-backup-$$.app"
stamped=0
cleanup() {
  if [ -d "$backup" ] && [ ! -e "$app" ]; then
    mv "$backup" "$app" || echo "Restore the previous app from $backup" >&2
  fi
  if [ "$stamped" -eq 1 ]; then
    tools/version.sh --restore >/dev/null || echo 'Run tools/version.sh --restore to undo the version stamp.' >&2
  fi
  rm -rf "$work" "$staged"
}
trap cleanup EXIT

# --- Dependencies: collect everything that is missing, then report once. ---
missing=()
godot="${GODOT_BIN:-}"
if [ -z "$godot" ]; then
  for candidate in "$(command -v godot || true)" \
      /Applications/Godot_mono.app/Contents/MacOS/Godot \
      "$HOME/Applications/Godot_mono.app/Contents/MacOS/Godot" \
      /Applications/Godot.app/Contents/MacOS/Godot \
      "$HOME/Applications/Godot.app/Contents/MacOS/Godot"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      godot="$candidate"
      break
    fi
  done
fi
if [ -z "$godot" ] || [ ! -x "$godot" ]; then
  missing+=("Godot $godot_version .NET: install it, or set GODOT_BIN to its executable")
else
  version=$("$godot" --version 2>/dev/null | tail -n 1 || true)
  case "$version" in
    "$godot_version".*.mono.*) ;;
    *) missing+=("Godot $godot_version .NET: $godot reports '${version:-nothing}' (need $godot_version.*.mono.*)") ;;
  esac
fi
if ! command -v dotnet >/dev/null || [ "$(dotnet --version 2>/dev/null | cut -d. -f1)" != 10 ]; then
  missing+=('.NET 10 SDK: install it from https://dotnet.microsoft.com/download/dotnet/10.0')
fi
templates="$HOME/Library/Application Support/Godot/export_templates/$godot_version.stable.mono"
if [ ! -d "$templates" ]; then
  missing+=("Godot $godot_version .NET export templates: in Godot use Editor > Manage Export Templates (expected $templates)")
fi
for tool in python3 git codesign ditto; do
  command -v "$tool" >/dev/null || missing+=("$tool: not found on PATH")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo 'Cannot build Bronze Tee. Missing:' >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi

# --- Source: main, clean, fast-forwarded (unless --no-pull). ---
if [ "$pull" -eq 1 ]; then
  if [ -n "$(git status --porcelain)" ]; then
    echo 'The working tree has changes. Commit or stash them, or use --no-pull to build as is.' >&2
    exit 1
  fi
  if [ "$(git rev-parse --abbrev-ref HEAD)" != main ]; then
    echo 'Not on main. Switch to main, or use --no-pull to build this checkout.' >&2
    exit 1
  fi
  git pull --ff-only
fi
if ! git diff --quiet HEAD -- project.godot export_presets.cfg; then
  echo 'project.godot or export_presets.cfg has local changes; restore them first.' >&2
  exit 1
fi

# An app that is running cannot be replaced; check before the long build.
if /usr/bin/osascript -e 'application id "com.cernylabs.bronzetee" is running' | grep -qx true; then
  echo 'Quit Bronze Tee, then run this script again.' >&2
  exit 1
fi
if [ ! -w /Applications ]; then
  echo 'You do not have permission to write to /Applications.' >&2
  exit 1
fi

dotnet tool restore
if [ "$check" -eq 1 ]; then
  ./tools/check.sh
fi

# --- Stamp, import, export. The trap restores the stamped files. ---
stamped=1
tools/version.sh --stamp
installed=$(tools/version.sh --get DisplayVersion)
"$godot" --headless --path . --import >"$work/import.log" 2>&1 || {
  tail -n 40 "$work/import.log" >&2
  echo 'The Godot import failed.' >&2
  exit 1
}
mkdir -p "$work/out"
"$godot" --headless --path . --export-release macOS "$work/out/Bronze-Tee-macOS.zip" 2>&1 | tee "$work/export.log"
if grep -Eq '(^ERROR:|SCRIPT ERROR|Unhandled exception)' "$work/export.log"; then
  echo 'Godot reported an export error.' >&2
  exit 1
fi
test -s "$work/out/Bronze-Tee-macOS.zip"
tools/version.sh --restore
stamped=0

# --- Unpack, sign, smoke test. ---
ditto -x -k "$work/out/Bronze-Tee-macOS.zip" "$work/unpacked"
built="$work/unpacked/Bronze Tee.app"
[ -f "$built/Contents/MacOS/Bronze Tee" ] || { echo 'The app is missing from the export.' >&2; exit 1; }
codesign --force --deep --sign - "$built"
codesign --verify --deep --strict "$built"
"$built/Contents/MacOS/Bronze Tee" --headless --quit-after 5 > "$work/game.log" 2>&1
if grep -Eq '(^ERROR:|SCRIPT ERROR|Unhandled exception)' "$work/game.log"; then
  head -80 "$work/game.log" >&2
  echo 'The built game reported an error.' >&2
  exit 1
fi

# --- Install with backup/restore. ---
ditto "$built" "$staged"
codesign --verify --deep --strict "$staged"
if [ -e "$app" ]; then
  mv "$app" "$backup"
fi
mv "$staged" "$app"
if [ -d "$backup" ]; then
  rm -rf "$backup"
fi
printf 'Installed Bronze Tee %s in /Applications.\n' "$installed"
printf 'Open Bronze Tee from Applications. macOS may ask you to approve it in Privacy & Security.\n'
