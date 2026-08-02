class_name Ball
extends RefCounted
## Seam drawing for anything round and orange.
##
## The player's ball, the loose balls in the lane and the golden pickups are all
## the same shape at three different sizes, so the seams live here rather than
## being written out three times with three sets of magic numbers.

## Draws the eight-panel seam pattern onto `ci`, centred on `c`. `spin` rotates
## the whole pattern, which is what makes a rolling ball read as rolling.
static func draw_seams(ci: CanvasItem, c: Vector2, r: float, spin: float, col: Color) -> void:
	var w := maxf(1.2, r * 0.10)
	ci.draw_arc(c, r, 0.0, TAU, 24, col, w, true)

	var axis := Vector2.from_angle(spin) * r
	ci.draw_line(c - axis, c + axis, col, w, true)

	# Two seams bulging either side of that axis. Sampling x = k*sqrt(1 - t^2)
	# keeps them on the sphere, so they meet the outline exactly at the poles
	# instead of crossing it.
	for k: float in [0.52, -0.52]:
		var pts := PackedVector2Array()
		for i in 13:
			var t := -1.0 + 2.0 * float(i) / 12.0
			var p := Vector2(k * r * sqrt(maxf(0.0, 1.0 - t * t)), t * r)
			pts.append(c + p.rotated(spin))
		ci.draw_polyline(pts, col, w, true)
