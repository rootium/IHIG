class_name Baller
extends Node2D
## The player.
##
## Two states that matter: HANG, where you are holding onto a rim and can aim,
## and AIR, where gravity owns you and holding the screen spends air to float.
## The shot clock drains in both, which is what keeps you moving.
##
## Aiming is a pull-back drag: the further you pull, the harder the jump. The
## direction is clamped to always point somewhere above horizontal, because a
## jump aimed into the floor is never a thing a player meant to do.

signal died(reason: String)
signal scored(hoop: Hoop, points: int, swish: bool, bank: bool)
signal clanged

enum State { HANG, AIR, DEAD }

var state: State = State.HANG
var vel: Vector2 = Vector2.ZERO

var host: Hoop = null

var air: float = BD.AIR_MAX
var shot_clock: float = BD.SHOT_CLOCK
var combo: int = 0

## Persist between jumps so there is always a preview on screen, even before
## the player has touched anything.
var aim_dir: Vector2 = Vector2(0.42, -0.91).normalized()
var aim_power: float = 0.72

var dragging: bool = false
var drag_from: Vector2 = Vector2.ZERO
var floating: bool = false
var touch_point: Vector2 = Vector2.ZERO
var skin: Dictionary = {}

var banked: bool = false          ## Touched a backboard since the last jump.

var _spin: float = 0.0
var _lean: float = 0.0
var _clang_lockout: float = 0.0
var _pop: float = 0.0             ## Landing squash, decays to zero.
var _trail: Array[Vector2] = []
## Reused rather than allocated per frame; Court.advance() owns its contents.
var _flight := Flight.new()
var _preview := Flight.new()


func _ready() -> void:
	z_index = 10
	skin = Skins.baller(SaveData.baller_id)


func reset(p_skin: Dictionary) -> void:
	skin = p_skin
	state = State.HANG
	vel = Vector2.ZERO
	host = null
	air = BD.AIR_MAX
	shot_clock = BD.SHOT_CLOCK
	combo = 0
	banked = false
	dragging = false
	floating = false
	aim_dir = Vector2(0.42, -0.91).normalized()
	aim_power = 0.72
	_clang_lockout = 0.0
	_pop = 0.0
	_trail.clear()


## Grabs a rim. Refills air and resets the shot clock — scoring is the only way
## to get either back.
func hang(h: Hoop) -> void:
	host = h
	state = State.HANG
	vel = Vector2.ZERO
	position = h.hang_point()
	air = BD.AIR_MAX
	shot_clock = BD.SHOT_CLOCK
	banked = false
	_pop = 1.0
	_clang_lockout = BD.CLANG_LOCKOUT


## Rides the rim without spending the shot clock, for menu backdrops.
func idle(delta: float) -> void:
	if state != State.HANG or not is_instance_valid(host):
		return
	position = host.hang_point()
	_spin += delta * 1.4
	_pop = maxf(0.0, _pop - delta * 3.2)
	queue_redraw()


func die(reason: String) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	dragging = false
	floating = false
	died.emit(reason)


func speed() -> float:
	return vel.length()


func multiplier() -> int:
	return mini(1 + combo / BD.MULT_STEP, BD.MULT_MAX)


# --- the force model ---------------------------------------------------------

## The one integrator. Real flight and the on-screen preview both step through
## here, so the path you are shown and the path you get cannot drift apart.
## Position is then always `pos + vel * dt`, which is why it is not returned.
static func step_velocity(v: Vector2, dt: float, grav_mult: float, steer_x: float) -> Vector2:
	var out := v
	out.y += BD.GRAV * grav_mult * dt
	out.x += steer_x * dt
	out.x -= out.x * BD.AIR_DRAG * dt
	return out.limit_length(BD.MAX_SPEED)


## The velocity a jump from here would start with. Includes the sideways carry
## of a sliding rim, so letting go at the end of a rim's travel genuinely throws
## you further than letting go in the middle.
func launch_velocity() -> Vector2:
	var v := aim_dir * lerpf(BD.JUMP_MIN, BD.JUMP_MAX, clampf(aim_power, 0.0, 1.0))
	if state == State.HANG and is_instance_valid(host):
		v.x += host.slide_velocity()
	return v


# --- aiming ------------------------------------------------------------------

func begin_aim(at: Vector2) -> void:
	dragging = true
	drag_from = at


## Pull back from where you first touched: the aim is the vector from your
## finger to that point, so the gesture matches slinging yourself the other way.
func update_aim(at: Vector2) -> void:
	if not dragging:
		return
	var pull := drag_from - at
	if pull.length() < BD.MIN_PULL:
		return
	aim_dir = clamp_aim(pull.normalized())
	aim_power = clampf(pull.length() / BD.MAX_PULL, 0.0, 1.0)


func end_aim() -> void:
	dragging = false


## Forces an aim to point above horizontal. Which way it tips when the player
## aims downward is decided by the horizontal sign, so a drag that strays below
## the line resolves toward the side it was already heading.
static func clamp_aim(dir: Vector2) -> Vector2:
	var d := dir
	if d.length_squared() < 0.0001:
		return Vector2(0.0, -1.0)
	d = d.normalized()
	var hi := -BD.AIM_MIN_ELEVATION              # shallowest allowed, to the right
	var lo := -PI + BD.AIM_MIN_ELEVATION         # shallowest allowed, to the left
	var a := d.angle()
	if a >= lo and a <= hi:
		return d
	return Vector2.from_angle(hi if d.x >= 0.0 else lo)


## Leaves the rim. Free — air only pays for floating, so an empty meter costs
## you control in the air but never strands you on a rim.
func jump() -> void:
	if state != State.HANG:
		return
	vel = launch_velocity()
	state = State.AIR
	host = null
	banked = false
	_clang_lockout = BD.CLANG_LOCKOUT


# --- frame -------------------------------------------------------------------

func step(delta: float, court: Court) -> void:
	if state == State.DEAD:
		return
	_drop_stale_host()
	_clang_lockout = maxf(0.0, _clang_lockout - delta)
	_pop = maxf(0.0, _pop - delta * 3.2)

	shot_clock -= delta
	if shot_clock <= 0.0:
		shot_clock = 0.0
		die("Shot clock violation")
		return

	if state == State.HANG:
		_step_hang(delta)
	else:
		_step_air(delta, court)

	_push_trail()
	queue_redraw()


## A hoop lives in a chunk that gets culled once the climb leaves it behind. A
## freed Hoop can neither be hung from nor scored on, so dropping the reference
## is both safe and correct.
##
## is_instance_valid() is the whole test on purpose: in GDScript a freed object
## compares equal to null, so a `host != null` guard would skip exactly the case
## this exists to catch. is_instance_valid(null) is already false.
func _drop_stale_host() -> void:
	if state == State.HANG and not is_instance_valid(host):
		host = null
		state = State.AIR


func _step_hang(delta: float) -> void:
	if not is_instance_valid(host):
		state = State.AIR
		return
	# Ride the rim. On a sliding hoop this is what makes the timing of a jump
	# matter as much as its aim. Court.step() has already moved it this frame.
	position = host.hang_point()
	_lean = lerpf(_lean, 0.0, 1.0 - pow(0.02, delta))
	_spin += delta * 1.4


func _step_air(delta: float, court: Court) -> void:
	var grav_mult := 1.0
	var steer := 0.0
	if floating and air > 0.0:
		grav_mult = BD.FLOAT_GRAV_MULT
		steer = signf(touch_point.x - position.x) * BD.FLOAT_STEER
		air = maxf(0.0, air - BD.AIR_BURN * delta)

	# Hand our state to the court, let it do the physics, take it back. The
	# preview runs the identical call on a throwaway Flight.
	_flight.load_from(position, vel, banked)
	court.advance(_flight, delta, grav_mult, steer)
	position = _flight.pos
	vel = _flight.vel
	banked = _flight.banked

	_lean = lerpf(_lean, clampf(vel.x / 700.0, -1.0, 1.0) * 0.5, 1.0 - pow(0.05, delta))
	_spin += (vel.x * 0.004 + 2.2) * delta

	if _flight.scored_on != null:
		_score_on(_flight.scored_on)
	elif _flight.hit_iron != null and _clang_lockout <= 0.0:
		_clang_on(_flight.hit_iron)


## Clipped the iron. It costs the combo and throws you off line, but the run
## continues — you can still save it with a float or a lower rim.
func _clang_on(h: Hoop) -> void:
	var closest := h.rim_closest_point(position)
	var away := position - closest
	var n: Vector2 = away.normalized() if away.length() > 0.01 else Vector2(0.0, -1.0)
	position = closest + n * (BD.BALLER_R + 0.5)
	vel = (vel - 2.0 * n * vel.dot(n)) * BD.CLANG_BOUNCE

	# Carom off the side. Without a guaranteed outward kick the reflection damps
	# toward nothing and leaves the player resting on the rim, re-clanging every
	# lockout until the clock kills them.
	var off := position.x - h.position.x
	var dir_x := signf(off) if absf(off) > 1.0 else -signf(h.side)
	vel.x = dir_x * maxf(absf(vel.x), BD.CLANG_KICK)

	_clang_lockout = BD.CLANG_LOCKOUT
	combo = 0
	clanged.emit()


func _score_on(h: Hoop) -> void:
	var dx := absf(position.x - h.position.x)
	var swish := dx <= h.swish_half()
	var repeat := h.scored
	var points := 0
	if not repeat:
		points = BD.DUNK_POINTS
		if swish:
			points += BD.SWISH_BONUS
		if banked:
			points += BD.BANK_BONUS
		points *= multiplier()
		combo += 1
	var was_banked := banked
	h.celebrate()
	hang(h)
	scored.emit(h, points, swish and not repeat, was_banked and not repeat)


# --- prediction --------------------------------------------------------------

## Where a coasting jump from here ends up: the path, the rim it drops through,
## and the rim it clangs off instead. Called every frame so the line tracks the
## drag while you aim.
##
## The line stops the moment it meets iron. Showing the carom would be noise —
## what a player needs to know is that *this* aim does not go in, early enough
## to move their thumb.
##
## Hoops are sampled where they are now: a rim that slides will have moved by
## the time you arrive. That is deliberate — the preview promises the path your
## body takes, and leading a moving rim is left as the skill it should be.
func predict(court: Court) -> Dictionary:
	if state == State.DEAD:
		return {"points": PackedVector2Array(), "target": null, "blocked": null}

	_preview.load_from(position, launch_velocity() if state == State.HANG else vel, false)
	var pts := PackedVector2Array([_preview.pos])
	var target: Hoop = null
	var blocked: Hoop = null
	for i in BD.PREVIEW_STEPS:
		court.advance(_preview, BD.PREVIEW_DT, 1.0, 0.0)
		pts.append(_preview.pos)
		if _preview.scored_on != null:
			target = _preview.scored_on
			break
		if _preview.hit_iron != null:
			blocked = _preview.hit_iron
			break
	return {"points": pts, "target": target, "blocked": blocked}


func _push_trail() -> void:
	_trail.push_front(position)
	if _trail.size() > BD.TRAIL_LENGTH:
		_trail.resize(BD.TRAIL_LENGTH)


# --- drawing -----------------------------------------------------------------
# The node's rotation stays at zero and the figure is rotated in code, so the
# trail — which is stored in world space — can be drawn in the same pass without
# fighting the transform.

func _draw() -> void:
	if state == State.DEAD:
		return
	var jersey: Color = skin.get("jersey", BD.C_JERSEY)
	var trim: Color = skin.get("trim", Color.WHITE)
	var ball_col: Color = skin.get("ball", BD.C_BALL)
	var flesh: Color = skin.get("skin", BD.C_SKIN)

	_draw_trail(trim)

	var r := BD.BALLER_R
	# Squash on landing, stretch while rising. Cheap, and it sells the leap.
	var sy := 1.0 - 0.30 * _pop + clampf(-vel.y / 2600.0, 0.0, 0.22)
	var sx := 1.0 + 0.24 * _pop

	var hip := Vector2(0.0, r * 0.35)
	var shoulder := Vector2(0.0, -r * 0.55 * sy)

	# Legs — tucked when rising, trailing when falling.
	var tuck := clampf(-vel.y / 1200.0, 0.0, 1.0)
	for s: float in [-1.0, 1.0]:
		var knee := hip + Vector2(s * r * 0.42 * sx, r * lerpf(0.62, 0.30, tuck))
		var foot := knee + Vector2(s * r * lerpf(0.30, 0.72, tuck), r * lerpf(0.62, 0.10, tuck))
		_limb(hip, knee, foot, jersey.darkened(0.25), r * 0.20)

	# Torso.
	draw_line(_lean_pt(hip), _lean_pt(shoulder), jersey, r * 0.86, true)
	draw_circle(_lean_pt(shoulder + Vector2(0, -r * 0.05)), r * 0.40, jersey)
	# Jersey number stripe.
	draw_line(_lean_pt(hip + Vector2(0, -r * 0.1)), _lean_pt(shoulder + Vector2(0, r * 0.15)),
			Color(trim.r, trim.g, trim.b, 0.55), r * 0.22, true)

	# Head.
	var head := _lean_pt(shoulder + Vector2(0.0, -r * 0.62))
	draw_circle(head, r * 0.44, flesh)

	# The ball hand goes up when rising, down to cradle when falling.
	var up: float = clampf(-vel.y / 900.0, 0.0, 1.0) if state == State.AIR else 1.0
	var hand := _lean_pt(shoulder + Vector2(r * 0.72, -r * lerpf(0.05, 1.15, up)))
	_limb(_lean_pt(shoulder), _lean_pt(shoulder + Vector2(r * 0.55, -r * 0.35 * up)), hand,
			flesh, r * 0.18)
	# Off hand.
	var off := _lean_pt(shoulder + Vector2(-r * 0.78, -r * 0.30 * up))
	_limb(_lean_pt(shoulder), _lean_pt(shoulder + Vector2(-r * 0.6, 0.0)), off,
			flesh, r * 0.18)

	var br := r * 0.52
	draw_circle(hand, br, ball_col)
	Ball.draw_seams(self, hand, br, _spin, Color(0.12, 0.10, 0.10, 0.7))


func _limb(a: Vector2, b: Vector2, c: Vector2, col: Color, w: float) -> void:
	draw_line(a, b, col, w, true)
	draw_line(b, c, col, w, true)


func _lean_pt(p: Vector2) -> Vector2:
	return p.rotated(_lean * 0.5)


func _draw_trail(col: Color) -> void:
	if _trail.size() < 2:
		return
	for i in range(_trail.size() - 1):
		var f := 1.0 - float(i) / float(_trail.size())
		draw_line(_trail[i] - position, _trail[i + 1] - position,
				Color(col.r, col.g, col.b, 0.40 * f), 5.0 * f, true)
