using System;
using System.Collections.Generic;
using System.Linq;
using Godot;
using BronzeTee.Physics;
using GDictionary = Godot.Collections.Dictionary;
using NVector2 = System.Numerics.Vector2;
using NVector3 = System.Numerics.Vector3;

// Narrow bridge: Godot owns the world and presentation; the library owns motion.
public partial class PhysicsBridge : Node
{
    private GolfSimulation? _simulation;
    private BallState? _ball;
    private float _greenStimpFeet = 10f;

    public void SetGreenSpeed(double stimpFeet) { GreenPhysics.RollingResistance((float)stimpFeet); _greenStimpFeet = (float)stimpFeet; }

    public void StartShot(GDictionary data)
    {
        _simulation = new GolfSimulation(new GodotCourse(GetParent(), false), _greenStimpFeet);
        _ball = _simulation.Start(ReadShot(data));
    }

    public Vector3 InitialVelocity(GDictionary data) => ToGodot(GolfSimulation.LaunchVelocity(ReadShot(data)));

    public GDictionary CurrentShot() => _ball is null ? new GDictionary() : Snapshot(_ball, false, false);

    public GDictionary StepShot(double delta)
    {
        if (_simulation is null || _ball is null) return new GDictionary();
        var events = _simulation.Step(_ball, (float)delta);
        return Snapshot(_ball, events.TreeHit, events.FirstLanding);
    }

    public void CancelShot() { _simulation = null; _ball = null; }

    // Both prediction modes use the same step function as live play.
    public GDictionary Forecast(GDictionary data, bool stopAtFirstLanding, bool ignoreHazards)
    {
        var simulation = new GolfSimulation(new GodotCourse(GetParent(), ignoreHazards), _greenStimpFeet);
        var ball = simulation.Start(ReadShot(data));
        var treeHit = false;
        for (var i = 0; i < 2400 && ball.Phase is BallPhase.Airborne or BallPhase.Rolling; i++)
        {
            var events = simulation.Step(ball, 1f / Engine.PhysicsTicksPerSecond);
            treeHit |= events.TreeHit;
            if (stopAtFirstLanding && events.FirstLanding) break;
        }
        return ForecastResult(ball, treeHit);
    }

    // Same result as Forecast plus the sampled path: "path" (positions) and "path_speed" (m/s), evenly spaced in time.
    public GDictionary ForecastWithPath(GDictionary data, bool stopAtFirstLanding, bool ignoreHazards, int sampleEverySteps)
    {
        var simulation = new GolfSimulation(new GodotCourse(GetParent(), ignoreHazards), _greenStimpFeet);
        var trace = simulation.Trace(ReadShot(data), stopAtFirstLanding, 2400, Math.Max(1, sampleEverySteps), 1f / Engine.PhysicsTicksPerSecond);
        var result = ForecastResult(trace.Ball, trace.TreeHit);
        result["path"] = PackVectors(trace.Samples);
        result["path_speed"] = Packed(trace.Samples);
        return result;
    }

    private GDictionary ForecastResult(BallState ball, bool treeHit)
    {
        var result = Snapshot(ball, treeHit, ball.FirstLanding.HasValue);
        result["surface"] = ball.Phase == BallPhase.Water ? "Water" :
            ball.Phase == BallPhase.Holed ? "Cup" :
            GetParent().Call("_lie", ToGodot(ball.Position)).AsString();
        return result;
    }

    private static Vector3[] PackVectors(IReadOnlyList<PathSample> samples) => samples.Select(sample => ToGodot(sample.Position)).ToArray();
    private static float[] Packed(IReadOnlyList<PathSample> samples) => samples.Select(sample => sample.Speed).ToArray();

    private static Shot ReadShot(GDictionary d) => new(
        ToNumerics(d["start"].AsVector3()), (Club)d["club"].AsInt32(), d["power"].AsSingle(),
        d["aim"].AsSingle(), (ShotShape)d["shape"].AsInt32(), (ShotType)d["type"].AsInt32(),
        (Lie)d["lie"].AsInt32(), ToNumerics(d["wind"].AsVector3()),
        d["swing_speed"].AsSingle(), d["swipe"].AsSingle(),
        d.ContainsKey("spin") ? (SpinMode)d["spin"].AsInt32() : SpinMode.Normal);

    private static GDictionary Snapshot(BallState ball, bool treeHit, bool firstLanding) => new()
    {
        ["position"] = ToGodot(ball.Position), ["velocity"] = ToGodot(ball.Velocity),
        ["phase"] = (int)ball.Phase, ["has_landed"] = ball.HasLanded,
        ["carry"] = ball.CarryMeters, ["rollout"] = ball.RolloutMeters,
        ["peak"] = ball.PeakHeightMeters, ["tree_hit"] = treeHit,
        ["first_landing"] = firstLanding,
        ["backspin_rpm"] = NVector3.Dot(ball.AngularVelocity, new NVector3(MathF.Cos(ball.Shot.AimDegrees * MathF.PI / 180f), 0, MathF.Sin(ball.Shot.AimDegrees * MathF.PI / 180f))) / SpinPhysics.RadiansPerSecondPerRpm,
        ["sidespin_rpm"] = -ball.AngularVelocity.Y / SpinPhysics.RadiansPerSecondPerRpm
    };

    private static NVector3 ToNumerics(Vector3 v) => new(v.X, v.Y, v.Z);
    private static Vector3 ToGodot(NVector3 v) => new(v.X, v.Y, v.Z);

    private sealed class GodotCourse(Node game, bool ignoreHazards) : ICourse
    {
        public float HeightAt(float x, float z) => game.Call("_ground_height", x, z).AsSingle();
        public Lie LieAt(NVector3 position)
        {
            var pos = ToGodot(position);
            if (!ignoreHazards && game.Call("_in_water", pos).AsBool()) return Lie.Water;
            var name = game.Call("_lie", pos).AsString();
            return System.Enum.TryParse<Lie>(name, out var lie) ? lie : Lie.Rough;
        }
        public bool IntersectsTree(NVector3 from, NVector3 to) =>
            !ignoreHazards && game.Call("_tree_hit", ToGodot(from), ToGodot(to)).AsBool();
        public NVector2 CupPosition
        {
            get
            {
                if (ignoreHazards) return new NVector2(0, -10000);
                var cup = game.Get("CUP").AsVector3();
                return new NVector2(cup.X, cup.Z);
            }
        }
    }
}
