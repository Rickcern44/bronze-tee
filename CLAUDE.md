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

## Commits and releases

Every agent (game-team and infra-dev alike) follows these rules. Details: README.md "Versioning and releases".

- Commits follow Conventional Commits 1.0.0: `type(scope): RCE-nnn subject`. The Linear key goes at the start of the subject, right after `: ` (e.g. `feat(course): RCE-169 bake surface maps`); a `Refs: RCE-nnn` footer is also accepted. Types: feat, fix, perf, refactor, docs, test, build, ci, chore, style, revert. Scope is optional and lowercase (course, physics, ui, infra, ci, ...). Breaking: `type(scope)!:` or a `BREAKING CHANGE:` footer. Never use the old `RCE-nnn: Subject` form.
- PR titles must be conventional too: PRs are squash-merged and the squash commit uses the title. CI (`.github/workflows/conventional-commits.yml`) checks the title and every commit with `tools/check-commit-msg.sh`; run it locally before pushing.
- Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- PR bodies end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- Version source: git tags via GitVersion (`GitVersion.yml`, tool pinned in `.config/dotnet-tools.json`). No hand-edited version file. Tags are `vX.Y.Z`; `main` computes the plain next `X.Y.Z` (no alpha pre-releases); branches get a branch label. `tools/version.sh` prints it; `tools/version.sh --stamp` is for export/CI only, and stamped `project.godot` / `export_presets.cfg` must never be committed.
- Releases: every push (squash merge) to `main` is released by CI (`.github/workflows/macos.yml`): it creates the annotated tag `vX.Y.Z` on the merge commit and publishes a stable GitHub Release with `Bronze-Tee-macOS.zip`. The PR title decides the bump, so merging is releasing.
- Release notes: no committed changelog. git-cliff (`cliff.toml`) renders the notes into each GitHub Release; preview with `git cliff --unreleased --strip all`. Do not recreate `CHANGELOG.md`.
- Implementers and agents never tag, publish, or move tags by hand; CI does it on merge. A maintainer pushes a `vX.Y.Z` tag manually only to recover a broken release (README "Versioning and releases").
- Pre-1.0 bump rules: breaking change -> minor, everything else -> patch. Reaching 1.0.0 needs an explicit decision from the user.
