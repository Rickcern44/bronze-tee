using System.Numerics;

namespace BronzeTee.Physics;

/// <summary>One sampled point along a simulated shot.</summary>
public readonly record struct PathSample(Vector3 Position, float Speed, float TimeSeconds);

/// <summary>Result of <see cref="GolfSimulation.Trace"/>: the final ball state plus the sampled path.</summary>
public sealed record ShotTrace(BallState Ball, bool TreeHit, IReadOnlyList<PathSample> Samples);
