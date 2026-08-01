class_name Pieces
extends RefCounted
## How every piece looks, drawn from a centre and a cell size rather than from a
## position on a board.
##
## The board draws its cells with these, and so does the legend on the how-to
## screen. That is the whole reason they live here: a legend that redraws the
## pieces in its own code is a legend that goes quietly wrong the first time the
## board's look changes, and a wrong legend is worse than none — it teaches the
## player to read something that is not there.


static func wall(ci: CanvasItem, mid: Vector2, cell: float, palette: Dictionary) -> void:
	var r := cell * 0.36
	var col: Color = palette.get("wall", LM.C_WALL)
	ci.draw_rect(Rect2(mid - Vector2(r, r), Vector2(r, r) * 2.0), col)
	ci.draw_rect(Rect2(mid - Vector2(r, r) * 0.62, Vector2(r, r) * 1.24), col.darkened(0.25))


## Both pieces are their diagonal. A mirror draws it solid; a splitter draws it
## see-through with solid ends — a half-silvered mirror, which is exactly what
## it behaves like. The ends stay opaque so the angle is still readable at a
## glance, since the angle is the only thing a tap changes.
static func mirror(ci: CanvasItem, mid: Vector2, cell: float, orient: int,
		split: bool, optic: Dictionary) -> void:
	var k := cell * 0.33
	var d := Vector2(k, -k) if orient == 0 else Vector2(k, k)
	var col: Color = optic.get("piece", Color(0.86, 0.90, 1.0))
	var wide := maxf(cell * 0.10, 3.0)

	ci.draw_circle(mid, cell * 0.42, Color(1, 1, 1, 0.035))
	if split:
		ci.draw_line(mid - d, mid + d, Color(col.r, col.g, col.b, 0.34), wide, true)
		ci.draw_circle(mid - d, wide * 0.66, col)
		ci.draw_circle(mid + d, wide * 0.66, col)
	else:
		ci.draw_line(mid - d, mid + d, Color(0, 0, 0, 0.35), wide + 4.0, true)
		ci.draw_line(mid - d, mid + d, col, wide, true)
		# One bright edge, so which face the light strikes is legible.
		ci.draw_line(mid - d, mid + d, Color(1, 1, 1, 0.35), wide * 0.3, true)


static func source(ci: CanvasItem, mid: Vector2, cell: float, dir: int, col: Color) -> void:
	var r := cell * 0.30
	ci.draw_circle(mid, r * 1.7, Color(col.r, col.g, col.b, 0.14))
	ci.draw_rect(Rect2(mid - Vector2(r, r), Vector2(r, r) * 2.0), col)
	ci.draw_rect(Rect2(mid - Vector2(r, r) * 0.5, Vector2(r, r)), Color(1, 1, 1, 0.75))
	# The nozzle says which way it fires without the player having to guess.
	var v := Grid.vec(dir)
	var n := Vector2(-v.y, v.x)
	ci.draw_colored_polygon(PackedVector2Array([
		mid + v * (r * 2.1), mid + v * r + n * r * 0.62, mid + v * r - n * r * 0.62]), col)


## Three states, and the difference between them is the whole read of the
## board: an empty ring is waiting, a ring with a mismatched dot inside is being
## fed the wrong colour, and a filled disc is done. The wrong-colour state
## matters most — it is the game telling you *which* colour arrived, which is
## the only clue a mixing puzzle can give you.
##
## `got` is the mask actually arriving; 0 means nothing is.
static func target(ci: CanvasItem, mid: Vector2, cell: float, want: int, got: int,
		palette: Dictionary) -> void:
	var col := LM.mix(want, palette)
	var r := cell * 0.30

	if got == want:
		ci.draw_circle(mid, r, col)
		ci.draw_circle(mid, r * 0.42, Color(1, 1, 1, 0.85))
		return

	ci.draw_arc(mid, r, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.85),
		maxf(cell * 0.055, 2.0), true)
	if got != 0:
		var have := LM.mix(got, palette)
		ci.draw_circle(mid, r * 0.45, Color(have.r, have.g, have.b, 0.9))
