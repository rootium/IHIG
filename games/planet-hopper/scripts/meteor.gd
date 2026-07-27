class_name Meteor
extends Node2D
## Drifts on a straight line across the lane, ignoring gravity. Cheap to
## dodge if you see it coming, fatal if you are busy watching your fuel.

var radius: float = 16.0
var vel: Vector2 = Vector2.ZERO
var theme: Dictionary = {}

var _spin: float = 0.0
var _rate: float = 1.0
var _shape: PackedVector2Array = PackedVector2Array()
var _trail: Array[Vector2] = []


func setup(p_radius: float, p_vel: Vector2, rng: RandomNumberGenerator) -> void:
	radius = p_radius
	vel = p_vel
	_rate = rng.randf_range(-2.2, 2.2)
	# Lumpy rock: a circle with each vertex pushed in or out a little.
	var n := rng.randi_range(7, 9)
	for i in n:
		var a := TAU * i / float(n)
		var r := radius * rng.randf_range(0.72, 1.25)
		_shape.append(Vector2(cos(a), sin(a)) * r)


func _process(delta: float) -> void:
	position += vel * delta
	_spin += _rate * delta
	_trail.push_front(Vector2.ZERO)
	for i in range(1, _trail.size()):
		_trail[i] -= vel * delta
	if _trail.size() > 14:
		_trail.resize(14)
	queue_redraw()


func _draw() -> void:
	var col: Color = theme.get("meteor", PH.C_METEOR)
	for i in range(_trail.size() - 1, 0, -1):
		var f := 1.0 - float(i) / float(_trail.size())
		draw_circle(_trail[i], radius * 0.5 * f, Color(col.r, col.g, col.b, 0.16 * f))
	var pts := PackedVector2Array()
	for p in _shape:
		pts.append(p.rotated(_spin))
	draw_colored_polygon(pts, col)
	draw_circle(Vector2(-radius * 0.2, -radius * 0.15), radius * 0.28, col.darkened(0.3))
