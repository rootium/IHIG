class_name StarPickup
extends Node2D
## A floating credit, scattered along the routes between planets. Picking these
## up is the reason to take the scenic line instead of the safe one.

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
	var c: Color = theme.get("star_pickup", PH.C_STAR)
	var pulse := 1.0 + 0.12 * sin(_t * 3.0)
	draw_circle(Vector2.ZERO, radius * 1.7 * pulse, Color(c.r, c.g, c.b, 0.10))
	# Four-pointed sparkle: alternating long and short vertices around a circle.
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * i / 8.0 - PI * 0.5
		var r: float = radius * pulse * (1.0 if i % 2 == 0 else 0.34)
		pts.append(Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, c)
