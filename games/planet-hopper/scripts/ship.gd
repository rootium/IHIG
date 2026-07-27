class_name Ship
extends Node2D
## The player.
##
## Two states that matter: ORBIT, where you ride a circle around a planet and
## top up your tanks, and FLY, where gravity owns you and thrust costs fuel.
## Oxygen drains in both, which is what keeps you climbing.
##
## The planet you launch from stops pulling on you until something else catches
## you (`_launch_host`). Without that, a hop at anything below escape velocity
## curves straight back to where it started, which reads as the game fighting
## you. With it, a launch is a clean arc you can aim.

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
var _lockout: float = 0.0
var _launch_host: Planet = null
var _trail: Array[Vector2] = []


func _ready() -> void:
	z_index = 10
	skin = Skins.ship(SaveData.ship_id)


func reset(p_skin: Dictionary) -> void:
	skin = p_skin
	state = State.ORBIT
	vel = Vector2.ZERO
	host = null
	_launch_host = null
	fuel = PH.FUEL_MAX
	oxygen = PH.OXY_MAX
	thrusting = false
	has_aim = false
	_flame = 0.0
	_lockout = 0.0
	_trail.clear()


func attach(p: Planet, r: float, a: float, dir: float) -> void:
	host = p
	_launch_host = null
	state = State.ORBIT
	orbit_r = r
	orbit_a = a
	orbit_w = dir * sqrt(PH.GRAV * p.mass / r) / r
	_sync_orbit()


## Breaks orbit along the tangent. Free — fuel only pays for steering in flight,
## so an empty tank strands you but never softlocks you.
func launch() -> void:
	if state != State.ORBIT or not is_instance_valid(host):
		return
	state = State.FLY
	vel = _tangent() * absf(orbit_w) * orbit_r * PH.LAUNCH_MULT
	_heading = vel.angle()
	_launch_host = host
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


## Advances the orbit without consuming anything, for menu backdrops.
func idle(delta: float) -> void:
	if state != State.ORBIT or not is_instance_valid(host):
		return
	orbit_a += orbit_w * delta
	_sync_orbit()
	queue_redraw()


## The planet we launched from lives in a chunk that gets culled once we climb
## far enough past it, which on a long run leaves `_launch_host` dangling. A
## freed planet can neither pull nor capture, so dropping the reference is both
## safe and correct — and without it, gravity_at() is handed a freed object.
##
## is_instance_valid() is the whole test on purpose. Guarding it with a
## `_launch_host != null` precondition looks natural and is wrong: in GDScript a
## freed object compares equal to null, so that check skips exactly the case
## this exists to catch. is_instance_valid(null) is already false.
func _drop_stale_refs() -> void:
	if not is_instance_valid(_launch_host):
		_launch_host = null


func step(delta: float, world: World) -> void:
	if state == State.DEAD:
		return
	_drop_stale_refs()
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

	_push_trail()
	queue_redraw()


## Where a coast from here ends up, and which planet catches it. Called every
## frame by Main to draw the path and highlight the target; while orbiting it
## previews the launch you would get by tapping right now.
func predict(world: World) -> Dictionary:
	_drop_stale_refs()  # callers may reach here before step() on a given frame
	var p := position
	var v := vel
	var exclude := _launch_host
	if state == State.ORBIT:
		if not is_instance_valid(host):
			return {"points": PackedVector2Array(), "target": null}
		v = _tangent() * absf(orbit_w) * orbit_r * PH.LAUNCH_MULT
		exclude = host

	var pts := PackedVector2Array([p])
	var target: Planet = null
	for i in PH.PREVIEW_STEPS:
		v += world.gravity_at(p, exclude) * PH.PREVIEW_DT
		p += v * PH.PREVIEW_DT
		pts.append(p)
		var c := world.capture_candidate(p, exclude)
		if c != null:
			target = c
			break
	return {"points": pts, "target": target}


# --- orbit -------------------------------------------------------------------

func _step_orbit(delta: float) -> void:
	if not is_instance_valid(host):
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
	var acc := world.gravity_at(position, _launch_host)

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
	if _lockout > 0.0:
		return
	var p := world.capture_candidate(position, _launch_host)
	if p == null:
		return
	if speed() <= PH.CAPTURE_SPEED:
		var dist := position.distance_to(p.position)
		var r := clampf(dist, p.radius + PH.ORBIT_GAP * 0.75, p.capture_radius())
		var offset := position - p.position
		var dir := signf(offset.cross(vel))
		attach(p, r, offset.angle(), 1.0 if dir == 0.0 else dir)
		captured.emit(p)
	elif position.distance_to(p.position) < p.radius + PH.SHIP_RADIUS:
		die("Hit the surface too hard")


func _push_trail() -> void:
	_trail.push_front(position)
	if _trail.size() > PH.TRAIL_LENGTH:
		_trail.resize(PH.TRAIL_LENGTH)


# --- drawing -----------------------------------------------------------------
# The node's rotation is deliberately left at zero and the hull is rotated in
# code instead, so the trail — which is stored in world space — can be drawn in
# the same pass without fighting the transform.

func _draw() -> void:
	if state == State.DEAD:
		return
	var hull: Color = skin.get("hull", PH.C_SHIP)
	var trim: Color = skin.get("trim", PH.C_RING)
	var flame_col: Color = skin.get("flame", PH.C_FLAME)

	_draw_trail(trim)

	if _flame > 0.01:
		var l := 16.0 + 12.0 * _flame * (0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.05))
		draw_colored_polygon(_rot([Vector2(-11, -6), Vector2(-11, 6), Vector2(-11 - l, 0)]),
			Color(flame_col.r, flame_col.g, flame_col.b, 0.9 * _flame))
		draw_colored_polygon(_rot([Vector2(-11, -3), Vector2(-11, 3), Vector2(-11 - l * 0.55, 0)]),
			Color(1, 1, 1, 0.75 * _flame))

	var pts := _rot(_hull_points(int(skin.get("shape", 0))))
	draw_colored_polygon(pts, hull)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.25), 2.0, true)
	draw_circle(Vector2.from_angle(_heading) * 5.0, 4.5, trim)


func _draw_trail(col: Color) -> void:
	if _trail.size() < 2:
		return
	for i in range(_trail.size() - 1):
		var f := 1.0 - float(i) / float(_trail.size())
		draw_line(_trail[i] - position, _trail[i + 1] - position,
			Color(col.r, col.g, col.b, 0.55 * f), 5.0 * f, true)


func _rot(points) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append((p as Vector2).rotated(_heading))
	return out


static func _hull_points(shape: int) -> PackedVector2Array:
	match shape:
		1:  # broad wings
			return PackedVector2Array([
				Vector2(20, 0), Vector2(-4, -8), Vector2(-14, -17), Vector2(-11, -6),
				Vector2(-12, 0), Vector2(-11, 6), Vector2(-14, 17), Vector2(-4, 8),
			])
		2:  # long-hauler with tail fins
			return PackedVector2Array([
				Vector2(25, 0), Vector2(3, -6), Vector2(-12, -8), Vector2(-17, -14),
				Vector2(-12, -3), Vector2(-12, 3), Vector2(-17, 14), Vector2(-12, 8), Vector2(3, 6),
			])
		_:  # rounded capsule
			return PackedVector2Array([
				Vector2(18, 0), Vector2(9, -8), Vector2(-9, -8), Vector2(-14, -4),
				Vector2(-14, 4), Vector2(-9, 8), Vector2(9, 8),
			])
