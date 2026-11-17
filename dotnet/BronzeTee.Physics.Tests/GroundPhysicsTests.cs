using System.Numerics;
using BronzeTee.Physics;
using Xunit;

namespace BronzeTee.Physics.Tests;

public sealed class GroundPhysicsTests
{
    private static readonly Vector3 Incoming = new(24, -12, 0);

    [Fact]
    public void SurfaceChangesBounceAndRetainedSpeed()
    {
        var fairway = GroundPhysics.Bounce(Incoming, Vector3.UnitY, Lie.Fairway, ShotType.Normal, Club.Driver);
        var firstCut = GroundPhysics.Bounce(Incoming, Vector3.UnitY, Lie.FirstCut, ShotType.Normal, Club.Driver);
        var rough = GroundPhysics.Bounce(Incoming, Vector3.UnitY, Lie.Rough, ShotType.Normal, Club.Driver);
        var sand = GroundPhysics.Bounce(Incoming, Vector3.UnitY, Lie.Bunker, ShotType.Normal, Club.Driver);
        Assert.True(fairway.Velocity.Y > firstCut.Velocity.Y && firstCut.Velocity.Y > rough.Velocity.Y && rough.Velocity.Y > sand.Velocity.Y);
        Assert.True(fairway.Velocity.X > firstCut.Velocity.X && firstCut.Velocity.X > rough.Velocity.X && rough.Velocity.X > sand.Velocity.X);
        Assert.False(fairway.IsRolling);
    }

    [Fact]
    public void ShallowLandingKeepsMoreForwardSpeedThanSteepLanding()
    {
        var shallow = GroundPhysics.Bounce(new Vector3(24, -4, 0), Vector3.UnitY, Lie.Fairway, ShotType.Normal, Club.Driver);
        var steep = GroundPhysics.Bounce(new Vector3(24, -20, 0), Vector3.UnitY, Lie.Fairway, ShotType.Normal, Club.Driver);
        Assert.True(shallow.Velocity.X > steep.Velocity.X);
        Assert.True(steep.Velocity.Y > shallow.Velocity.Y);
    }

    [Fact]
    public void SurfaceNormalChangesBounceDirection()
    {
        var flat = GroundPhysics.Bounce(Incoming, Vector3.UnitY, Lie.Fairway, ShotType.Normal, Club.Driver);
        var slope = Vector3.Normalize(new Vector3(-.15f, 1, 0));
        var angled = GroundPhysics.Bounce(Incoming, slope, Lie.Fairway, ShotType.Normal, Club.Driver);
        Assert.NotEqual(flat.Velocity, angled.Velocity);
        Assert.True(Vector3.Dot(angled.Velocity, slope) > 0);
    }

    [Theory]
    [InlineData(Club.Driver, ShotType.Normal, Lie.Fairway)]
    [InlineData(Club.FiveIron, ShotType.Normal, Lie.Fairway)]
    [InlineData(Club.PitchingWedge, ShotType.Flop, Lie.Green)]
    public void FlightProducesVisibleFirstBounce(Club club, ShotType type, Lie surface)
    {
        var course = new SurfaceCourse(surface);
        var simulation = new GolfSimulation(course);
        var shot = new Shot(new Vector3(0, GolfSimulation.BallRadius, 0), club, 1f, 0,
            ShotShape.Straight, type, Lie.Fairway, Vector3.Zero);
        var ball = simulation.Start(shot);
        var landed = false;
        for (var tick = 0; tick < 2400; tick++)
        {
            if (!simulation.Step(ball).FirstLanding) continue;
            landed = true;
            var expectedApex = ball.Velocity.Y * ball.Velocity.Y / (2f * 9.81f);
            Assert.InRange(expectedApex, .05f, 2f);
            Assert.Equal(BallPhase.Airborne, ball.Phase);
            break;
        }
        Assert.True(landed);
    }

    private sealed class SurfaceCourse(Lie surface) : ICourse
    {
        public float HeightAt(float x, float z) => 0;
        public Lie LieAt(Vector3 position) => surface;
        public bool IntersectsTree(Vector3 from, Vector3 to) => false;
        public Vector2 CupPosition => new(0, -10000);
    }

    [Theory]
    [InlineData(.25f, 1.8f, 2.2f)]
    [InlineData(.50f, 15.0f, 17.0f)]
    [InlineData(.75f, 51.0f, 57.0f)]
    public void PutterHasUsablePowerRangeOnFlatGreen(float power, float minimumFeet, float maximumFeet)
    {
        var simulation = new GolfSimulation(new SurfaceCourse(Lie.Green));
        var shot = new Shot(new Vector3(0, GolfSimulation.BallRadius, 0), Club.Putter, power, 0,
            ShotShape.Straight, ShotType.Normal, Lie.Green, Vector3.Zero);
        var ball = simulation.Simulate(shot);
        Assert.InRange(-ball.Position.Z * 3.28084f, minimumFeet, maximumFeet);
    }

    [Fact]
    public void FlopChecksMoreAndTinyImpactsBecomeRolling()
    {
        var normal = GroundPhysics.Bounce(Incoming, Vector3.UnitY, Lie.Green, ShotType.Normal, Club.PitchingWedge);
        var flop = GroundPhysics.Bounce(Incoming, Vector3.UnitY, Lie.Green, ShotType.Flop, Club.PitchingWedge);
        Assert.True(flop.Velocity.Y < normal.Velocity.Y && flop.Velocity.X < normal.Velocity.X);
        var slow = GroundPhysics.Bounce(new Vector3(1, -.5f, 0), Vector3.UnitY, Lie.Fairway, ShotType.Normal, Club.Driver);
        Assert.True(slow.IsRolling);
        Assert.Equal(0, slow.Velocity.Y);
    }
}
