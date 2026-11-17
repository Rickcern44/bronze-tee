using System.Numerics;
using BronzeTee.Physics;
using Xunit;

namespace BronzeTee.Physics.Tests;

public sealed class GreenPhysicsTests
{
    [Theory]
    [InlineData(8f)] [InlineData(10f)] [InlineData(12f)]
    public void StimpRollMatchesSelectedGreenSpeed(float stimp)
    {
        var velocity = new Vector3(0, 0, -GreenPhysics.StimpLaunchSpeed);
        var spin = Vector3.Cross(Vector3.UnitY, velocity) / SpinPhysics.BallRadiusMeters;
        var distance = 0f;
        for (var i = 0; i < 4000 && velocity.Length() > .001f; i++)
        {
            (velocity, spin) = GreenPhysics.Step(velocity, spin, Vector2.Zero, stimp, 1f / 240f);
            distance += velocity.Length() / 240f;
        }
        Assert.InRange(distance / GreenPhysics.FeetToMeters, stimp - .1f, stimp + .1f);
    }

    [Fact]
    public void SlidingTransfersSpeedToForwardRotation()
    {
        var velocity = new Vector3(0, 0, -2);
        var initialSpin = Vector3.Zero;
        var (after, spin) = GreenPhysics.Step(velocity, initialSpin, Vector2.Zero, 10, 1f / 60);
        Assert.True(after.Length() < velocity.Length());
        Assert.True(spin.X < 0);
        var initialSlip = velocity.Length();
        var afterSlip = (after + Vector3.Cross(spin, -Vector3.UnitY * SpinPhysics.BallRadiusMeters)).Length();
        Assert.True(afterSlip < initialSlip);
    }

    [Fact]
    public void RegulationCupCapturesCenteredControlledPuttButRejectsMissAndFastPutt()
    {
        var simulation = new GolfSimulation(new GreenCourse());
        Shot Make(float offset, float power) => new(new Vector3(offset, GolfSimulation.BallRadius, 0), Club.Putter, power, 0,
            ShotShape.Straight, ShotType.Normal, Lie.Green, Vector3.Zero);
        Assert.Equal(BallPhase.Holed, simulation.Simulate(Make(0, .36f)).Phase);
        Assert.NotEqual(BallPhase.Holed, simulation.Simulate(Make(.04f, .36f)).Phase);
        Assert.NotEqual(BallPhase.Holed, simulation.Simulate(Make(0, .8f)).Phase);
        Assert.InRange(GolfSimulation.CupRadius * 2, .1079f, .1080f);
    }

    private sealed class GreenCourse : ICourse
    {
        public float HeightAt(float x, float z) => 0;
        public Lie LieAt(Vector3 position) => Lie.Green;
        public bool IntersectsTree(Vector3 from, Vector3 to) => false;
        public Vector2 CupPosition => new(0, -.8f);
    }
}
