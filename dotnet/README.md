# C# physics

`BronzeTee.Physics` is a standalone .NET 10 class library with no Godot dependencies. `BronzeTee.Physics.Tests` contains xUnit scenario tests. Run:

```sh
dotnet test dotnet/BronzeTee.Physics.Tests/BronzeTee.Physics.Tests.csproj
```

The library's `GolfSimulation.Step` advances a `BallState` in fixed steps; `Simulate` calls that same method to run a whole shot. `Shot` supplies club, power, a full-swing driver-equivalent `SwingSpeedMph` reference (70–130, default 105), shape, type, lie, aim, bounded swipe offset (`SwipeDegrees`) and wind; `ICourse` supplies ground height, lie, tree intersections and cup location. Units are meters and seconds, with +X right, +Y up and -Z forward.

`BronzeTee.Godot.csproj` references this library, and `scripts/PhysicsBridge.cs` adapts the current Godot course to `ICourse`. Live flight and rolling, landing previews, and full-shot club recommendations all call `GolfSimulation.Step`. GDScript still owns input, UI, course geometry, scoring and penalty handling. Build the Godot adapter with `dotnet build BronzeTee.Godot.csproj`, then run using Godot 4.7.2 .NET.

`GroundPhysics` resolves impact from the incoming velocity, local surface normal, surface, shot type and ball spin. Its tunable arcade parameters give long irons more forward release on green impacts while steep shots check more; non-driver shots landing on the fairway also retain more momentum. These are gameplay calibrations, not a survey of a particular green. Putting resistance remains calibrated separately to Stimp. The Godot recommendation intentionally ignores trees and hazards, while the landing preview and live shot include them.

The xUnit suite includes a set of putting scenarios in `BronzeTee.Physics.Tests/PuttingScenarioTests.cs`, alongside Stimp, spin and cup checks in `GreenPhysicsTests.cs`. It covers short and long putts at 8, 10 and 12 ft Stimp; level, uphill, downhill and cross-slope behavior; stopping times; deliberately steep slopes; cup capture; and consistency between 60 and 120 physics steps per second. The existing tests also cover club distances, wind, lies, trees, water and shot shapes.

To check the generated course geometry and actual game integration as well, run:

```sh
godot --headless --path . --script res://tests/green_scenarios_check.gd
```

This samples the playable green slopes on all four holes, runs short putts at each green speed, and compares a live putt with its forecast. `tests/hole_two_iron_approach_check.gd` exercises a 5-iron green landing with a light tailwind, a 6-iron run-up with a stronger tailwind, a headwind, and live/forecast agreement on the actual second hole. The model allows sustained rolling on an unrealistically steep, unbounded slope when downhill gravity exceeds rolling resistance; ordinary playable greens are kept below that threshold. Physical playtesting is still needed.
