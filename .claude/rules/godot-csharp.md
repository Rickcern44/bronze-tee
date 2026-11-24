---
paths:
  - "**/*.cs"
---

# C# conventions for Bronze Tee

- `BronzeTee.Godot.csproj` uses `Godot.NET.Sdk/4.7.2` and `net10.0` with nullable enabled. Match the SDK version to the Godot version.
- Build with `dotnet build BronzeTee.Godot.csproj -warnaserror`; warnings fail the check gate.
- Keep reusable physics code in `dotnet/BronzeTee.Physics` and cover it in `dotnet/BronzeTee.Physics.Tests`.
- `scripts/PhysicsBridge.cs` is the Godot adapter; keep engine-specific code there rather than in the physics library.
- `godot --headless --check-only --script` does not verify C#. The authoritative C# check is `dotnet build`, followed by `dotnet test`.
- Do not commit `bin/`, `obj/`, `.godot/`, or generated files unless the change is intentional.
- Every C# change must pass `./tools/check.sh` before it is handed to review.
