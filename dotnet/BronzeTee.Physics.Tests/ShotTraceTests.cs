using System.Numerics;
using BronzeTee.Physics;
using Xunit;

namespace BronzeTee.Physics.Tests;

public sealed class ShotTraceTests
{
    private static readonly Vector3 Tee = new(0, GolfSimulation.BallRadius, 0);
    private static readonly Shot Driver = new(Tee, Club.Driver, 1, 0, ShotShape.Straight, ShotType.Normal, Lie.Tee, Vector3.Zero);
    private static readonly Shot Putt = new(Tee, Club.Putter, .5f, 0, ShotShape.Straight, ShotType.Normal, Lie.Green, Vector3.Zero);
    private readonly GolfSimulation simulation = new(new FlatFairway());

    [Fact]
    public void TraceEndsWhereSimulateEnds()
    {
        var trace = simulation.Trace(Driver);
        var ball = simulation.Simulate(Driver);
        Assert.Equal(ball.Position, trace.Ball.Position);
        Assert.Equal(ball.Phase, trace.Ball.Phase);
        Assert.Equal(ball.CarryMeters, trace.Ball.CarryMeters);
        Assert.False(trace.TreeHit);
    }

    [Fact]
    public void FirstSampleIsStartAndLastIsFinalPosition()
    {
        var trace = simulation.Trace(Driver);
        Assert.Equal(Tee, trace.Samples[0].Position);
        Assert.Equal(0f, trace.Samples[0].TimeSeconds);
        Assert.Equal(trace.Ball.Position, trace.Samples[^1].Position);
        Assert.Equal(0f, trace.Samples[^1].Speed);
    }

    [Fact]
    public void SamplesAreEvenlySpacedInTime()
    {
        var trace = simulation.Trace(Driver, sampleEverySteps: 6);
        var gaps = trace.Samples.Zip(trace.Samples.Skip(1), (a, b) => b.TimeSeconds - a.TimeSeconds).ToArray();
        Assert.All(gaps.Take(gaps.Length - 1), gap => Assert.Equal(0.1f, gap, 3));
        Assert.InRange(gaps[^1], 0.0001f, 0.1001f);
    }

    [Fact]
    public void PuttSamplesBunchUpAsTheBallSlows()
    {
        var trace = new GolfSimulation(new FlatGreen()).Trace(Putt);
        var spacing = trace.Samples.Zip(trace.Samples.Skip(1), (a, b) => Vector3.Distance(a.Position, b.Position)).ToArray();
        Assert.True(trace.Samples.Count > 5);
        Assert.True(spacing[0] > spacing[^2]);
        Assert.True(trace.Samples[0].Speed > trace.Samples[^2].Speed);
    }

    [Fact]
    public void StopAtFirstLandingEndsAtTheLandingPoint()
    {
        var trace = simulation.Trace(Driver, stopAtFirstLanding: true);
        Assert.True(trace.Ball.FirstLanding.HasValue);
        Assert.Equal(trace.Ball.FirstLanding!.Value, trace.Samples[^1].Position);
        Assert.True(trace.Samples[^1].Position.Y <= GolfSimulation.BallRadius + 0.001f);
    }

    [Fact]
    public void StepLimitIsReportedWithoutThrowing()
    {
        var trace = simulation.Trace(Driver, maxSteps: 30);
        Assert.Equal(BallPhase.Airborne, trace.Ball.Phase);
        Assert.Equal(0.5f, trace.Samples[^1].TimeSeconds, 3);
    }

    [Fact]
    public void RejectsBadArguments()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => simulation.Trace(Driver, maxSteps: 0));
        Assert.Throws<ArgumentOutOfRangeException>(() => simulation.Trace(Driver, sampleEverySteps: 0));
    }

    private sealed class FlatGreen : ICourse
    {
        public float HeightAt(float x, float z) => 0f;
        public Lie LieAt(Vector3 position) => Lie.Green;
        public bool IntersectsTree(Vector3 from, Vector3 to) => false;
        public Vector2 CupPosition => new(0, -10000);
    }
}
