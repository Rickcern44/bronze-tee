# Slice: blue-flags (mission blue-course-flags, slice OPR.99.0.1.2)

## 1. Goal
On every Royal Crest hole (1 to 4) the flag cloth on the cup is blue instead of red-orange, and a scripted playtest of the normal game scene saves one screenshot per hole that shows it.

## Verified source (dev-design, 2026-11-18, commit c899ba2)
- The course flag is built in `scripts/main.gd` in `_build_world()` at line 296: `_box(Vector3(CUP.x + 0.9, _ground_height(CUP.x, CUP.z) + 3.6, CUP.z), Vector3(1.8, 0.8, 0.08), Color(0.96, 0.35, 0.18))`. Line 295 is the pole (`Vector3(0.012, 4.0, 0.012)`, `Color(0.95, 0.94, 0.82)`). `_build_world()` runs for every hole through `_load_hole()`, so one edit covers all four holes (`resources/holes/royal_crest_01..04.tres`). Nothing else in `scripts/`, `scenes/`, `resources/` or `shaders/` builds a course flag.
- `HudPalette.FLAG` (`scripts/ui/hud_palette.gd:18`, `F0562E`) is a separate UI accent used by the tree warning marker (`landing_marker.gd`) and the ball-trail tint (`ball_trail.gd`). **It is not the course flag. Do not change it.**
- No existing test refers to the flag colour (`grep` for the colour and for `_box(` in `tests/`: no hits).

## 2. Files
| File | Change |
|---|---|
| `scripts/main.gd` | Add one constant; use it at line 296; name the two nodes (see section 3). |
| `tests/playtest/blue_flags_playtest.gd` (new) | Per-hole flag screenshots and colour checks. |
| `tests/playtest/normal_game_playtest.gd` | Comment only: step 3 comment "(currently red)" becomes "(blue)". No logic change. |
| `docs/design/GDD.md`, `docs/slices/blue-flags.md` | Written by dev-design; commit with the slice. |

Change nothing else. No change to pole, flag size, position, `HudPalette`, tests/*_check.gd, dotnet.

## 3. Types and functions
In `scripts/main.gd`:
1. Add near the other constants (after line 84): `const FLAG_COLOR := Color(0.08, 0.30, 0.92) # course flag cloth, blue`.
2. Line 295: keep as is but capture the result: `var pole := _box(...); pole.name = "CupPole"`. (Geometry and colour unchanged.)
3. Line 296: `var flag := _box(Vector3(CUP.x + 0.9, _ground_height(CUP.x, CUP.z) + 3.6, CUP.z), Vector3(1.8, 0.8, 0.08), FLAG_COLOR); flag.name = "CupFlag"`.
Names let the playtest find the nodes with `game.find_child("CupFlag", false, false)`. `_load_hole()` frees the previous hole's nodes, so exactly one `CupFlag` exists at a time.

## 4. Constants
| Name | Where | Value |
|---|---|---|
| `FLAG_COLOR` | `scripts/main.gd` | `Color(0.08, 0.30, 0.92)` (hex about `144DEB`) |
| Distances tried from cup | `APPROACH_DISTANCES` in playtest | `[25.0, 40.0, 18.0]` metres, in that order |
| Settle frames | `SETTLE_FRAMES` in playtest | 90 |
| Min projected flag width | `MIN_FLAG_PX` in playtest | 20 px |
| Sample window | `WIN_X`, `WIN_Y` in playtest | 6 px, 3 px half-size (13 x 7 px) |
| Pixel thresholds | in playtest | mean `b >= 0.55`, `b - r >= 0.30`, `b - g >= 0.20` |
| Output dir | `OUT_DIR` in playtest | `OS.get_environment("FLAG_OUT_DIR")` or default `playtest-output/blue_flags` |

Why those thresholds: the sky is `(0.48, 0.70, 0.86)`, so `b - g` is 0.16 and fails; a lit blue flag passes. Red-orange has `b < r`, fails.

## 5. Steps
1. Edit `scripts/main.gd` per section 3.
2. Write `tests/playtest/blue_flags_playtest.gd` per section 8, same helpers as `normal_game_playtest.gd` (`wait`, `shot`, `valid`, `step`).
3. Before-run with the temporary red colour substitution described in section 8; revert; confirm the revert with `git diff`.
4. `./tools/check.sh` passes.
5. `./tools/playtest.sh normal_game` and `./tools/playtest.sh blue_flags` pass.
6. Commit (hook runs the gate): `Make course flags blue`.

## 6. Unit tests
None. This is a visual constant with no C# logic.

## 7. Headless checks
No new or changed `tests/*_check.gd`. The 27 existing checks run unchanged. (The flag is built headless too, so `gameplay_check.gd` and others already exercise `_build_world()`; they must stay green.)

## 8. Playtest script: `tests/playtest/blue_flags_playtest.gd`
Run: `./tools/playtest.sh blue_flags` (wrapper isolates Godot paths and scans the log).

Setup as in `normal_game_playtest.gd`: instantiate `res://scenes/main.tscn`, add to root, `DirAccess.make_dir_recursive_absolute(OUT_DIR)`.

Helper `flag_check(game) -> Dictionary` returns `{found, color_ok, px, mean}`:
- `var flag = game.find_child("CupFlag", false, false)`; `found = flag != null`.
- `color_ok = flag.material_override.albedo_color.is_equal_approx(game.FLAG_COLOR)`. `FLAG_COLOR` and both node names exist in every run, including the before-run.
- Project the flag centre: `var c: Vector2 = game.camera.unproject_position(flag.global_position)`; `behind = game.camera.is_position_behind(flag.global_position)`. Projected width `px`: `abs(unproject_position(flag.global_position + Vector3(0.9,0,0)).x - unproject_position(flag.global_position - Vector3(0.9,0,0)).x)`.
- Mean colour of the window `c +/- (WIN_X, WIN_Y)` (clamped to the image) in the screenshot taken for that hole.

Per hole `h` in 1 to 4 (steps 1 to 4), call `game._load_hole(h - 1)`, then for each `d` in `APPROACH_DISTANCES` until a distance passes:
1. Place the ball on the straight line from the cup: `var p = game.CUP + Vector3(0, 0, d)`; `p.y = game._ground_height(p.x, p.z) + game.BALL_RADIUS`; `game.ball_position = p; game.ball.position = p`.
2. Point the camera at the cup. The camera heading is derived every frame inside `main.gd` from `game.aim` (degrees): direction `(sin(aim), 0, -cos(aim))`; there is no `view_direction` member. Set `game.club_index = 0` (driver, so the full-shot camera is used, not the low putting camera), `game.aim = 0.0` (the ball is placed directly south of the cup, so the cup is straight ahead along -Z; for a general ball position `aim = rad_to_deg(atan2(v.x, -v.z))` with `v = CUP - p`). The camera then settles to 12 m behind and 7 m above the ball, looking 6 m ahead of it.
3. `game._update_hud()`, `await wait(SETTLE_FRAMES)` (the camera lerps toward its target; `game.camera` is `Camera3D`). Record `game.club_index` in the step output; if the game switched it back to the putter, report it, `shot("flag_hole<h>_d<d>")`.
4. A distance passes when: `found`, `not behind`, `px >= MIN_FLAG_PX`, the centre `c` is inside the 1280x720 frame, and the thresholds in section 4 hold.
Keep the passing screenshot and also copy it to `flag_hole<h>.png`. Delete failed attempts or keep them; report which distance passed.

| # | Input / call | Screenshot | PASS when |
|---|---|---|---|
| 1 | Hole 1 as above | `flag_hole1.png` | `found`, `color_ok`, some distance passes the pixel check, `valid(img)` (1280x720, at least 50 colours) |
| 2 | Hole 2 | `flag_hole2.png` | same |
| 3 | Hole 3 | `flag_hole3.png` | same |
| 4 | Hole 4 | `flag_hole4.png` | same |
| 5 | Pole and geometry unchanged: on hole 1, `CupPole` exists; its `mesh.size == Vector3(0.012, 4.0, 0.012)`, albedo `Color(0.95, 0.94, 0.82)`; `CupFlag` mesh size `Vector3(1.8, 0.8, 0.08)` | none | all equal |
| 6 | HUD accent untouched: `HudPalette.FLAG == Color("F0562E")` | none | equal |
| 7 | No earlier step failed | none | `failures == 0` (the wrapper then scans the log) |

Print `PASS step N: ...` / `FAIL step N: ...` with the numbers measured (distance used, px, mean r g b). `quit(0 if failures == 0 else 1)`.

"Before" run (colour-only substitution, sandboxed): after the full edit of section 3 is in the working tree, temporarily change only the colour argument on the flag line from `FLAG_COLOR` to `Color(0.96, 0.35, 0.18)` (the original red-orange). Keep `const FLAG_COLOR` (blue, the reference), the node names and all geometry. Run `FLAG_OUT_DIR=playtest-output/blue_flags_before ./tools/playtest.sh blue_flags`. Required result: steps 1 to 4 each print `FAIL` (colour mismatch against `FLAG_COLOR` and pixel thresholds not met) while their screenshots are still saved and valid; steps 5 and 6 print `PASS`; step 7 prints `FAIL`; wrapper exits non-zero. The screenshots must show a red-orange flag. Then revert the substitution (flag line uses `FLAG_COLOR` again), confirm with `git diff scripts/main.gd` that the flag line shows `FLAG_COLOR`, and run the "after" run. Both runs go through the wrapper, so Godot config, data and cache stay in the temp sandbox.

Playtester (Luna) reads each `flag_holeN.png` in the "after" run and reports, per hole: pass or fail, the flag colour seen in plain words, and whether the flag is clearly visible (not hidden by trees or off-screen). Also look at the "before" images once to confirm they were red-orange. Do not judge feel. If the colour looks blue in the image but the pixel thresholds fail (for example because of lighting), report the measured mean r g b to dev-design; do not loosen the thresholds yourself.

## Acceptance steps (lead)
1. `git diff` shows only: `FLAG_COLOR` constant, the two `_box` lines in `scripts/main.gd`, the new playtest, the comment edit, and the two docs. `HudPalette` is untouched.
2. `./tools/check.sh` passes (27 checks, 83 xUnit).
3. `./tools/playtest.sh normal_game` passes.
4. `./tools/playtest.sh blue_flags` prints `PASS step 1` to `PASS step 7` and `PLAYTEST PASSED`.
5. `playtest-output/blue_flags/flag_hole1..4.png` exist; the playtester describes each flag as blue; `playtest-output/blue_flags_before/` images show red-orange.
6. The lead (or the operator) opens one image to confirm. The person plays the game for how it looks and feels on their own machine.

## 9. Out of scope
- Any change to the pole, flag size, shape, position, waving or lighting.
- Any `HudPalette` colour; tree marker and ball trail keep red-orange.
- New holes, tees or other course colours.
- Judging game feel.
