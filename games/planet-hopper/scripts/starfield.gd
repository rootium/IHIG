class_name Starfield
extends Node2D
## Three parallax layers of stars, tiled procedurally so the field is endless
## without holding a single star in memory beyond one screen's worth.

const TILE := 512.0
const LAYERS := [
	{"parallax": 0.15, "density": 5, "size": 1.1, "alpha": 0.35},
	{"parallax": 0.35, "density": 4, "size": 1.7, "alpha": 0.55},
	{"parallax": 0.6, "density": 3, "size": 2.4, "alpha": 0.8},
]

var cam_pos: Vector2 = Vector2.ZERO
var view_size: Vector2 = Vector2(720, 1280)
var zoom: float = 1.0
var theme: Dictionary = {}


func _draw() -> void:
	var star: Color = theme.get("star", Color(0.85, 0.88, 1.0))
	var half := view_size * 0.5 / zoom

	for li in LAYERS.size():
		var layer: Dictionary = LAYERS[li]
		var origin: Vector2 = cam_pos * float(layer.parallax)
		var x0 := int(floor((origin.x - half.x) / TILE))
		var x1 := int(ceil((origin.x + half.x) / TILE))
		var y0 := int(floor((origin.y - half.y) / TILE))
		var y1 := int(ceil((origin.y + half.y) / TILE))

		for tx in range(x0, x1 + 1):
			for ty in range(y0, y1 + 1):
				var rng := RandomNumberGenerator.new()
				rng.seed = _tile_seed(tx, ty, li)
				for i in int(layer.density):
					var local := Vector2(rng.randf(), rng.randf()) * TILE
					var world := Vector2(tx * TILE, ty * TILE) + local
					# Undo the parallax offset so the layer drifts slower than the camera.
					var at := world - origin + cam_pos
					var tw: float = 0.65 + 0.35 * sin(float(rng.randi() % 100))
					draw_circle(at, float(layer.size), Color(star.r, star.g, star.b, float(layer.alpha) * tw))


static func _tile_seed(tx: int, ty: int, layer: int) -> int:
	return tx * 73856093 ^ ty * 19349663 ^ (layer + 1) * 83492791
