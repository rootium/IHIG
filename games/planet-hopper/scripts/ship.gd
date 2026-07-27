class_name Ship
extends Node2D
## The player.
##
## Two states that matter: ORBIT, where you ride a circle around a planet and
## top up your tanks, and FLY, where gravity owns you and thrust costs fuel.
## Oxygen drains in both, which is what keeps you moving.

signal died(reason: String)
signal captured(planet: Planet)

enum State { ORBIT, FLY, DEAD }

var state: State = State.ORBIT
var vel: Vector2 = Vector2.ZERO

var host: Planet = null
var orbit_r: float = 0.0
var orbit_a: float = 0.0
var orbit_w: float = 0.0  ## Signed angular velocity; sign is the travel direction.

var fuel: float = PH.FUEL_MAX
var oxygen: float = PH.OXY_MAX

var thrusting: bool = false
var aim_point: Vector2 = Vector2.ZERO
var has_aim: bool = false
var skin: Dictionary = {}

var _heading: float = 0.0
var _flame: float = 0.0
var _lockout: float = 0.0  ## Blocks re-capture right after a launch.


func _ready() -> void:
	z_index = 10
	skin = Skins.ship(SaveData.ship_id)


func reset(p_skin: Dictionary) -> void:
	skin = p_skin
	state = State.ORBIT
	vel = Vector2.ZERO
	host = null
	fuel = PH.FUEL_MAX
	oxygen = PH.OXY_MAX
	thrusting = false
	has_aim = false
	_flame = 0.0
	_lockout = 0.0


## Locks the ship into a circular orbit. `dir` is +1 or -1 for the sweep.
func attach(p: Planet, r: float, a: float, dir: float) -> void:
	host = p
	state = State.ORBIT
	orbit_r = r
	orbit_a = a
	orbit_w = dir * sqrt(PH.GRAV * p.mass / r) / r
	_sync_orbit()


## Breaks orbit along the tangent. Free — fuel is only for steering in flight,
## so an empty tank strands you but never softlocks you.
func launch() -> void:
	if state != State.ORBIT:
		return
	state = State.FLY
	vel = _tangent() * absf(orbit_w) * orbit_r * PH.LAUNCH_MULT
	_heading = vel.angle()
	host = null
	_lockout = PH.RECAPTURE_LOCKOUT


func die(reason: String) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	thrusting = false
	died.emit(reason)


func speed() -> float:
	return vel.length()


## Advances the orbit without consuming anything. Used behind the menus so the
## title screen shows a living system rather than a frozen one.
func idle(delta: float) -> void:
	if state != State.ORBIT or not is_instance_valid(host):
		return
	orbit_a += orbit_w * delta
	_sync_orbit()
	rotation = _heading
	queue_redraw()


func step(delta: float, world: World) -> void:
	if state == State.DEAD:
		return
	_lockout = maxf(0.0, _lockout - delta)
	oxygen -= PH.OXY_DRAIN * delta
	if oxygen <= 0.0:
		oxygen = 0.0
		die("Out of oxygen")
		return

	if state == State.ORBIT:
		_step_orbit(delta)
	else:
		_step_fly(delta, world)

	rotation = _heading
	queue_redraw()


# --- orbit -------------------------------------------------------------------

func _step_orbit(delta: float) -> void:
	if not is_instance_valid(host):
		# The planet was culled out from under us; fall back to free flight.
		state = State.FLY
		return
	orbit_a += orbit_w * delta
	_sync_orbit()
	_replenish(delta)
	_flame = maxf(0.0, _flame - delta * 5.0)


func _replenish(delta: float) -> void:
	if not host.has_supply():
		return
	if host.kind == Planet.Kind.OXYGEN:
		var take: float = minf(PH.OXY_REFILL * delta, minf(host.reserve, PH.OXY_MAX - oxygen))
		oxygen += take
		host.reserve -= take
	elif host.kind == Planet.Kind.FUEL:
		var take: float = minf(PH.FUEL_REFILL * delta, minf(host.reserve, PH.FUEL_MAX - fuel))
		fuel += take
		host.reserve -= take


func _tangent() -> Vector2:
	return Vector2(-sin(orbit_a), cos(orbit_a)) * signf(orbit_w)


func _sync_orbit() -> void:
	position = host.position + Vector2(cos(orbit_a), sin(orbit_a)) * orbit_r
	var t := _tangent()
	_heading = t.angle()
	vel = t * absf(orbit_w) * orbit_r


# --- free flight -------------------------------------------------------------

func _step_fly(delta: float, world: World) -> void:
	var acc := Vector2.ZERO
	for b in world.gravity_bodies():
		var d: Vector2 = b.position - position
		var dist := d.length()
		if dist < 1.0 or dist > b.influence:
			continue
		acc += (d / dist) * minf(PH.GRAV * b.mass / (dist * dist), PH.MAX_GRAV_ACCEL)

	# Nose swings toward your finger; without input it settles onto the
	# direction of travel so the ship always reads as "pointing where I'm going".
	if has_aim:
		_heading = rotate_toward(_heading, (aim_point - position).angle(), PH.TURN_RATE * delta)
	elif vel.length_squared() > 100.0:
		_heading = rotate_toward(_heading, vel.angle(), PH.TURN_RATE * 0.5 * delta)

	if thrusting and fuel > 0.0:
		acc += Vector2.from_angle(_heading) * PH.THRUST
		fuel = maxf(0.0, fuel - PH.FUEL_BURN * delta)
		_flame = 1.0
	else:
		_flame = maxf(0.0, _flame - delta * 5.0)

	vel = (vel + acc * delta).limit_length(PH.MAX_SPEED)
	position += vel * delta

	_check_planets(world)


func _check_planets(world: World) -> void:
	for p in world.planets:
		var dist := position.distance_to(p.position)
		if dist > p.capture_radius():
			continue
		# Slow enough and the planet catches you; too fast and you either sail
		# through the window or hit the ground. Capture keeps you at the height
		# you arrived at, so a shallow approach parks you in a wide orbit.
		if _lockout <= 0.0 and speed() <= p.capture_speed():
			var r := clampf(dist, p.radius + PH.ORBIT_GAP * 0.8, p.capture_radius())
			var offset := position - p.position
			var dir := signf(offset.cross(vel))
			attach(p, r, offset.angle(), 1.0 if dir == 0.0 else dir)
			captured.emit(p)
			return
		if dist < p.radius + PH.SHIP_RADIUS:
			die("Hit the surface too hard")
			return


# --- drawing -----------------------------------------------------------------

func _draw() -> void:
	if state == State.DEAD:
		return
	var hull: Color = skin.get("hull", PH.C_SHIP)
	var trim: Color = skin.get("trim", Color(0.36, 0.55, 0.95))
	var flame_col: Color = skin.get("flame", PH.C_FLAME)

	if _flame > 0.01:
		var l := 15.0 + 11.0 * _flame * (0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.05))
		draw_colored_polygon(
			PackedVector2Array([Vector2(-8, -5), Vector2(-8, 5), Vector2(-8 - l, 0)]),
			Color(flame_col.r, flame_col.g, flame_col.b, 0.9 * _flame))
		draw_colored_polygon(
			PackedVector2Array([Vector2(-8, -2.4), Vector2(-8, 2.4), Vector2(-8 - l * 0.55, 0)]),
			Color(1, 1, 1, 0.75 * _flame))

	var pts := _hull_points(int(skin.get("shape", 0)))
	draw_colored_polygon(pts, hull)
	draw_polyline(pts + PackedVector2Array([pts[0]]), trim, 1.6, true)
	draw_circle(Vector2(4.5, 0), 3.0, trim)


static func _hull_points(shape: int) -> PackedVector2Array:
	match shape:
		1:  # broad wings
			return PackedVector2Array([
				Vector2(16, 0), Vector2(-4, -6), Vector2(-11, -13), Vector2(-8, -4),
				Vector2(-9, 0), Vector2(-8, 4), Vector2(-11, 13), Vector2(-4, 6),
			])
		2:  # long-hauler with tail fins
			return PackedVector2Array([
				Vector2(19, 0), Vector2(2, -5), Vector2(-9, -6), Vector2(-13, -11),
				Vector2(-9, -2), Vector2(-9, 2), Vector2(-13, 11), Vector2(-9, 6), Vector2(2, 5),
			])
		_:  # classic dart
			return PackedVector2Array([
				Vector2(16, 0), Vector2(-10, -9), Vector2(-6, 0), Vector2(-10, 9),
			])
