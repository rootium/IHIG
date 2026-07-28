class_name Board
extends Node2D
## Draws the puzzle and turns taps into cells.
##
## Beam geometry is rebuilt only when the board changes — a tap, a new level, a
## resize — and never per frame, because between taps nothing about a puzzle is
## moving. The rebuild sorts every segment into one bucket per colour mask, so
## however tangled the light gets, the whole beam layer draws in at most seven
## draw_multiline() calls instead of one call per segment.
##
## The one animated layer is a child Glow node; see glow.gd.

signal tile_pressed(cell: int)

const MASKS := 8               ## Colour masks are three bits, so 0..7.
const MAX_CELL := 96.0         ## Cap so a small grid does not fill the screen.

var grid: Grid
var palette: Dictionary = {}
var optic: Dictionary = {}
var interactive: bool = false
var recv: Dictionary = {}      ## What each target is currently receiving.

var _rect: Rect2 = Rect2()
var _cell: float = 48.0
var _origin: Vector2 = Vector2.ZERO
var _lit: Dictionary = {}
var _seg: Array[PackedVector2Array] = []
var _glow: Glow


func _ready() -> void:
	_seg.resize(MASKS)
	for i in MASKS:
		_seg[i] = PackedVector2Array()
	_glow = Glow.new()
	_glow.z_index = 3
	add_child(_glow)


func set_level(g: Grid) -> void:
	grid = g
	_measure()
	refresh()


func layout(rect: Rect2) -> void:
	_rect = rect
	_measure()
	refresh()


## Re-traces the board and rebuilds everything drawn from it.
func refresh() -> void:
	if grid == null:
		return
	var res := Beam.trace(grid)
	_lit = res.lit
	recv = res.recv
	_build_segments()
	_build_marks()
	queue_redraw()


func solved() -> bool:
	return grid != null and Beam.solved(grid, recv)


func center(cell: int) -> Vector2:
	return _origin + Vector2(grid.x_of(cell) + 0.5, grid.y_of(cell) + 0.5) * _cell


## The cell under a viewport point, or -1 if the point missed the board.
func cell_at(screen_pos: Vector2) -> int:
	if grid == null:
		return -1
	var local := (screen_pos - _origin) / _cell
	var x := int(floor(local.x))
	var y := int(floor(local.y))
	if x < 0 or y < 0 or x >= grid.w or y >= grid.h:
		return -1
	return grid.cell_at(x, y)


func _unhandled_input(event: InputEvent) -> void:
	if not interactive or grid == null or not (event is InputEventMouseButton):
		return
	var e := event as InputEventMouseButton
	if e.button_index != MOUSE_BUTTON_LEFT or not e.pressed:
		return
	var cell := cell_at(get_viewport().get_canvas_transform().affine_inverse() * e.position)
	if cell >= 0:
		tile_pressed.emit(cell)


## Feedback for a tap the game accepted. Kept here so the caller does not have
## to know where a cell is on screen.
func ping(cell: int) -> void:
	_glow.tap(center(cell), palette.get("ink", LM.C_INK), _cell * 0.42)


# --- geometry ----------------------------------------------------------------

func _measure() -> void:
	if grid == null or _rect.size.x <= 0.0:
		return
	_cell = minf(minf(_rect.size.x / grid.w, _rect.size.y / grid.h), MAX_CELL)
	_origin = _rect.position + (_rect.size - Vector2(grid.w, grid.h) * _cell) * 0.5


## Turns the trace into line segments, bucketed by colour.
##
## Each lit key is one beam crossing one cell, so the geometry for it is the
## piece of the beam inside that cell: straight across an empty one, in to the
## middle and back out on a new heading at a mirror, and both at once at a
## splitter.
##
## It accumulates into plain Arrays and converts once at the end, because a
## PackedVector2Array is a value type: appending to one nested inside another
## container copies the whole buffer every time, where a plain Array is a
## reference and appends in place.
func _build_segments() -> void:
	var buckets: Array[Array] = []
	buckets.resize(MASKS)
	for i in MASKS:
		buckets[i] = []

	var half := _cell * 0.5
	for key in _lit:
		var cell: int = key >> 2
		var dir: int = key & 3
		var mid := center(cell)
		var v := Grid.vec(dir) * half
		var bucket: Array = buckets[_lit[key]]
		bucket.append(mid - v)
		bucket.append(mid)
		match grid.kind[cell]:
			Grid.Kind.EMPTY:
				bucket.append(mid)
				bucket.append(mid + v)
			Grid.Kind.MIRROR:
				bucket.append(mid)
				bucket.append(mid + Grid.vec(Grid.reflect(dir, grid.orient[cell])) * half)
			Grid.Kind.SPLITTER:
				bucket.append(mid)
				bucket.append(mid + v)
				bucket.append(mid)
				bucket.append(mid + Grid.vec(Grid.reflect(dir, grid.orient[cell])) * half)
			_:
				pass  # walls, sources and targets swallow the beam at the centre

	for i in MASKS:
		_seg[i] = PackedVector2Array(buckets[i])


func _build_marks() -> void:
	var marks: Array[Dictionary] = []
	for cell in grid.size():
		if grid.kind[cell] != Grid.Kind.TARGET:
			continue
		var want := int(grid.tint[cell])
		if int(recv.get(cell, 0)) == want:
			marks.append({"pos": center(cell), "col": LM.mix(want, palette), "r": _cell * 0.3})
	_glow.set_marks(marks)


# --- drawing -----------------------------------------------------------------

func _draw() -> void:
	if grid == null:
		return
	var span := Vector2(grid.w, grid.h) * _cell
	draw_rect(Rect2(_origin - Vector2(8, 8), span + Vector2(16, 16)),
		palette.get("board", LM.C_BOARD))

	var line: Color = palette.get("grid", LM.C_GRID)
	for x in grid.w + 1:
		var px := _origin.x + x * _cell
		draw_line(Vector2(px, _origin.y), Vector2(px, _origin.y + span.y), line, 1.0)
	for y in grid.h + 1:
		var py := _origin.y + y * _cell
		draw_line(Vector2(_origin.x, py), Vector2(_origin.x + span.x, py), line, 1.0)

	for cell in grid.size():
		if grid.kind[cell] == Grid.Kind.WALL:
			_draw_wall(cell)

	_draw_beams()

	for cell in grid.size():
		match grid.kind[cell]:
			Grid.Kind.MIRROR:
				_draw_mirror(cell, false)
			Grid.Kind.SPLITTER:
				_draw_mirror(cell, true)
			Grid.Kind.SOURCE:
				_draw_source(cell)
			Grid.Kind.TARGET:
				_draw_target(cell)
			_:
				pass


func _draw_beams() -> void:
	var core: float = maxf(_cell * 0.075 * float(optic.get("core", 1.0)), 1.5)
	var glow: float = core * float(optic.get("glow", 3.4))
	var hot: float = optic.get("hot", 0.0)
	for mask in range(1, MASKS):
		var pts := _seg[mask]
		if pts.is_empty():
			continue
		var c := LM.mix(mask, palette)
		draw_multiline(pts, Color(c.r, c.g, c.b, 0.13), glow, true)
		draw_multiline(pts, Color(c.r, c.g, c.b, 0.92), core, true)
		if hot > 0.0:
			draw_multiline(pts, Color(1, 1, 1, hot), core * 0.34, true)


func _draw_wall(cell: int) -> void:
	var r := _cell * 0.36
	var mid := center(cell)
	var col: Color = palette.get("wall", LM.C_WALL)
	draw_rect(Rect2(mid - Vector2(r, r), Vector2(r, r) * 2.0), col)
	draw_rect(Rect2(mid - Vector2(r, r) * 0.62, Vector2(r, r) * 1.24), col.darkened(0.25))


## Both pieces are their diagonal. A mirror draws it solid; a splitter draws it
## see-through with solid ends — a half-silvered mirror, which is exactly what
## it behaves like. The ends stay opaque so the angle is still readable at a
## glance, since the angle is the only thing a tap changes.
func _draw_mirror(cell: int, split: bool) -> void:
	var mid := center(cell)
	var k := _cell * 0.33
	var d := Vector2(k, -k) if grid.orient[cell] == 0 else Vector2(k, k)
	var col: Color = optic.get("piece", Color(0.86, 0.90, 1.0))
	var wide := maxf(_cell * 0.10, 3.0)

	draw_circle(mid, _cell * 0.42, Color(1, 1, 1, 0.035))
	if split:
		draw_line(mid - d, mid + d, Color(col.r, col.g, col.b, 0.34), wide, true)
		draw_circle(mid - d, wide * 0.66, col)
		draw_circle(mid + d, wide * 0.66, col)
	else:
		draw_line(mid - d, mid + d, Color(0, 0, 0, 0.35), wide + 4.0, true)
		draw_line(mid - d, mid + d, col, wide, true)
		# One bright edge, so which face the light strikes is legible.
		draw_line(mid - d, mid + d, Color(1, 1, 1, 0.35), wide * 0.3, true)


func _draw_source(cell: int) -> void:
	var mid := center(cell)
	var col := LM.mix(int(grid.tint[cell]), palette)
	var r := _cell * 0.30
	draw_circle(mid, r * 1.7, Color(col.r, col.g, col.b, 0.14))
	draw_rect(Rect2(mid - Vector2(r, r), Vector2(r, r) * 2.0), col)
	draw_rect(Rect2(mid - Vector2(r, r) * 0.5, Vector2(r, r)), Color(1, 1, 1, 0.75))
	# The nozzle says which way it fires without the player having to guess.
	var v := Grid.vec(int(grid.orient[cell]))
	var n := Vector2(-v.y, v.x)
	draw_colored_polygon(PackedVector2Array([
		mid + v * (r * 2.1), mid + v * r + n * r * 0.62, mid + v * r - n * r * 0.62]), col)


## Three states, and the difference between them is the whole read of the
## board: an empty ring is waiting, a ring with a mismatched dot inside is being
## fed the wrong colour, and a filled disc is done. The wrong-colour state
## matters most — it is the game telling you *which* colour arrived, which is
## the only clue a mixing puzzle can give you.
func _draw_target(cell: int) -> void:
	var mid := center(cell)
	var want := int(grid.tint[cell])
	var got := int(recv.get(cell, 0))
	var col := LM.mix(want, palette)
	var r := _cell * 0.30

	if got == want:
		draw_circle(mid, r, col)
		draw_circle(mid, r * 0.42, Color(1, 1, 1, 0.85))
		return

	draw_arc(mid, r, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.85), maxf(_cell * 0.055, 2.0), true)
	if got != 0:
		var have := LM.mix(got, palette)
		draw_circle(mid, r * 0.45, Color(have.r, have.g, have.b, 0.9))
