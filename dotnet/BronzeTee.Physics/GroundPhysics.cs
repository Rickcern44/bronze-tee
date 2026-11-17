using System.Numerics;

namespace BronzeTee.Physics;

/// <summary>Arcade impact response using the local surface normal and material.</summary>
public static class GroundPhysics
{
    public readonly record struct Impact(Vector3 Velocity, Vector3 AngularVelocity, bool IsRolling);

    public static Vector3 Normal(ICourse course, Vector3 position)
    {
        const float sample = .2f;
        var dx = (course.HeightAt(position.X + sample, position.Z) - course.HeightAt(position.X - sample, position.Z)) / (2 * sample);
        var dz = (course.HeightAt(position.X, position.Z + sample) - course.HeightAt(position.X, position.Z - sample)) / (2 * sample);
        return Vector3.Normalize(new Vector3(-dx, 1, -dz));
    }

    public static Impact Bounce(Vector3 incoming, Vector3 normal, Lie surface, ShotType type, Club club, Vector3 angularVelocity = default)
    {
        normal = Vector3.Normalize(normal);
        var perpendicular = Vector3.Dot(incoming, normal);
        if (perpendicular >= 0) return new(incoming, angularVelocity, false);
        var tangent = incoming - normal * perpendicular;
        var incidence = Math.Clamp(-perpendicular / MathF.Max(tangent.Length(), .01f), 0, 1);
        var (restitution, retention) = surface switch
        {
            Lie.Green => (.22f, .70f),
            Lie.Rough => (.12f, .42f),
            Lie.FirstCut => (.16f, .64f),
            Lie.Bunker => (.06f, .30f),
            _ => (.20f, .82f)
        };
        // Greens should preserve more forward momentum than the old arcade
        // landing penalty; spin/contact friction still checks the shot below.
        retention = Math.Clamp(retention * (1f - .70f * incidence), .12f, .90f);
        if (surface == Lie.Green)
        {
            // Steep descents still check; shallower iron approaches release.
            var steepness = Math.Clamp((incidence - .65f) / .30f, 0f, 1f);
            retention *= 1f - .36f * steepness * steepness * (3f - 2f * steepness);
        }
        // Baseline surface grip preserves the established arcade club tuning.
        if (club != Club.Driver && surface != Lie.Green)
            retention *= surface is Lie.Fairway or Lie.Tee ? .78f : .72f;
        switch (type)
        {
            case ShotType.Flop: restitution *= .65f; retention *= .80f; break;
            case ShotType.Punch: retention = MathF.Min(.90f, retention * 1.15f); break;
            case ShotType.Stinger: retention = MathF.Min(.90f, retention * 1.25f); break;
        }
        var outgoingNormalSpeed = -perpendicular * restitution;
        var outgoing = tangent * retention + normal * outgoingNormalSpeed;
        // Tangential slip at contact transfers momentum between translation and spin.
        // The sphere inertia factor is 2/5; friction is capped by the normal impulse.
        var radius = SpinPhysics.BallRadiusMeters;
        var contact = -normal * radius;
        var contactSpeed = outgoing + Vector3.Cross(angularVelocity, contact);
        var slip = contactSpeed - normal * Vector3.Dot(contactSpeed, normal);
        var slipSpeed = slip.Length();
        var friction = surface switch { Lie.Green => .055f, Lie.Rough => .10f, Lie.FirstCut => .06f, Lie.Bunker => .14f, _ => .025f };
        if (slipSpeed > .0001f)
        {
            var impulseSize = MathF.Min(slipSpeed / 3.5f, friction * (-perpendicular) * (1f + restitution));
            var impulse = -slip / slipSpeed * impulseSize;
            outgoing += impulse;
            angularVelocity += Vector3.Cross(contact, impulse) / (.4f * radius * radius);
        }
        // Avoid endless tiny hops without flattening the visually meaningful first bounce.
        return outgoingNormalSpeed < .6f ? new(new Vector3(outgoing.X, 0, outgoing.Z), angularVelocity, true) : new(outgoing, angularVelocity, false);
    }
}
