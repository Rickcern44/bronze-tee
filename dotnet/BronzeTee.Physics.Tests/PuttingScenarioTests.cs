using System.Numerics;
using BronzeTee.Physics;
using Xunit;

namespace BronzeTee.Physics.Tests;

/// <summary>Deterministic, inspectable putting scenarios, independent of Godot.</summary>
public sealed class PuttingScenarioTests
{
    private static Shot Putt(float power, float aim = 0) => new(
        new Vector3(0, GolfSimulation.BallRadius, 0), Club.Putter, power, aim,
        ShotShape.Straight, ShotType.Normal, Lie.Green, Vector3.Zero);

    private static (BallState Ball, int Steps) Play(GolfSimulation sim, Shot shot, float dt = 1f / 60f, int maxSteps = 3600)
    {
        var ball = sim.Start(shot);
        var steps = 0;
        while (ball.Phase is BallPhase.Rolling or BallPhase.Airborne && steps < maxSteps)
        {
            sim.Step(ball, dt);
            steps++;
        }
        return (ball, steps);
    }

    [Theory]
    [InlineData(8f, .2f)] [InlineData(8f, .5f)] [InlineData(8f, .8f)]
    [InlineData(10f, .2f)] [InlineData(10f, .5f)] [InlineData(10f, .8f)]
    [InlineData(12f, .2f)] [InlineData(12f, .5f)] [InlineData(12f, .8f)]
    public void FlatGreenPuttsComeToRest(float stimp, float power)
    {
        var (ball, steps) = Play(new GolfSimulation(new PlaneGreen(), stimp), Putt(power));
        Assert.Equal(BallPhase.Stopped, ball.Phase);
        Assert.InRange(steps, 1, 2400);
        Assert.True(float.IsFinite(ball.RolloutMeters) && ball.RolloutMeters > 0);
        Assert.Equal(Vector3.Zero, ball.Velocity);
        Assert.Equal(Vector3.Zero, ball.AngularVelocity);
    }

    [Fact]
    public void FasterGreenRollsFartherForSamePutt()
    {
        var distances = new[] { 8f, 10f, 12f }.Select(stimp =>
            Play(new GolfSimulation(new PlaneGreen(), stimp), Putt(.5f)).Ball.RolloutMeters).ToArray();
        Assert.True(distances[0] < distances[1] && distances[1] < distances[2]);
    }

    [Theory]
    [InlineData(8f)] [InlineData(10f)] [InlineData(12f)]
    public void NormalSlopesSettleAndDownhillRollsFarther(float stimp)
    {
        var sim = new GolfSimulation(new PlaneGreen(zSlope: .03f), stimp);
        var downhill = Play(sim, Putt(.5f));
        var uphill = Play(sim, Putt(.5f, 180));
        Assert.Equal(BallPhase.Stopped, downhill.Ball.Phase);
        Assert.Equal(BallPhase.Stopped, uphill.Ball.Phase);
        Assert.True(downhill.Ball.RolloutMeters > uphill.Ball.RolloutMeters);
        Assert.InRange(downhill.Steps, 1, 2400);
    }

    [Fact]
    public void CrossSlopeBreaksTowardDownhillSide()
    {
        var (ball, _) = Play(new GolfSimulation(new PlaneGreen(xSlope: .025f)), Putt(.5f));
        Assert.Equal(BallPhase.Stopped, ball.Phase);
        Assert.True(ball.Position.X < -.1f);
    }

    [Fact]
    public void SteepSlopeKeepsMovingAndCanReverseAnUphillPutt()
    {
        var sim = new GolfSimulation(new PlaneGreen(zSlope: -.1f), 10);
        Assert.False(GreenPhysics.CanSettle(new Vector2(0, -.1f), 10));
        var ball = sim.Start(Putt(.15f));
        var reversed = false;
        for (var i = 0; i < 600; i++)
        {
            sim.Step(ball);
            Assert.Equal(BallPhase.Rolling, ball.Phase);
            if (ball.Velocity.Z > .1f) { reversed = true; break; }
        }
        Assert.True(reversed, "The putt should slow, reverse and roll downhill on a sustained steep slope.");
    }

    [Fact]
    public void OrdinaryPuttHasSimilarResultAtTwoStepRates()
    {
        var sim = new GolfSimulation(new PlaneGreen(xSlope: .015f));
        var slow = Play(sim, Putt(.5f), 1f / 60f);
        var fast = Play(sim, Putt(.5f), 1f / 120f);
        Assert.Equal(BallPhase.Stopped, slow.Ball.Phase);
        Assert.Equal(BallPhase.Stopped, fast.Ball.Phase);
        Assert.InRange(Vector3.Distance(slow.Ball.Position, fast.Ball.Position), 0, .12f);
    }

    private sealed class PlaneGreen(float xSlope = 0, float zSlope = 0) : ICourse
    {
        public float HeightAt(float x, float z) => x * xSlope + z * zSlope;
        public Lie LieAt(Vector3 position) => Lie.Green;
        public bool IntersectsTree(Vector3 from, Vector3 to) => false;
        public Vector2 CupPosition => new(0, -10000);
    }
}
