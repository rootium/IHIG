class_name GoldBall
extends Node2D
## A floating credit, scattered along the lines between rims. Collecting these
## is the reason to take the long way round instead of the safe one.

const VALUE := 1

var radius: float = 15.0
var theme: Dictionary = {}

var _t: float = 0.0


func _ready() -> void:
	_t = randf() * TAU  # desynchronise the pulse between pickups


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c: Color = theme.get("gold", BD.C_GOLD)
	var pulse := 1.0 + 0.10 * sin(_t * 3.0)
	draw_circle(Vector2.ZERO, radius * 1.8 * pulse, Color(c.r, c.g, c.b, 0.10))
	draw_circle(Vector2.ZERO, radius * pulse, c)
	Ball.draw_seams(self, Vector2.ZERO, radius * pulse, _t * 0.9, Color(0.42, 0.31, 0.05, 0.8))
