class_name Defender
extends Node2D
## Patrols sideways across the lane, guarding the approach to a rim. Touching
## one ends the run.
##
## Defenders always patrol *below* the rim they guard rather than level with it,
## so they threaten the rise toward a basket instead of the moment you are
## hanging on it. A hazard you cannot escape by any route would just be a wall.

var radius: float = 22.0
var theme: Dictionary = {}

var span: float = 200.0
var speed: float = 90.0
var home_x: float = 0.0

var _phase: float = 0.0
var _bob: float = 0.0


func setup(p_radius: float, p_span: float, p_speed: float, rng: RandomNumberGenerator) -> void:
	radius = p_radius
	span = p_span
	speed = p_speed
	home_x = position.x
	_phase = rng.randf() * TAU
	_bob = rng.randf() * TAU


## Stepped by Court rather than by _process, so everything the player can hit
## advances on the same clock the player does.
func step(delta: float) -> void:
	_phase += (speed / maxf(span, 1.0)) * delta
	_bob += delta * 4.0
	position.x = home_x + sin(_phase) * span
	queue_redraw()


func _draw() -> void:
	var col: Color = theme.get("defender", BD.C_DEFENDER)
	# Arms go up on the side it is moving toward — it reads as contesting a shot.
	var lean := signf(cos(_phase))
	var reach := 0.82 + 0.18 * sin(_bob)

	draw_circle(Vector2.ZERO, radius * 1.5, Color(col.r, col.g, col.b, 0.10))
	for s: float in [-1.0, 1.0]:
		var tip := Vector2(s * radius * 0.95, -radius * (1.15 + 0.35 * reach))
		if s == lean:
			tip.y -= radius * 0.3
		draw_line(Vector2(s * radius * 0.45, -radius * 0.25), tip, col, 6.0, true)
	draw_circle(Vector2(0, radius * 0.15), radius * 0.82, col)
	draw_circle(Vector2(0, -radius * 0.72), radius * 0.42, col.lightened(0.25))
