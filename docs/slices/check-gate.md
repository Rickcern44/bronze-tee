# Slice: check-gate (mission blue-course-flags, slice OPR.99.0.1.1)

## 1. Goal
`./tools/check.sh` exists, passes on a clean checkout, and a git `pre-commit` hook runs it; a scripted playtest of the normal game saves screenshots (including the course flag, still red) that the person can open. **Do not change any flag colour in this slice.**

## Baseline (measured by dev-design on 2026-11-18, before this slice)
- `dotnet build BronzeTee.Godot.csproj`: succeeded, 0 warnings, 0 errors (3 s).
- `dotnet test dotnet/BronzeTee.Physics.Tests`: 83 passed, 0 failed.
- `godot --headless --path . --import`: exit 0.
- All 27 `tests/*_check.gd` exit 0 with no `SCRIPT ERROR` / `Assertion failed` / `ERROR:` line; each takes 0 to 4 s.
- **No real baseline failures.** Nothing to fix or exempt. Existing tests must stay unchanged.
- Known gap: `git config core.hooksPath` is unset and `.git/hooks` has no hook. `tests/playtest/` does not exist.

## 2. Files
| File | Purpose |
|---|---|
| `tools/check.sh` (new, mode 755) | The one gate command. |
| `tools/install-hooks.sh` (new, mode 755) | Writes `.git/hooks/pre-commit`. |
| `.git/hooks/pre-commit` (generated, not committed) | Runs `./tools/check.sh`. |
| `tools/playtest.sh` (new, mode 755) | Runs one playtest: `./tools/playtest.sh <slug>`. |
| `tests/playtest/normal_game_playtest.gd` (new) | Scripted playtest of the normal game with screenshots. |
| `docs/design/GDD.md`, `docs/slices/check-gate.md` | Written by dev-design; commit them with the slice, do not edit. |
| `README.md` | Add one section "Check gate" (see step 7). |

Change nothing else. Do not edit `tests/*_check.gd`, `dotnet/`, `scripts/`, `scenes/`.

## 3. Behaviour of `tools/check.sh`
Bash, `#!/usr/bin/env bash`, `set -u -o pipefail`. `cd "$(dirname "$0")/.."` first. Stop at the first failing stage with a non-zero exit; print `==> <stage>` before each stage and `CHECK GATE PASSED` at the end.

Stages, in this order:
1. **build**: `dotnet build BronzeTee.Godot.csproj -warnaserror`. (Baseline has 0 warnings, so warnings-as-errors is safe.)
2. **unit tests**: for each `dotnet/*.Tests` directory, `dotnet test "$dir" --no-restore`. (Only `dotnet/BronzeTee.Physics.Tests` exists today.) Fail if a directory has no tests.
3. **import**: `timeout 120 godot --headless --path . --import`, output saved to a temp log. Fail on non-zero exit, on time-out (exit 124), or if the output contains a bad line (below).
4. **checks**: for each `tests/*_check.gd` in sorted order, `timeout 120 godot --headless --path . --script res://tests/<name>.gd`, output saved to a temp log and echoed. Print `PASS <name> (<n>s)` or `FAIL <name>: <reason>` where reason is `exit <code>`, `timeout`, or `bad output line`. Stop at the first failure after printing the last 30 log lines.

Bad output line (extended regex, case-sensitive) for stages 3 and 4: `SCRIPT ERROR|Assertion failed|^ERROR:`.

Godot isolation: after creating `LOGDIR`, export `XDG_CONFIG_HOME="$LOGDIR/config"`, `XDG_DATA_HOME="$LOGDIR/data"` and `XDG_CACHE_HOME="$LOGDIR/cache"` (mkdir all three) before stages 3 and 4, so Godot never writes to the runner's `~/.config/godot`, `~/.local/share/godot` or `~/.cache/godot` (the editor help cache) (a seat with a read-only HOME failed import with "Cannot save file editor_settings-4.7.tres"). Do not change `HOME`: dotnet and NuGet need it. Stage 1 and 2 run before the export or are unaffected by it. The project's own `.godot/` cache stays in the repo.

Temp logs go in `mktemp -d` with `trap 'rm -rf "$LOGDIR"' EXIT`.

The script must not run the playtest (it needs Xvfb and is slow). The playtest is run separately.

## 4. Constants
| Name | Where | Value |
|---|---|---|
| Per-check time limit | `CHECK_TIMEOUT` in `tools/check.sh` | 120 s |
| Import time limit | `IMPORT_TIMEOUT` in `tools/check.sh` | 120 s |
| Bad-line regex | `BAD_RE` in `tools/check.sh` | `SCRIPT ERROR\|Assertion failed\|^ERROR:` |
| Screenshot dir | `OUT_DIR` in playtest | `playtest-output/normal_game` |
| Playtest wait per step | `STEP_FRAMES` in playtest | 10 frames |
| Playtest overall limit | `timeout 300` on the run command | 300 s |

## 5. Steps
1. Write `tools/check.sh` per section 3. `chmod +x`.
2. Write `tools/install-hooks.sh`: writes `.git/hooks/pre-commit` containing `#!/usr/bin/env bash` / `exec ./tools/check.sh`, `chmod +x`. Run it once.
3. Run `./tools/check.sh`; it must exit 0 and print `CHECK GATE PASSED`.
4. Prove the gate can fail (see section 6, negative tests). Revert each temporary change afterwards; confirm `git status` shows only the intended files.
5. Write `tests/playtest/normal_game_playtest.gd` per section 8. Run it.
6. Do not run the pre-commit hook with `--no-verify`.
7. README: add a short "Check gate" section: run `./tools/check.sh`; run `./tools/install-hooks.sh` once per clone; the playtest command.
8. Commit (hook runs the gate) with message `Add check gate and normal-game playtest`.

## 6. Unit tests (gate self-tests, run by hand once by build, results reported)
No new xUnit tests. Negative tests, each temporary and reverted:
| # | Given | When | Then |
|---|---|---|---|
| N1 | `tests/club_distance_check.gd` has a line `assert(false, "x")` added at the end of `check` (or the equivalent top-level function) | `./tools/check.sh` | exit non-zero; prints `FAIL club_distance_check.gd: bad output line` (a failing assert can leave Godot hanging until the limit, so the bad-line test is applied before the timeout test); later checks do not run |
| N2 | a temporary `tests/zz_hang_check.gd` containing `func _initialize(): while true: pass`; run with `CHECK_TIMEOUT=10` env override (2 s would also trip the real `migrated_holes_check.gd`) | `./tools/check.sh` | prints `FAIL zz_hang_check.gd: timeout`; exit non-zero. (So `CHECK_TIMEOUT` must be `${CHECK_TIMEOUT:-120}`.) |
| N3 | a temporary syntax error in `scripts/PhysicsBridge.cs` | `./tools/check.sh` | stage 1 fails, exit non-zero, no later stage runs |
| N5 | `HOME` points to a read-only empty directory (`HOME=$(mktemp -d); chmod a-w $HOME`) but `DOTNET_CLI_HOME` and `NUGET_PACKAGES` point at the real ones | `./tools/check.sh` | stages 3 and 4 pass (Godot config goes to the temp dir). If the build stage cannot run with that HOME, report it; that is outside this slice |
| N4 | N1 change in place | `git commit` of an unrelated trivial change | commit is refused by the hook |

If any of N1 to N4 does not behave as stated, that is a spec gap: report it to dev-design.

## 7. Headless checks
No new or changed `tests/*_check.gd`. The 27 existing ones are run unchanged by stage 4.

## 8. Playtest script: `tests/playtest/normal_game_playtest.gd`
`extends SceneTree`. Run with the wrapper (the only supported way; it isolates Godot paths so a read-only HOME does not matter):
`./tools/playtest.sh normal_game`

`tools/playtest.sh <slug>` (bash, `set -u -o pipefail`, cd to repo root): `LOGDIR=$(mktemp -d)`, trap-remove it; `mkdir` and export `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME` under `$LOGDIR`; run `xvfb-run -a -s "-screen 0 1280x720x24" timeout 300 godot --audio-driver Dummy --path . --script res://tests/playtest/<slug>_playtest.gd 2>&1 | tee "$LOGDIR/out.log"`; keep the exit code; then if `out.log` matches `SCRIPT ERROR|Assertion failed|^ERROR:` print `FAIL log scan: <matching lines>` and exit 1; if the script exit code is non-zero exit with it; else print `PLAYTEST PASSED`. Exit 2 with a usage message if the script file does not exist.

The raw command it wraps, for reference only:
`xvfb-run -a -s "-screen 0 1280x720x24" timeout 300 godot --audio-driver Dummy --path . --script res://tests/playtest/normal_game_playtest.gd`

Use `call_deferred("run")` in `_initialize`, `var game = load("res://scenes/main.tscn").instantiate(); root.add_child(game)`. Create `OUT_DIR` with `DirAccess.make_dir_recursive_absolute`. Helper `wait(n)`: `for i in n: await process_frame`. Helper `shot(name)`: `await RenderingServer.frame_post_draw`, then `root.get_viewport().get_texture().get_image().save_png(OUT_DIR + "/" + name + ".png")`. Helper `step(n, ok, text)`: print `PASS step N: text` or `FAIL step N: text`. After the last step, `quit(0 if no failures else 1)`.

A screenshot is "valid" when the file exists, width 1280 and height 720, and the image has at least 50 distinct colours when sampled on a 32x18 grid (so a blank frame fails).

| # | Input / call | Wait | Screenshot | PASS when |
|---|---|---|---|---|
| 1 | Instantiate `main.tscn` and add to root | `wait(STEP_FRAMES)` | `01_tee_hole1.png` | `game.hole_index == 0`, `game.strokes == 0`, `game.hole_complete == false`, screenshot valid |
| 2 | Call `game._load_hole(1)` (hole 2), then `game._update_hud()` | `wait(STEP_FRAMES)` | `02_hole2_tee.png` | `game.hole_index == 1`, screenshot valid |
| 3 | Call `game._load_hole(0)`. Place ball near cup: `game.ball_position = game.CUP + Vector3(0, game.BALL_RADIUS, 6.0)`; `game.ball.position = game.ball_position`; `game._update_hud()` | `wait(STEP_FRAMES)` | `03_near_cup_flag.png` | `game.ball_position.distance_to(game.CUP)` between 5.5 and 6.5, screenshot valid. **Evidence for the operator:** this image should show the flag (currently red). Reporter states what colour the flag is in the image. |
| 4 | Call `game._load_hole(0)`, wait, then drive one real shot with synthetic mouse input via `Input.parse_input_event`: press left button at (640, 400); motion to (640, 460) (pull back); motion to (640, 200) (swipe up); release. Every motion event sets both `relative` and `screen_relative` (the game reads `screen_relative`). Send each event, then `wait(2)`. | `wait(120)` frames or until `game.in_motion` becomes false after having been true, max 600 frames | `04_after_shot.png` | `game.strokes == 1` and `game.in_motion == false`, screenshot valid. If synthetic input does not produce a stroke, report the exact events tried and the values of `swing_active`, `backswing`, `strokes`; do not substitute method calls without telling dev-design. |
| 5 | Call `game._reset_ball()` (restart, same as R) | `wait(STEP_FRAMES)` | `05_restart.png` | `game.strokes == 0`, screenshot valid |
| 6 | Log scan | n/a | none | performed by `tools/playtest.sh`, not by the .gd script: no `SCRIPT ERROR`, `Assertion failed` or `^ERROR:` line in the captured output, and exit code 0. The .gd script prints `PASS step 6: no earlier step failed` itself; the wrapper prints `PLAYTEST PASSED` only if the scan is also clean |

Playtester (Luna) reads each PNG and reports for each step: pass or fail, plus one line describing what the image shows (hole, ball, HUD visible, flag colour in step 3). Do not report anything about game feel.

## Acceptance steps (lead)
1. `./tools/check.sh` exits 0 and prints `CHECK GATE PASSED`.
2. N1 to N4 reported with their actual output.
3. `.git/hooks/pre-commit` exists and is executable; the commit of this slice went through it.
4. `./tools/playtest.sh normal_game` prints `PASS step 1` to `PASS step 6` and `PLAYTEST PASSED`, also with `HOME` set to a read-only directory; `playtest-output/normal_game/` contains the five PNGs.
5. `git diff` for the slice touches only the files in section 2, and no flag colour or `HudPalette.FLAG` change. (Note: `HudPalette.FLAG` is `F0562E`, a UI accent also used for the tree warning marker and ball trail; the course flag object has not been located yet. Locating it is the first task of the blue-flag slice, not this one.)

## 9. Out of scope
- Changing any flag colour or any game code.
- Adding or editing xUnit tests or `tests/*_check.gd`.
- CI, formatting tools, linters.
- Running the playtest inside `check.sh`.
- Judging game feel.
