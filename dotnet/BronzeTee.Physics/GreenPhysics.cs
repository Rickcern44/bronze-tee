using System.Numerics;

namespace BronzeTee.Physics;

/// <summary>Approximate sliding and rolling motion for a spherical ball on a green.</summary>
public static class GreenPhysics
{
    public const float StimpLaunchSpeed = 1.83f;
    public const float FeetToMeters = .3048f;
    public const float Gravity = 9.81f;
    public const float SlidingFriction = .25f;
    public const float SlopeFactor = 5f / 7f;
    // Default putter launch includes some forward roll, then slides into full roll.
    public const float PutterInitialRollFraction = .35f;
    public const float PutterRollSpeedFraction = 1f - (1f - PutterInitialRollFraction) * 2f / 7f;

    public static float RollingResistance(float stimpFeet)
    {
        if (!float.IsFinite(stimpFeet) || stimpFeet < 4 || stimpFeet > 16)
            throw new ArgumentOutOfRangeException(nameof(stimpFeet));
        return StimpLaunchSpeed * StimpLaunchSpeed / (2f * stimpFeet * FeetToMeters);
    }

    /// <summary>Whether rolling resistance can hold the ball against this slope.</summary>
    public static bool CanSettle(Vector2 slope, float stimpFeet) =>
        slope.Length() * Gravity * SlopeFactor <= RollingResistance(stimpFeet);

    public static (Vector3 Velocity, Vector3 Spin) Step(Vector3 velocity, Vector3 spin, Vector2 slope, float stimpFeet, float dt)
    {
        var normal = Vector3.UnitY;
        var radius = SpinPhysics.BallRadiusMeters;
        var contact = -normal * radius;
        var slip = velocity + Vector3.Cross(spin, contact);
        slip.Y = 0;
        var slipSpeed = slip.Length();
        if (slipSpeed > .00001f)
        {
            // Unit mass, solid-sphere inertia (2/5 m r²); cap at pure roll.
            var impulse = -slip / slipSpeed * MathF.Min(slipSpeed / 3.5f, SlidingFriction * Gravity * dt);
            velocity += impulse;
            spin += Vector3.Cross(contact, impulse) / (.4f * radius * radius);
        }
        // Gravity of a rolling solid sphere; rolling resistance is calibrated to Stimp.
        var beforeRolling = velocity;
        var horizontal = new Vector2(velocity.X, velocity.Z) - slope * (Gravity * SlopeFactor * dt);
        var speed = horizontal.Length();
        var resistance = RollingResistance(stimpFeet) * dt;
        horizontal = speed <= resistance ? Vector2.Zero : horizontal * ((speed - resistance) / speed);
        velocity = new Vector3(horizontal.X, 0, horizontal.Y);
        // Rolling resistance and slope also change angular speed without erasing slip.
        spin += Vector3.Cross(normal, velocity - beforeRolling) / radius;
        return (velocity, spin);
    }
}
