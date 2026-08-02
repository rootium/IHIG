class_name LooseBall
extends Node2D
## A ball loose in the lane, drifting on a straight line and ignoring gravity.
## Fatal on contact, and cheap to dodge if you spotted it before you jumped.

var radius: float = 15.0
var vel: Vector2 = Vector2.ZERO
var theme: Dictionary = {}

var _spin: float = 0.0
var _rate: float = 1.0


func setup(p_radius: float, p_vel: Vector2, rng: RandomNumberGenerator) -> void:
	radius = p_radius
	vel = p_vel
	# Spin direction follows travel, so the seams read as rolling, not flickering.
	_rate = signf(p_vel.x) * rng.randf_range(2.4, 4.2)


## Stepped by Court rather than by _process, so everything the player can hit
## advances on the same clock the player does.
func step(delta: float) -> void:
	position += vel * delta
	_spin += _rate * delta
	queue_redraw()


func _draw() -> void:
	var col: Color = theme.get("loose", BD.C_LOOSE)
	draw_circle(Vector2.ZERO, radius * 1.35, Color(col.r, col.g, col.b, 0.10))
	draw_circle(Vector2.ZERO, radius, col)
	Ball.draw_seams(self, Vector2.ZERO, radius, _spin, Color(0.1, 0.1, 0.13, 0.75))
