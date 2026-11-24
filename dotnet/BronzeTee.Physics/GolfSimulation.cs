using System.Numerics;

namespace BronzeTee.Physics;

/// <summary>Fixed-step arcade golf simulation. Contains no Godot dependencies.</summary>
public sealed class GolfSimulation(ICourse course, float greenStimpFeet = 10f)
{
	public const float BallRadius = SpinPhysics.BallRadiusMeters;
	public const float DefaultStepSeconds = 1f / 60f;
	public const float YardsPerMeter = 1.0936133f;
	public static float GreenRollingResistance => GreenPhysics.RollingResistance(10f);
	public const float PutterPowerExponent = 1.5f;
	private const float Gravity = 9.81f;
	private const float AirDrag = 0.0022f;
	public const float CupRadius = 0.10795f / 2f;
	public const float CupDepth = 0.1016f;
	private const float CupMaxCenterSpeed = 1.63f;

	public static float LiePower(Lie lie) => lie switch
	{
		Lie.Rough => 0.82f,
		Lie.FirstCut => 0.92f,
		Lie.Bunker => 0.62f,
		_ => 1f
	};

	// The backswing meter is a player control, not measured clubhead speed.
	// Partial wedges use a distance-oriented response for controllable approaches.
	public static float PowerSpeedFraction(Shot shot) => shot.Club switch
	{
		Club.Putter => MathF.Pow(shot.Power, PutterPowerExponent),
		Club.PitchingWedge or Club.SandWedge or Club.LobWedge => MathF.Pow(shot.Power, .55f),
		_ => shot.Power
	};

	public static Vector3 LaunchVelocity(Shot shot)
	{
		if (!float.IsFinite(shot.Power) || shot.Power is < 0 or > 1)
			throw new ArgumentOutOfRangeException(nameof(shot), "Power must be between 0 and 1.");
		var (speed, loft) = shot.Club switch
		{
			Club.Driver => (69.60f, 22.0f),
			Club.ThreeWood => (67.64f, 21.0f),
			Club.FiveWood => (62.52f, 23.0f),
			Club.SevenWood => (58.13f, 25.0f),
			Club.FourHybrid => (56.38f, 26.0f),
			Club.FiveIron => (53.04f, 27.0f),
			Club.SixIron => (49.80f, 29.0f),
			Club.SevenIron => (46.81f, 31.0f),
			Club.EightIron => (43.60f, 34.0f),
			Club.NineIron => (40.67f, 37.0f),
			Club.PitchingWedge => (37.82f, 40.0f),
			Club.SandWedge => (31.69f, 46.0f),
			Club.LobWedge => (29.45f, 52.0f),
			Club.Putter => (8.00f, 0.0f),
			_ => throw new ArgumentOutOfRangeException(nameof(shot))
		};
		var putting = shot.Club == Club.Putter;
		if (!float.IsFinite(shot.SwingSpeedMph) || shot.SwingSpeedMph is < 70f or > 130f)
			throw new ArgumentOutOfRangeException(nameof(shot), "Full-swing speed setting must be 70–130 mph.");
		var typeSpeed = 1f;
		if (!putting)
			(loft, typeSpeed) = shot.Type switch
			{
				ShotType.Flop => (MathF.Max(loft + 18f, 58f), 0.52f),
				ShotType.Punch => (MathF.Max(6f, loft * 0.55f), 0.82f),
				ShotType.Stinger => (MathF.Max(4f, loft * 0.34f), 0.90f),
				_ => (loft, 1f)
			};
		if (!float.IsFinite(shot.SwipeDegrees) || MathF.Abs(shot.SwipeDegrees) > 12f)
			throw new ArgumentOutOfRangeException(nameof(shot), "Swipe angle must be between -12 and 12 degrees.");
		var heading = Degrees(shot.AimDegrees + shot.SwipeDegrees);
		loft = Degrees(loft);
		var power = PowerSpeedFraction(shot);
		speed *= power * LiePower(shot.Lie) * typeSpeed * (putting ? 1f : shot.SwingSpeedMph / 105f);
		return new Vector3(MathF.Sin(heading) * MathF.Cos(loft), MathF.Sin(loft), -MathF.Cos(heading) * MathF.Cos(loft)) * speed;
	}

	public BallState Start(Shot shot)
	{
		var velocity = LaunchVelocity(shot);
		return new BallState
		{
			Shot = shot,
			Position = shot.Start,
			Velocity = velocity,
			AngularVelocity = SpinPhysics.LaunchSpin(shot, velocity),
			Phase = shot.Club == Club.Putter ? BallPhase.Rolling : BallPhase.Airborne,
			HasLanded = shot.Club == Club.Putter
		};
	}

	public StepEvents Step(BallState ball, float dt = DefaultStepSeconds)
	{
		if (!float.IsFinite(dt) || dt <= 0 || dt > 0.1f)
			throw new ArgumentOutOfRangeException(nameof(dt));
		if (ball.Phase is BallPhase.Stopped or BallPhase.Holed or BallPhase.Water) return default;
		ball.TreeCooldown = MathF.Max(0, ball.TreeCooldown - dt);
		var previous = ball.Position;
		var treeHit = false;
		var firstLanding = false;
		if (ball.Phase == BallPhase.Airborne)
		{
			var relative = ball.Velocity - ball.Shot.WindMetersPerSecond;
			var acceleration = -Vector3.UnitY * Gravity - relative * relative.Length() * AirDrag;
			acceleration += SpinPhysics.AirAcceleration(ball.AngularVelocity, relative);
			ball.AngularVelocity = SpinPhysics.DecayInAir(ball.AngularVelocity, dt);
			ball.Velocity += acceleration * dt;
			ball.Position += ball.Velocity * dt;
			if (ball.TreeCooldown <= 0 && course.IntersectsTree(previous, ball.Position))
			{
				treeHit = true;
				ball.TreeCooldown = 0.5f;
				ball.Position = previous;
				ball.Velocity *= 0.25f;
				ball.Velocity = new Vector3(ball.Velocity.X, MathF.Min(ball.Velocity.Y, -1.5f), ball.Velocity.Z);
			}
			if (ball.HasLanded) ball.RolloutMeters += HorizontalDistance(previous, ball.Position);
			ball.PeakHeightMeters = MathF.Max(ball.PeakHeightMeters, ball.Position.Y - ball.Shot.Start.Y);
			var ground = course.HeightAt(ball.Position.X, ball.Position.Z) + BallRadius;
			// A rising ball that meets a short steep face (a bunker lip) from above-ground
			// at the previous step also collides; otherwise it would end up underground.
			var hitsFace = ball.Velocity.Y >= 0 && previous.Y > course.HeightAt(previous.X, previous.Z) + BallRadius + 1e-4f;
			if (ball.Position.Y <= ground && (ball.Velocity.Y < 0 || hitsFace))
			{
				ball.Position = new Vector3(ball.Position.X, ground, ball.Position.Z);
				if (course.LieAt(ball.Position) == Lie.Water) ball.Phase = BallPhase.Water;
				else
				{
					if (!ball.HasLanded)
					{
						ball.HasLanded = true;
						firstLanding = true;
						ball.FirstLanding = ball.Position;
						ball.CarryMeters = HorizontalDistance(ball.Shot.Start, ball.Position);
					}
					var impact = GroundPhysics.Bounce(ball.Velocity, GroundPhysics.Normal(course, ball.Position), course.LieAt(ball.Position), ball.Shot.Type, ball.Shot.Club, ball.AngularVelocity);
					ball.Velocity = impact.Velocity;
					ball.AngularVelocity = impact.AngularVelocity;
					if (impact.IsRolling) ball.Phase = BallPhase.Rolling;
				}
			}
		}
		else
		{
			var lie = course.LieAt(ball.Position);
			var resistance = lie switch { Lie.Green => GreenRollingResistance, Lie.Bunker => 16f, Lie.Rough => 10f, Lie.FirstCut => 8.75f, _ => 7.5f };
			var x = ball.Position.X;
			var z = ball.Position.Z;
			var slope = new Vector2((course.HeightAt(x + .2f, z) - course.HeightAt(x - .2f, z)) / .4f,
									(course.HeightAt(x, z + .2f) - course.HeightAt(x, z - .2f)) / .4f);
			Vector2 horizontal;
			if (lie == Lie.Green)
			{
				(ball.Velocity, ball.AngularVelocity) = GreenPhysics.Step(ball.Velocity, ball.AngularVelocity, slope, greenStimpFeet, dt);
				horizontal = new Vector2(ball.Velocity.X, ball.Velocity.Z);
			}
			else
			{
				horizontal = new Vector2(ball.Velocity.X, ball.Velocity.Z) - slope * Gravity * dt;
				var speed = horizontal.Length();
				horizontal = speed <= resistance * dt ? Vector2.Zero : horizontal * ((speed - resistance * dt) / speed);
				ball.Velocity = new Vector3(horizontal.X, 0, horizontal.Y);
			}
			ball.Position += ball.Velocity * dt;
			if (course.IntersectsTree(previous, ball.Position))
			{
				treeHit = true;
				ball.Position = previous;
				ball.Velocity = Vector3.Zero;
				horizontal = Vector2.Zero;
			}
			ball.Position = new Vector3(ball.Position.X, course.HeightAt(ball.Position.X, ball.Position.Z) + BallRadius, ball.Position.Z);
			if (lie != Lie.Green) ball.AngularVelocity = SpinPhysics.RollingSpin(ball.AngularVelocity, GroundPhysics.Normal(course, ball.Position), ball.Velocity, dt);
			ball.RolloutMeters += HorizontalDistance(previous, ball.Position);
			if (course.LieAt(ball.Position) == Lie.Water) ball.Phase = BallPhase.Water;
			else if (CrossesCup(previous, ball.Position, course.CupPosition, horizontal, slope))
			{
				ball.Position = new Vector3(course.CupPosition.X, course.HeightAt(course.CupPosition.X, course.CupPosition.Y) - CupDepth + BallRadius, course.CupPosition.Y);
				ball.Velocity = Vector3.Zero;
				ball.AngularVelocity = Vector3.Zero;
				ball.Phase = BallPhase.Holed;
			}
			else if (horizontal.Length() < 0.05f && (lie != Lie.Green || GreenPhysics.CanSettle(slope, greenStimpFeet)))
			{
				ball.Velocity = Vector3.Zero;
				ball.AngularVelocity = Vector3.Zero;
				ball.Phase = BallPhase.Stopped;
			}
		}
		return new StepEvents(firstLanding, treeHit);
	}

	/// <summary>Runs the same step function used for live shots until the ball stops.</summary>
	public BallState Simulate(Shot shot, int maxSteps = 2400)
	{
		if (maxSteps <= 0) throw new ArgumentOutOfRangeException(nameof(maxSteps));
		var ball = Start(shot);
		for (var i = 0; i < maxSteps && ball.Phase is BallPhase.Airborne or BallPhase.Rolling; i++) Step(ball);
		if (ball.Phase is BallPhase.Airborne or BallPhase.Rolling)
			throw new InvalidOperationException("Shot did not finish within the simulation limit.");
		return ball;
	}

	/// <summary>
	/// Runs the same step function as <see cref="Simulate"/> but never throws when the step limit is reached,
	/// and records a sample (position, speed, time) every <paramref name="sampleEverySteps"/> steps.
	/// The first sample is the start; the last is the final position. Samples are evenly spaced in time,
	/// so they bunch together as the ball slows.
	/// </summary>
	public ShotTrace Trace(Shot shot, bool stopAtFirstLanding = false, int maxSteps = 2400, int sampleEverySteps = 6, float stepSeconds = DefaultStepSeconds)
	{
		if (maxSteps <= 0) throw new ArgumentOutOfRangeException(nameof(maxSteps));
		if (sampleEverySteps <= 0) throw new ArgumentOutOfRangeException(nameof(sampleEverySteps));
		var ball = Start(shot);
		var samples = new List<PathSample> { new(ball.Position, ball.Velocity.Length(), 0f) };
		var treeHit = false;
		var steps = 0;
		for (; steps < maxSteps && ball.Phase is BallPhase.Airborne or BallPhase.Rolling;)
		{
			var events = Step(ball, stepSeconds);
			steps++;
			treeHit |= events.TreeHit;
			if (steps % sampleEverySteps == 0) samples.Add(new PathSample(ball.Position, ball.Velocity.Length(), steps * stepSeconds));
			if (stopAtFirstLanding && events.FirstLanding) break;
		}
		if (steps % sampleEverySteps != 0) samples.Add(new PathSample(ball.Position, ball.Velocity.Length(), steps * stepSeconds));
		return new ShotTrace(ball, treeHit, samples);
	}

	private static float Degrees(float degrees) => degrees * MathF.PI / 180f;
	private static float HorizontalDistance(Vector3 a, Vector3 b) => Vector2.Distance(new(a.X, a.Z), new(b.X, b.Z));
	private static bool CrossesCup(Vector3 from, Vector3 to, Vector2 cup, Vector2 velocity, Vector2 slope)
	{
		var start = new Vector2(from.X, from.Z);
		var segment = new Vector2(to.X - from.X, to.Z - from.Z);
		var t = Math.Clamp(Vector2.Dot(cup - start, segment) / MathF.Max(segment.LengthSquared(), 0.000001f), 0f, 1f);
		var offset = Vector2.Distance(start + segment * t, cup);
		if (offset >= CupRadius) return false;
		// Penner's fit to Holmes' measured capture boundary, adjusted for slope.
		var speed = velocity.Length();
		var uphill = speed > .0001f ? Vector2.Dot(slope, velocity / speed) : 0f;
		var maxSpeed = CupMaxCenterSpeed * (1f - offset * offset / (CupRadius * CupRadius));
		maxSpeed /= MathF.Sqrt(Math.Clamp(1f - uphill, .5f, 1.5f));
		return speed <= maxSpeed;
	}
}
