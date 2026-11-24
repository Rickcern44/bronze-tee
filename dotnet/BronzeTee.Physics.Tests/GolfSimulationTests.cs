using System.Numerics;
using BronzeTee.Physics;
using Xunit;

namespace BronzeTee.Physics.Tests;

public sealed class GolfSimulationTests
{
    private static readonly Vector3 Tee = new(0, GolfSimulation.BallRadius, 0);
    private static readonly Shot Driver = new(Tee, Club.Driver, 1, 0, ShotShape.Straight, ShotType.Normal, Lie.Tee, Vector3.Zero);
    private readonly GolfSimulation simulation = new(new FlatFairway());

    [Fact]
    public void CalmFullDriverMatchesExistingCalibration()
    {
        var ball = simulation.Simulate(Driver);
        Assert.Equal(BallPhase.Stopped, ball.Phase);
        Assert.InRange(ball.CarryMeters * GolfSimulation.YardsPerMeter, 252f, 257f);
        Assert.InRange(ball.RolloutMeters * GolfSimulation.YardsPerMeter, 24f, 31f);
        Assert.InRange(-ball.Position.Z * GolfSimulation.YardsPerMeter, 277f, 283f);
        Assert.True(ball.FirstLanding.HasValue);
    }

    [Fact]
    public void CrosswindAndHeadwindChangeFlightInExpectedDirections()
    {
        var calm = simulation.Simulate(Driver);
        var cross = simulation.Simulate(Driver with { WindMetersPerSecond = new Vector3(8.94f, 0, 0) });
        var tail = simulation.Simulate(Driver with { WindMetersPerSecond = new Vector3(0, 0, -8.94f) });
        var head = simulation.Simulate(Driver with { WindMetersPerSecond = new Vector3(0, 0, 8.94f) });
        Assert.True(cross.FirstLanding!.Value.X > calm.FirstLanding!.Value.X + 1);
        Assert.True(tail.CarryMeters > calm.CarryMeters);
        Assert.True(head.CarryMeters < calm.CarryMeters);
    }

    [Fact]
    public void SwipeAngleOffsetsLaunchAndCombinesWithShape()
    {
        var left = simulation.Simulate(Driver with { SwipeDegrees = -4 });
        var straight = simulation.Simulate(Driver);
        var right = simulation.Simulate(Driver with { SwipeDegrees = 4 });
        Assert.True(left.FirstLanding!.Value.X < straight.FirstLanding!.Value.X);
        Assert.True(right.FirstLanding!.Value.X > straight.FirstLanding!.Value.X);
        var putt = Driver with { Club = Club.Putter, Power = .5f, SwipeDegrees = 4 };
        Assert.True(GolfSimulation.LaunchVelocity(putt).X > 0);
        Assert.Throws<ArgumentOutOfRangeException>(() => simulation.Start(Driver with { SwipeDegrees = 13 }));
    }

    [Fact]
    public void ShotShapesCurveProgressivelyLeftToRight()
    {
        var results = Enum.GetValues<ShotShape>().Select(shape => simulation.Simulate(Driver with { Shape = shape }).FirstLanding!.Value.X).ToArray();
        Assert.True(results.Zip(results.Skip(1)).All(pair => pair.First < pair.Second));
        Assert.InRange(results[2], -0.01f, 0.01f);
    }

    [Theory]
    [InlineData(Club.Driver, 224f, 242f)]
    [InlineData(Club.ThreeWood, 205f, 218f)]
    [InlineData(Club.FiveWood, 192f, 202f)]
    [InlineData(Club.SevenWood, 180f, 188f)]
    [InlineData(Club.FourHybrid, 175f, 182f)]
    [InlineData(Club.FiveIron, 162f, 168f)]
    [InlineData(Club.SixIron, 152f, 158f)]
    [InlineData(Club.SevenIron, 142f, 150f)]
    [InlineData(Club.EightIron, 131f, 135f)]
    [InlineData(Club.NineIron, 120f, 123f)]
    [InlineData(Club.PitchingWedge, 108f, 111f)]
    [InlineData(Club.SandWedge, 80f, 81f)]
    [InlineData(Club.LobWedge, 68f, 69f)]
    public void ClubsApproximateReferenceChartAt95Mph(Club club, float carryYards, float totalYards)
    {
        var ball = simulation.Simulate(Driver with { Club = club, SwingSpeedMph = 95f });
        Assert.InRange(ball.CarryMeters * GolfSimulation.YardsPerMeter, carryYards - 5, carryYards + 5);
        Assert.InRange(-ball.Position.Z * GolfSimulation.YardsPerMeter, totalYards - 5, totalYards + 5);
    }

    [Theory]
    [InlineData(Club.PitchingWedge)]
    [InlineData(Club.SandWedge)]
    [InlineData(Club.LobWedge)]
    public void PartialWedgesProducePredictableFractionsOfFullCarry(Club club)
    {
        var shot = Driver with { Club = club, Lie = Lie.Fairway };
        var full = simulation.Simulate(shot);
        var previous = 0f;
        foreach (var power in new[] { .25f, .5f, .75f })
        {
            var partial = simulation.Simulate(shot with { Power = power });
            Assert.InRange(partial.CarryMeters / full.CarryMeters, power - .08f, power + .08f);
            Assert.True(partial.CarryMeters > previous);
            previous = partial.CarryMeters;
        }
        Assert.True(full.CarryMeters > previous);
    }

    [Fact]
    public void SwingSpeedAndPowerChangeDistanceButDoNotAffectPutting()
    {
        var slow = simulation.Simulate(Driver with { Club = Club.FiveIron, SwingSpeedMph = 85 });
        var fast = simulation.Simulate(Driver with { Club = Club.FiveIron, SwingSpeedMph = 105 });
        var partial = simulation.Simulate(Driver with { Club = Club.FiveIron, SwingSpeedMph = 105, Power = .6f });
        Assert.True(slow.CarryMeters < fast.CarryMeters && partial.CarryMeters < slow.CarryMeters);
        var putt = Driver with { Club = Club.Putter, Power = .5f };
        Assert.Equal(GolfSimulation.LaunchVelocity(putt with { SwingSpeedMph = 70 }), GolfSimulation.LaunchVelocity(putt with { SwingSpeedMph = 130 }));
    }

    [Fact]
    public void ShotTypesProduceDistinctApexes()
    {
        var normal = simulation.Simulate(Driver with { Club = Club.FiveIron });
        var flop = simulation.Simulate(Driver with { Club = Club.FiveIron, Type = ShotType.Flop });
        var punch = simulation.Simulate(Driver with { Club = Club.FiveIron, Type = ShotType.Punch });
        var stinger = simulation.Simulate(Driver with { Club = Club.FiveIron, Type = ShotType.Stinger });
        Assert.True(flop.PeakHeightMeters > normal.PeakHeightMeters);
        Assert.True(normal.PeakHeightMeters > punch.PeakHeightMeters);
        Assert.True(punch.PeakHeightMeters > stinger.PeakHeightMeters);
        Assert.True(flop.CarryMeters < normal.CarryMeters);
    }

    [Fact]
    public void LieReducesLaunchSpeedAndPutterIgnoresShotMode()
    {
        var fairway = GolfSimulation.LaunchVelocity(Driver);
        var firstCut = GolfSimulation.LaunchVelocity(Driver with { Lie = Lie.FirstCut });
        var rough = GolfSimulation.LaunchVelocity(Driver with { Lie = Lie.Rough });
        var bunker = GolfSimulation.LaunchVelocity(Driver with { Lie = Lie.Bunker });
        Assert.True(fairway.Length() > firstCut.Length() && firstCut.Length() > rough.Length() && rough.Length() > bunker.Length());
        var putt = Driver with { Club = Club.Putter, Power = .5f };
        Assert.Equal(GolfSimulation.LaunchVelocity(putt), GolfSimulation.LaunchVelocity(putt with { Type = ShotType.Flop, Shape = ShotShape.Hook }));
    }

    [Fact]
    public void PreviewAndStepByStepUseIdenticalState()
    {
        var shot = Driver with { Shape = ShotShape.Draw, WindMetersPerSecond = new Vector3(3, 0, 2) };
        var predicted = simulation.Simulate(shot);
        var actual = simulation.Start(shot);
        while (actual.Phase is BallPhase.Airborne or BallPhase.Rolling) simulation.Step(actual);
        Assert.Equal(predicted.Position, actual.Position);
        Assert.Equal(predicted.FirstLanding, actual.FirstLanding);
        Assert.Equal(predicted.RolloutMeters, actual.RolloutMeters);
    }

    [Fact]
    public void WaterAndCupAreReportedAsTerminalStates()
    {
        var water = new GolfSimulation(new FixtureCourse(Lie.Water, new Vector2(0, -10000)));
        Assert.Equal(BallPhase.Water, water.Simulate(Driver).Phase);
        var green = new GolfSimulation(new FixtureCourse(Lie.Green, new Vector2(0, -0.8f)));
        var putt = Driver with { Club = Club.Putter, Power = .36f, Lie = Lie.Green };
        Assert.Equal(BallPhase.Holed, green.Simulate(putt).Phase);
    }

    [Fact]
    public void TreeImpactReducesSpeedAndShotEventuallyStops()
    {
        var obstacles = new GolfSimulation(new TreeCourse());
        var ball = obstacles.Start(Driver);
        var hit = false;
        for (var i = 0; i < 2400 && ball.Phase is BallPhase.Airborne or BallPhase.Rolling; i++)
        {
            var before = ball.Velocity.Length();
            var events = obstacles.Step(ball);
            if (events.TreeHit)
            {
                hit = true;
                Assert.True(ball.Velocity.Length() < before * 0.4f);
            }
        }
        Assert.True(hit);
        Assert.Equal(BallPhase.Stopped, ball.Phase);
    }

    [Fact]
    public void DownhillRollsFartherThanUphillOnTheSameGreen()
    {
        var green = new GolfSimulation(new SlopedGreen());
        var start = new Vector3(0, GolfSimulation.BallRadius, 0);
        var uphill = green.Simulate(Driver with { Start = start, Club = Club.Putter, Power = .6f, Lie = Lie.Green });
        var downhill = green.Simulate(Driver with { Start = start, Club = Club.Putter, Power = .6f, AimDegrees = 180f, Lie = Lie.Green });
        Assert.True(downhill.RolloutMeters > uphill.RolloutMeters);
    }

    [Fact]
    public void InvalidPowerAndTimeStepAreRejected()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => simulation.Start(Driver with { Power = 1.1f }));
        Assert.Throws<ArgumentOutOfRangeException>(() => simulation.Start(Driver with { SwingSpeedMph = 140f }));
        Assert.Throws<ArgumentOutOfRangeException>(() => simulation.Step(simulation.Start(Driver), 0));
    }

    [Theory]
    [InlineData(Club.SandWedge, ShotType.Punch, .35f)]
    [InlineData(Club.SandWedge, ShotType.Normal, .35f)]
    [InlineData(Club.Driver, ShotType.Stinger, .6f)]
    public void BallNeverEndsUnderneathAShortSteepBunkerLip(Club club, ShotType type, float power)
    {
        var course = new BunkerCourse();
        var sim = new GolfSimulation(course);
        var start = new Vector3(0, course.HeightAt(0, 0) + GolfSimulation.BallRadius, 0);
        var ball = sim.Start(new Shot(start, club, power, 0, ShotShape.Straight, type, Lie.Bunker, Vector3.Zero));
        for (var i = 0; i < 1200 && ball.Phase is BallPhase.Airborne or BallPhase.Rolling; i++)
        {
            sim.Step(ball);
            Assert.True(ball.Position.Y >= course.HeightAt(ball.Position.X, ball.Position.Z) + GolfSimulation.BallRadius - 0.001f,
                $"step {i}: ball at {ball.Position} is below ground {course.HeightAt(ball.Position.X, ball.Position.Z)}");
        }
    }

    // A 0.6 m deep bunker floor (z 0..-2.5) with a 0.5 m wide lip rising to the surrounding turf.
    private sealed class BunkerCourse : ICourse
    {
        public float HeightAt(float x, float z) => -0.6f * Math.Clamp((z + 3f) / 0.5f, 0f, 1f);
        public Lie LieAt(Vector3 position) => position.Z > -3f ? Lie.Bunker : Lie.Fairway;
        public bool IntersectsTree(Vector3 from, Vector3 to) => false;
        public Vector2 CupPosition => new(0, -10000);
    }

    private sealed class TreeCourse : ICourse
    {
        public float HeightAt(float x, float z) => 0;
        public Lie LieAt(Vector3 position) => Lie.Fairway;
        public Vector2 CupPosition => new(0, -10000);
        public bool IntersectsTree(Vector3 from, Vector3 to) => from.Z > -20 && to.Z <= -20;
    }

    private sealed class SlopedGreen : ICourse
    {
        public float HeightAt(float x, float z) => -0.02f * z;
        public Lie LieAt(Vector3 position) => Lie.Green;
        public Vector2 CupPosition => new(0, -10000);
        public bool IntersectsTree(Vector3 from, Vector3 to) => false;
    }

    private sealed record FixtureCourse(Lie Surface, Vector2 CupPosition) : ICourse
    {
        public float HeightAt(float x, float z) => 0;
        public Lie LieAt(Vector3 position) => Surface;
        public bool IntersectsTree(Vector3 from, Vector3 to) => false;
    }
}
