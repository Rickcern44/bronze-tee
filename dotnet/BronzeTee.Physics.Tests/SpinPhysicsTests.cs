using System.Numerics;
using BronzeTee.Physics;
using Xunit;

namespace BronzeTee.Physics.Tests;

public sealed class SpinPhysicsTests
{
    private static readonly Shot Iron = new(new Vector3(0, GolfSimulation.BallRadius, 0), Club.SevenIron, 1, 0, ShotShape.Straight, ShotType.Normal, Lie.Fairway, Vector3.Zero);

    [Fact]
    public void BackspinCreatesLiftAndDecaysInFlight()
    {
        var velocity = GolfSimulation.LaunchVelocity(Iron);
        var back = SpinPhysics.LaunchSpin(Iron with { Spin = SpinMode.Backspin }, velocity);
        var top = SpinPhysics.LaunchSpin(Iron with { Spin = SpinMode.Topspin }, velocity);
        Assert.True(SpinPhysics.AirAcceleration(back, velocity).Y > 0);
        Assert.True(SpinPhysics.AirAcceleration(top, velocity).Y < 0);
        Assert.True(SpinPhysics.DecayInAir(back, 1).Length() < back.Length());
    }

    [Fact]
    public void SpinChangesSurfaceImpactAndIsTransferredToBallMotion()
    {
        var incoming = new Vector3(0, -10, -20);
        var backspin = new Vector3(500, 0, 0);
        var topspin = -backspin;
        var back = GroundPhysics.Bounce(incoming, Vector3.UnitY, Lie.Green, ShotType.Normal, Club.SevenIron, backspin);
        var top = GroundPhysics.Bounce(incoming, Vector3.UnitY, Lie.Green, ShotType.Normal, Club.SevenIron, topspin);
        Assert.True(back.Velocity.Z > top.Velocity.Z);
        Assert.NotEqual(backspin, back.AngularVelocity);
        Assert.NotEqual(topspin, top.AngularVelocity);
    }

    [Fact]
    public void PutterIgnoresSpinAndShapeSelections()
    {
        var putt = Iron with { Club = Club.Putter, Power = .5f };
        var velocity = GolfSimulation.LaunchVelocity(putt);
        Assert.Equal(SpinPhysics.LaunchSpin(putt, velocity), SpinPhysics.LaunchSpin(putt with { Spin = SpinMode.Backspin, Shape = ShotShape.Hook }, velocity));
        Assert.True(Vector3.Cross(SpinPhysics.LaunchSpin(putt, velocity), -Vector3.UnitY * SpinPhysics.BallRadiusMeters).Z > 0);
    }
}
