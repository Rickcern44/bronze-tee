#!/usr/bin/env bash
# Bronze Tee asset pipeline driver. See docs/assets/PIPELINE.md section 3.
set -euo pipefail

BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
GODOT="${GODOT:-$HOME/Downloads/Godot_mono.app/Contents/MacOS/Godot}"
PYTHON="${PYTHON:-python3}"
export PYTHONDONTWRITEBYTECODE=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAMILIES=(trees props nature)
WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; return 0; }
trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: tools/pipeline.sh <command>

  check         environment: Blender, Godot, Python, Pillow found?
  textures      build + validate textures
  models        build all models with Blender, validate in Godot
  previews      regenerate model thumbnails, lineups and contact sheets
  determinism   build twice, compare hashes
  all           check, textures, models, previews, determinism

Env: BLENDER, GODOT, PYTHON (see docs/assets/PIPELINE.md)
EOF
}

header() { printf '\n==== %s ====\n' "$1"; }

# run a command, print it and its exit code on failure
run() {
  local rc=0
  printf '+ %s\n' "$*"
  "$@" || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'FAILED (exit %d): %s\n' "$rc" "$*" >&2
    return "$rc"
  fi
}

alarm() { local secs="$1"; shift; run perl -e 'alarm shift; exec @ARGV' "$secs" "$@"; }

cmd_check() {
  header "check"
  local missing=0
  if [ -x "$BLENDER" ]; then echo "found:   BLENDER=$BLENDER"; else echo "missing: BLENDER=$BLENDER"; missing=1; fi
  if [ -x "$GODOT" ]; then echo "found:   GODOT=$GODOT"; else echo "missing: GODOT=$GODOT"; missing=1; fi
  if command -v "$PYTHON" >/dev/null 2>&1; then echo "found:   PYTHON=$PYTHON ($("$PYTHON" --version 2>&1))"; else echo "missing: PYTHON=$PYTHON"; missing=1; fi
  if command -v "$PYTHON" >/dev/null 2>&1 && "$PYTHON" -c 'import PIL' >/dev/null 2>&1; then
    echo "found:   Pillow ($("$PYTHON" -c 'import PIL; print(PIL.__version__)'))"
  else
    echo "missing: Pillow (python import PIL)"; missing=1
  fi
  if [ -x "$BLENDER" ]; then
    local v
    v="$("$BLENDER" --version 2>/dev/null | head -n 1 || true)"
    if [ -n "$v" ]; then echo "found:   Blender version: $v"; else echo "missing: Blender version line"; missing=1; fi
  else
    echo "missing: Blender version line"
  fi
  if [ "$missing" -ne 0 ]; then echo "check: something is missing" >&2; return 1; fi
  echo "check: all found"
}

cmd_textures() {
  header "textures: build"
  run "$PYTHON" "$ROOT/tools/textures/build.py"
  header "textures: validate"
  run "$PYTHON" "$ROOT/tools/textures/validate.py"
}

cmd_models() {
  header "models: Blender build (all families)"
  alarm 900 "$BLENDER" -b --factory-startup --python-exit-code 1 -P "$ROOT/tools/blender/build.py" --
  header "models: Godot validate"
  alarm 300 "$GODOT" --headless --path "$ROOT" --script res://tools/assets/validate.gd
}

cmd_previews() {
  local f
  for f in "${FAMILIES[@]}"; do
    header "previews: $f"
    alarm 900 "$BLENDER" -b --factory-startup --python-exit-code 1 -P "$ROOT/tools/blender/previews.py" -- --family="$f"
    run "$PYTHON" "$ROOT/tools/blender/contact_sheet.py" --family="$f"
  done
  header "previews: autumn trees lineup"
  alarm 900 "$BLENDER" -b --factory-startup --python-exit-code 1 -P "$ROOT/tools/blender/previews.py" -- --family=trees --palette=autumn --skip-thumbs
}

hash_all() {
  local out="$1"
  (
    cd "$ROOT"
    {
      local f
      for f in "${FAMILIES[@]}"; do
        find "assets/models/$f" -maxdepth 1 -type f -name '*.glb'
      done
      [ -f assets/models/manifest.json ] && echo assets/models/manifest.json
      find assets/models/palette -type f -name '*.png' 2>/dev/null
      find assets/textures/library -type f -name '*.png' -not -path '*/_previews/*' 2>/dev/null
      [ -f assets/textures/library/manifest.json ] && echo assets/textures/library/manifest.json
    } | LC_ALL=C sort -u | while IFS= read -r p; do shasum -a 256 "$p"; done
  ) > "$out"
}

cmd_determinism() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/bt-pipeline.XXXXXX")"
  header "determinism: hash existing outputs"
  hash_all "$WORK/before.txt"
  echo "hashed $(wc -l < "$WORK/before.txt" | tr -d ' ') files"
  cmd_textures
  cmd_models
  header "determinism: hash rebuilt outputs"
  hash_all "$WORK/after.txt"
  echo "hashed $(wc -l < "$WORK/after.txt" | tr -d ' ') files"
  header "determinism: compare"
  if diff -q "$WORK/before.txt" "$WORK/after.txt" >/dev/null; then
    echo "PASS"
  else
    echo "FAIL: differing files:" >&2
    diff "$WORK/before.txt" "$WORK/after.txt" | awk '/^[<>]/ {print $4}' | sort -u >&2
    return 1
  fi
}

cmd_all() {
  local start=$SECONDS step rc
  local summary=() failed=0
  for step in check textures models previews determinism; do
    rc=0
    "cmd_$step" || rc=$?
    if [ "$rc" -eq 0 ]; then summary+=("$step: OK"); else summary+=("$step: FAIL (exit $rc)"); failed=1; break; fi
  done
  header "summary"
  printf '%s\n' "${summary[@]}"
  echo "total time: $((SECONDS - start))s"
  return "$failed"
}

case "${1:-}" in
  check)       cmd_check ;;
  textures)    cmd_textures ;;
  models)      cmd_models ;;
  previews)    cmd_previews ;;
  determinism) cmd_determinism ;;
  all)         cmd_all ;;
  *)           usage >&2; exit 2 ;;
esac
