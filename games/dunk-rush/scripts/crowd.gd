class_name Crowd
extends Node2D
## The arena behind the play: tiers of seated crowd, drawn procedurally and
## tiled so the stands are endless without ever holding more than one screen's
## worth in memory.
##
## Same trick as any parallax layer — each tile seeds its own RNG from its
## coordinates, so a tile looks identical every time it scrolls back into view
## without anything being stored between frames.

const TILE := 480.0
const LAYERS := [
	{"parallax": 0.12, "rows": 3, "per_row": 7, "size": 3.4, "alpha": 0.16},
	{"parallax": 0.28, "rows": 3, "per_row": 6, "size": 4.6, "alpha": 0.26},
	{"parallax": 0.46, "rows": 2, "per_row": 5, "size": 6.0, "alpha": 0.34},
]

var cam_pos: Vector2 = Vector2.ZERO
var view_size: Vector2 = Vector2(720, 1280)
var zoom: float = 1.0
var theme: Dictionary = {}


func _draw() -> void:
	var base: Color = theme.get("crowd", Color(0.30, 0.34, 0.52))
	var flash: Color = theme.get("flash", Color(1.0, 0.97, 0.85))
	var half := view_size * 0.5 / zoom
	var t := Time.get_ticks_msec() * 0.001

	for li in LAYERS.size():
		var layer: Dictionary = LAYERS[li]
		var origin: Vector2 = cam_pos * float(layer.parallax)
		var x0 := int(floor((origin.x - half.x) / TILE))
		var x1 := int(ceil((origin.x + half.x) / TILE))
		var y0 := int(floor((origin.y - half.y) / TILE))
		var y1 := int(ceil((origin.y + half.y) / TILE))

		for tx in range(x0, x1 + 1):
			for ty in range(y0, y1 + 1):
				_draw_tile(tx, ty, li, layer, origin, base, flash, t)


func _draw_tile(tx: int, ty: int, li: int, layer: Dictionary, origin: Vector2,
		base: Color, flash: Color, t: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _tile_seed(tx, ty, li)
	# Tier heights are seeded from the tile's row alone, never its column, so
	# neighbouring tiles put their seats at the same heights. Seeding this from
	# the full tile coordinate is what puts a visible vertical seam down the
	# stands wherever two tile columns meet.
	var row_rng := RandomNumberGenerator.new()
	row_rng.seed = _tile_seed(0, ty, li)

	var corner := Vector2(tx * TILE, ty * TILE)
	var rows := int(layer.rows)
	var alpha := float(layer.alpha)
	var size := float(layer.size)

	for r in rows:
		var row_y := (float(r) + row_rng.randf_range(0.18, 0.5)) / float(rows) * TILE
		# The rail each tier of seats sits on.
		var rail_a := corner + Vector2(0.0, row_y + size * 1.9)
		var rail_b := rail_a + Vector2(TILE, 0.0)
		draw_line(_at(rail_a, origin), _at(rail_b, origin),
				Color(base.r, base.g, base.b, alpha * 0.5), 1.6)

		for i in int(layer.per_row):
			var jitter := rng.randf_range(0.0, 1.0)
			var p := corner + Vector2((float(i) + jitter) / float(layer.per_row) * TILE, row_y)
			var c := base
			# A few heads are camera flashes, blinking out of phase with each other.
			if rng.randf() < 0.06:
				var blink := sin(t * 2.4 + rng.randf() * TAU)
				if blink > 0.86:
					c = flash
			draw_circle(_at(p, origin), size, Color(c.r, c.g, c.b, alpha + 0.1 * rng.randf()))


## Undo the parallax offset so the layer drifts slower than the camera does.
func _at(world: Vector2, origin: Vector2) -> Vector2:
	return world - origin + cam_pos


static func _tile_seed(tx: int, ty: int, layer: int) -> int:
	return tx * 73856093 ^ ty * 19349663 ^ (layer + 1) * 83492791
