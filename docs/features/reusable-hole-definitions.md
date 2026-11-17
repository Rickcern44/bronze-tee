# Reusable hole definitions

## Goal
Make supported course layouts editable as data instead of adding hole-specific code. The first milestone extracts Royal Crest hole 1; holes 2 and 3 retain their existing generation paths through ordered legacy entries in the course resource. Custom doglegs, arbitrary hazard outlines and a visual course editor are future work.

## Design
- A Godot course resource names the course and references ordered hole resources. A hole resource stores scoring, tee and cup positions, green and tee dimensions, fairway and cut parameters, terrain height and green slope, path, water ellipses, and deterministic tree placement.
- The first milestone supports the existing rounded fairway, elliptical green and water, and sinusoidal terrain and path. Store positions in meters (+X right, +Y up, -Z down the hole); yardage is display metadata.
- One active definition drives terrain and gameplay surface queries, shader parameters, tee/cup placement and tree collisions. Godot's adapter and standalone physics library keep the existing `ICourse` contract. Preserve surface precedence and the shader's four-water-ellipse maximum.
- Migrate hole 1 without changing its established appearance or gameplay. Preserve legacy hole 2 and 3 behavior and scoring. Integrate with the latest terrain visuals rather than replacing texture work.
- Include a test-only modified definition to prove that fairway width, green dimensions, tee/cup, height, tree layout and water positions are data-driven.

## Acceptance
- On hole 1, representative heights, surfaces, hazards, tree locations, predictions and scoring match the previous implementation. Reset and progression do not leak stale hole data.
- Changes to the test fixture reach terrain/shader parameters and gameplay/physics, and are cleared when a different hole is loaded.
- Existing C# physics, Godot surface, preview, scoring and three-hole progression checks pass. Document how to duplicate and edit a hole, and supported limits.

## Follow-up: all three holes migrated

Holes 2 and 3 now use the same hole resource and generator as hole 1. Hole 2 defines its lake and tree placement in its resource. Hole 3 defines its original hills, tee fade and green contours through reusable elevation parameters. No legacy layout branches remain. `tests/migrated_holes_check.gd` compares representative terrain heights against the earlier layouts and verifies resource edits.

## Follow-up: simple dogleg support

Hole definitions can now specify one smooth lateral bend with a start, end and offset, and individual trees relative to the green. The terrain shader, fairway/lie queries, path and tree rows use the same bend. The fourth hole uses these settings for an approximate left dogleg with collidable guard trees. More complex multi-point routing remains future work.
