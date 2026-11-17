using System.Numerics;

namespace BronzeTee.Physics;

/// <summary>Angular velocity is in radians/second. Launch RPM values are arcade tuning targets.</summary>
public static class SpinPhysics
{
    public const float BallRadiusMeters = 0.02135f; // Regulation-sized ball radius.
    public const float RadiansPerSecondPerRpm = 2f * MathF.PI / 60f;
    private const float MagnusCoefficient = .00001f;
    private const float AirSpinDecayPerSecond = .08f;

    public static Vector3 LaunchSpin(Shot shot, Vector3 velocity)
    {
        if (shot.Club == Club.Putter)
            return Vector3.Cross(Vector3.UnitY, velocity) / BallRadiusMeters * GreenPhysics.PutterInitialRollFraction;
        var rpm = shot.Club switch
        {
            Club.Driver => 2500f, Club.ThreeWood => 3100f, Club.FiveWood => 3600f,
            Club.SevenWood => 4000f, Club.FourHybrid => 4300f, Club.FiveIron => 4800f,
            Club.SixIron => 5300f, Club.SevenIron => 5800f, Club.EightIron => 6300f,
            Club.NineIron => 6800f, Club.PitchingWedge => 7400f, Club.SandWedge => 8000f,
            Club.LobWedge => 8500f, _ => 0f
        };
        var typeFactor = shot.Type switch { ShotType.Flop => 1.10f, ShotType.Punch => .72f, ShotType.Stinger => .55f, _ => 1f };
        // Normal shots keep modest launch spin but do not normally pull backward
        // on a level green. The lofted flop needs almost no default backspin to
        // settle without reversing; the explicit backspin mode remains strong.
        var modeFactor = shot.Spin switch { SpinMode.Backspin => 1.35f, SpinMode.Topspin => -.5f, _ => shot.Type == ShotType.Flop ? 0f : .35f };
        var spinScale = GolfSimulation.PowerSpeedFraction(shot) * (shot.SwingSpeedMph / 105f) * GolfSimulation.LiePower(shot.Lie);
        var backspin = rpm * typeFactor * modeFactor * spinScale;
        // Positive side RPM curves to the right of the aim direction.
        var side = shot.Shape switch { ShotShape.Hook => -1100f, ShotShape.Draw => -500f, ShotShape.Fade => 500f, ShotShape.Slice => 1100f, _ => 0f };
        var heading = shot.AimDegrees * MathF.PI / 180f;
        var right = new Vector3(MathF.Cos(heading), 0, MathF.Sin(heading));
        return (right * backspin - Vector3.UnitY * side * spinScale) * RadiansPerSecondPerRpm;
    }

    public static Vector3 AirAcceleration(Vector3 angularVelocity, Vector3 relativeAirVelocity) =>
        Vector3.Cross(new Vector3(angularVelocity.X, 0, angularVelocity.Z), relativeAirVelocity) * MagnusCoefficient
        + Vector3.Cross(new Vector3(0, angularVelocity.Y, 0), relativeAirVelocity) * (MagnusCoefficient * 4f);

    public static Vector3 DecayInAir(Vector3 angularVelocity, float delta) =>
        angularVelocity * MathF.Exp(-AirSpinDecayPerSecond * delta);

    public static Vector3 RollingSpin(Vector3 angularVelocity, Vector3 normal, Vector3 velocity, float delta)
    {
        var desired = Vector3.Cross(normal, velocity) / BallRadiusMeters;
        return Vector3.Lerp(angularVelocity, desired, 1f - MathF.Exp(-8f * delta));
    }
}
