using System.Numerics;

namespace BronzeTee.Physics;

// Coordinates are meters: Y is up, X right, and -Z forward from the tee.
public enum Lie { Tee, Fairway, Rough, Bunker, Green, Water, FirstCut }
public enum Club { Driver, ThreeWood, FiveWood, SevenWood, FourHybrid, FiveIron, SixIron, SevenIron, EightIron, NineIron, PitchingWedge, SandWedge, LobWedge, Putter }
public enum ShotShape { Hook, Draw, Straight, Fade, Slice }
public enum ShotType { Normal, Flop, Punch, Stinger }
public enum SpinMode { Normal, Backspin, Topspin }
public enum BallPhase { Airborne, Rolling, Stopped, Holed, Water }

public readonly record struct Shot(
    Vector3 Start, Club Club, float Power, float AimDegrees,
    ShotShape Shape, ShotType Type, Lie Lie, Vector3 WindMetersPerSecond,
    float SwingSpeedMph = 105f, float SwipeDegrees = 0f, SpinMode Spin = SpinMode.Normal);

public readonly record struct StepEvents(bool FirstLanding = false, bool TreeHit = false);

public sealed class BallState
{
    public required Shot Shot { get; init; }
    public Vector3 Position { get; internal set; }
    public Vector3 Velocity { get; internal set; }
    public Vector3 AngularVelocity { get; internal set; }
    public BallPhase Phase { get; internal set; }
    public bool HasLanded { get; internal set; }
    public Vector3? FirstLanding { get; internal set; }
    public float CarryMeters { get; internal set; }
    public float RolloutMeters { get; internal set; }
    public float PeakHeightMeters { get; internal set; }
    internal float TreeCooldown { get; set; }
}

/// <summary>Geometry and surfaces are supplied by the game or a test fixture.</summary>
public interface ICourse
{
    float HeightAt(float x, float z);
    Lie LieAt(Vector3 position);
    bool IntersectsTree(Vector3 from, Vector3 to);
    Vector2 CupPosition { get; }
}

public sealed class FlatFairway : ICourse
{
    public float HeightAt(float x, float z) => 0f;
    public Lie LieAt(Vector3 position) => Lie.Fairway;
    public bool IntersectsTree(Vector3 from, Vector3 to) => false;
    // A distant cup leaves calibration shots unaffected.
    public Vector2 CupPosition => new(0, -10000);
}
