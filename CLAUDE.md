# Bronze Tee — project contract

## Stack

- Godot: 4.7.2 `.mono` build
- Languages: GDScript + C#
- .NET: SDK 10.x, `net10.0`
- Main scene: `res://scenes/main.tscn`
- Base branch: `main`

## Verification gate

This repo already has one check gate. Run it; do not recreate its commands inline:

```bash
./tools/check.sh
```

It runs, in order:

1. course-import offline tests (`python3 -m unittest discover -s tests -p 'test_*.py'`)
2. `dotnet build BronzeTee.Godot.csproj -warnaserror`
3. `dotnet test` for every `dotnet/*.Tests` project
4. headless Godot import
5. every `tests/*_check.gd` script

Playtest scenarios use a virtual display and live in `tests/playtest/`:

```bash
./tools/playtest.sh normal_game
./tools/playtest.sh blue_flags
```

To produce a full game-team playtest report with the global harness:

```bash
~/.claude/skills/game-team/scripts/godot-playtest.sh \
  --path . \
  --verify "check gate|./tools/check.sh" \
  --verify "playtest normal_game|./tools/playtest.sh normal_game" \
  --report .playtest
```

Drop the second `--verify` when you only need the check gate.

## Game team

Use the global `game-team` skill and its agents for feature work:

- `game-orchestrator` sequences the work
- `game-implementer` writes code and opens a PR
- `game-playtester` runs the headless ladder and returns PASS/FAIL
- `game-reviewer` waits for CI and reviews
- `game-merger` merges only after all three gates pass

The playtester must include `./tools/check.sh` as a `--verify` step.

## Conventions

- C#-only rules live in `.claude/rules/godot-csharp.md`.
- Keep physics logic in `dotnet/BronzeTee.Physics` with matching tests in `dotnet/BronzeTee.Physics.Tests`.
- Add new headless checks as `tests/<name>_check.gd`; the gate discovers them automatically.
- Do not commit `bin/`, `obj/`, `.godot/`, or generated `.import` changes unless intentional.
