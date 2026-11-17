using System.Numerics;
using BronzeTee.Physics;
using Xunit;

namespace BronzeTee.Physics.Tests;

public sealed class ApproachLandingTests
{
    private static Shot Approach(Club club, float power, ShotType type = ShotType.Normal, SpinMode spin = SpinMode.Normal) =>
        new(new Vector3(0, GolfSimulation.BallRadius, 0), club, power, 0, ShotShape.Straight, type, Lie.Fairway, Vector3.Zero, Spin: spin);

    [Theory]
    [InlineData(Club.FiveIron, ShotType.Normal, .35f)]
    [InlineData(Club.NineIron, ShotType.Normal, .6f)]
    [InlineData(Club.PitchingWedge, ShotType.Normal, .35f)]
    [InlineData(Club.PitchingWedge, ShotType.Normal, 1f)]
    [InlineData(Club.SandWedge, ShotType.Normal, .6f)]
    [InlineData(Club.LobWedge, ShotType.Normal, 1f)]
    [InlineData(Club.PitchingWedge, ShotType.Flop, .6f)]
    [InlineData(Club.LobWedge, ShotType.Flop, 1f)]
    [InlineData(Club.PitchingWedge, ShotType.Punch, .6f)]
    [InlineData(Club.PitchingWedge, ShotType.Stinger, .6f)]
    public void NormalSpinPreservesForwardMotionOnLevelGreen(Club club, ShotType type, float power)
    {
        var simulation = new GolfSimulation(new FlatGreen());
        var ball = simulation.Start(Approach(club, power, type));
        for (var i = 0; i < 2400 && ball.Phase is BallPhase.Airborne or BallPhase.Rolling; i++)
        {
            simulation.Step(ball);
            if (ball.FirstLanding is { } landing)
                Assert.True(ball.Position.Z <= landing.Z + .01f, $"{club} {type} moved behind its landing point");
        }
        Assert.Equal(BallPhase.Stopped, ball.Phase);
        Assert.True(ball.FirstLanding.HasValue);
        Assert.True(ball.Position.Z <= ball.FirstLanding.Value.Z);
    }

    [Fact]
    public void ExplicitBackspinCanCheckAndPullBackButTopspinReleasesForward()
    {
        var sim = new GolfSimulation(new FlatGreen());
        var shot = Approach(Club.PitchingWedge, .6f);
        var normal = sim.Simulate(shot);
        var back = sim.Simulate(shot with { Spin = SpinMode.Backspin });
        var top = sim.Simulate(shot with { Spin = SpinMode.Topspin });
        var normalRelease = normal.FirstLanding!.Value.Z - normal.Position.Z;
        var backRelease = back.FirstLanding!.Value.Z - back.Position.Z;
        var topRelease = top.FirstLanding!.Value.Z - top.Position.Z;
        Assert.True(normalRelease > 0);
        Assert.True(backRelease < -.1f);
        Assert.True(topRelease > normalRelease);
    }

    [Theory]
    [InlineData(Club.FiveIron, 12f, 24f)]
    [InlineData(Club.SixIron, 8f, 20f)]
    public void FullLongIronApproachReleasesOnLevelGreen(Club club, float minYards, float maxYards)
    {
        var ball = new GolfSimulation(new FlatGreen()).Simulate(Approach(club, 1f));
        var release = (ball.FirstLanding!.Value.Z - ball.Position.Z) * GolfSimulation.YardsPerMeter;
        Assert.InRange(release, minYards, maxYards);
    }

    [Fact]
    public void LongIronWindChangesCarryAndNormalSpinStillReleases()
    {
        var sim = new GolfSimulation(new FlatGreen());
        var shot = Approach(Club.FiveIron, 1f);
        var calm = sim.Simulate(shot);
        var head = sim.Simulate(shot with { WindMetersPerSecond = new Vector3(0, 0, 4.47f) });
        var tail = sim.Simulate(shot with { WindMetersPerSecond = new Vector3(0, 0, -4.47f) });
        var cross = sim.Simulate(shot with { WindMetersPerSecond = new Vector3(4.47f, 0, 0) });
        var back = sim.Simulate(shot with { Spin = SpinMode.Backspin });
        var top = sim.Simulate(shot with { Spin = SpinMode.Topspin });
        Assert.InRange((calm.CarryMeters - head.CarryMeters) * GolfSimulation.YardsPerMeter, 3, 15);
        Assert.InRange((tail.CarryMeters - calm.CarryMeters) * GolfSimulation.YardsPerMeter, 3, 15);
        Assert.True(cross.FirstLanding!.Value.X > calm.FirstLanding!.Value.X + 1f);
        var release = calm.FirstLanding!.Value.Z - calm.Position.Z;
        Assert.True(release > 0);
        Assert.True(back.FirstLanding!.Value.Z - back.Position.Z < release);
        Assert.True(top.FirstLanding!.Value.Z - top.Position.Z > release);
    }

    private sealed class FlatGreen : ICourse
    {
        public float HeightAt(float x, float z) => 0;
        public Lie LieAt(Vector3 position) => Lie.Green;
        public bool IntersectsTree(Vector3 from, Vector3 to) => false;
        public Vector2 CupPosition => new(0, -10000);
    }
}
