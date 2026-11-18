# Bronze Tee: Game Design Document

Describes the game as it exists (imported prototype). See `README.md` for the full control list. Updated 2026-11-18.

## Pillars
1. Arcade golf with believable ball physics (shared fixed-step C# simulation for live play, previews and club recommendations).
2. Readable feedback: HUD, landing preview, green read, ball trail.
3. Desktop first, mouse swing now, trackball later.

## Core loop
Aim (A/D) and pick club (Q/E, auto-recommended) -> hold mouse, pull down (power), swipe up and release -> ball flies and rolls -> repeat from the new lie -> hole out with the putter -> N for next hole. Four holes from Royal Crest Golf Club's first four (white tees default).

## Controls
Mouse swing; A/D aim; Q/E club; U/I shape; J/K shot type; B spin; G green speed; V landing view; H green read; W/X wind; T tees; [ ] swing speed; F3 debug hole menu; N next hole; R restart; Esc quit. Details in README.

## Rules
- Each completed swing is one stroke. Water adds one penalty stroke and replays from the previous spot.
- Lies (fairway, first cut 92%, rough, bunker) change launch power and rolling resistance.
- Cup is 4.25 in wide; fast putts roll past.
- Round = holes 1 to 4. Score shown relative to par. After hole 4, R starts a new round.

## Win / lose
No lose state. Goal: finish each hole in as few strokes as possible. Scores: par shown on scorecard.

## Tunable values (starting numbers, from code)
| Value | Where | Number |
|---|---|---|
| Driver swing-speed reference | `swing_speed_mph` in `scripts/main.gd` | 105 mph (70 to 130, 5 mph steps) |
| Full driver total distance | calibration | about 280 yd, level fairway, calm |
| Green speed | `green_speed_index` | 10 ft Stimpmeter (8, 10, 12) |
| Wind | randomised per hole | 5 to 20 mph |
| First-cut launch power | lie | 92% |
| Aim step on green | controls | 0.25 deg (0.05 with Shift) |
| Swipe sensitivity | controls | 1.0 (0.5 to 2.0) |
| Course flag colour | not yet located | red (to become blue in the next slice) |

## Current mission
Mission blue-course-flags: change course flags from red to blue, verified in-game. Slice 1 (`docs/slices/check-gate.md`): build the check gate and a normal-game playtest. Slice 2 (next, not yet specified): the flag colour change.

## Team gate
`./tools/check.sh` (build, unit tests, import, headless checks) must pass before any change is done.
