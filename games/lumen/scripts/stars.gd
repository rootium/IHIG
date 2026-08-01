class_name StarRow
extends Control
## The three-star rating on the level-cleared screen, drawn rather than typed.
##
## It used to be "★".repeat(n) + "☆".repeat(3 - n). Godot's fallback font is
## barely more than Latin-1 — it has no ★, no ☆, and no geometric shapes at all
## — so the reward screen was showing three missing-glyph boxes. Everything else
## in this game is drawn in _draw() anyway.

const GOLD := Color(1.0, 0.84, 0.36)
const EMPTY := Color(1.0, 1.0, 1.0, 0.16)

var filled: int = 0
var total: int = 3

var _radius: float = 26.0
var _gap: float = 18.0


func _init(p_radius: float = 26.0) -> void:
	_radius = p_radius
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, _radius * 2.0 + 10.0)


func set_rating(p_filled: int, p_total: int = 3) -> void:
	filled = p_filled
	total = p_total
	queue_redraw()


## Ten vertices, alternating between the outer and inner radius, starting at
## the top so the star sits upright.
func _points(mid: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var rad := r if i % 2 == 0 else r * 0.42
		var a := -PI * 0.5 + float(i) * PI / 5.0
		pts.append(mid + Vector2(cos(a), sin(a)) * rad)
	return pts


func _draw() -> void:
	var span := float(total) * (_radius * 2.0) + float(total - 1) * _gap
	var x := (size.x - span) * 0.5 + _radius
	var y := size.y * 0.5
	for i in total:
		var pts := _points(Vector2(x, y), _radius)
		if i < filled:
			draw_colored_polygon(pts, GOLD)
		else:
			var loop := pts.duplicate()
			loop.append(pts[0])
			draw_polyline(loop, EMPTY, 2.0, true)
		x += _radius * 2.0 + _gap
