class_name Glow
extends Node2D
## The only thing on the board that moves.
##
## A puzzle is still between taps, so the board redraws when the board changes
## and not once a frame. That leaves two things that do want to animate — the
## halo breathing on a satisfied target, and the ripple under a tap — and they
## live here, on their own node, drawing a handful of circles. With nothing lit
## and nothing tapped this node does no work at all.

const RIPPLE_LIFE := 0.34
const BREATHE := 3.0

var _marks: Array[Dictionary] = []   ## {pos: Vector2, col: Color, r: float}

var _t: float = 0.0
var _ripple: float = 0.0
var _ripple_pos: Vector2 = Vector2.ZERO
var _ripple_col: Color = Color.WHITE
var _ripple_r: float = 40.0


## Always redraws, including when the new list is empty — going idle is itself a
## change, and the early-out in _process() would otherwise leave the last frame's
## halos burnt onto the screen for the rest of the run.
func set_marks(v: Array[Dictionary]) -> void:
	_marks = v
	queue_redraw()


func tap(pos: Vector2, col: Color, radius: float) -> void:
	_ripple = RIPPLE_LIFE
	_ripple_pos = pos
	_ripple_col = col
	_ripple_r = radius
	queue_redraw()


func _process(delta: float) -> void:
	if _ripple > 0.0:
		_ripple = maxf(_ripple - delta, 0.0)
	elif _marks.is_empty():
		return  # nothing is animating, so nothing needs redrawing
	_t += delta
	queue_redraw()


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_t * BREATHE)
	for m in _marks:
		var c: Color = m.col
		var r: float = m.r
		draw_circle(m.pos, r * (1.9 + 0.35 * pulse), Color(c.r, c.g, c.b, 0.07 + 0.05 * pulse))
		draw_circle(m.pos, r * (1.3 + 0.16 * pulse), Color(c.r, c.g, c.b, 0.13 + 0.07 * pulse))

	if _ripple > 0.0:
		var f := _ripple / RIPPLE_LIFE
		draw_arc(_ripple_pos, _ripple_r * (1.4 - 0.5 * f), 0.0, TAU, 28,
			Color(_ripple_col.r, _ripple_col.g, _ripple_col.b, 0.5 * f), 2.5, true)
