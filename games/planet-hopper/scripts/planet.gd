class_name Planet
extends Node2D
## A body you can orbit. Green planets hold oxygen, amber ones hold fuel, and
## both carry a finite reserve so camping one is only ever a temporary fix.

enum Kind { OXYGEN, FUEL, BARREN }

var kind: Kind = Kind.BARREN
var radius: float = 100.0
var mass: float = 10000.0
var influence: float = 900.0
var reserve: float = 0.0
var spin: float = 0.3
var theme: Dictionary = {}

## Set by Main each frame when the predicted flight path ends here. Drives the
## bright ring and tick marks that tell you where you are about to land.
var is_target: bool = false
## Set by Main when the ship is in orbit here. Together with is_target this
## gates the reserve gauge: drawing one on every planet put a second ring around
## everything and made the screen unreadable.
var is_host: bool = false

var _features: Array[Vector3] = []
var _angle: float = 0.0


func setup(p_kind: Kind, p_radius: float, rng: RandomNumberGenerator) -> void:
	kind = p_kind
	radius = p_radius
	mass = radius * radius
	influence = radius * PH.INFLUENCE_MULT
	spin = rng.randf_range(-0.35, 0.35)
	reserve = 0.0
	if kind == Kind.OXYGEN:
		reserve = rng.randf_range(85.0, 140.0)
	elif kind == Kind.FUEL:
		reserve = rng.randf_range(80.0, 130.0)
	for i in rng.randi_range(2, 4):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.2, 0.58) * radius
		_features.append(Vector3(cos(a) * d, sin(a) * d, rng.randf_range(0.09, 0.18) * radius))


func base_color() -> Color:
	match kind:
		Kind.OXYGEN:
			return theme.get("oxygen", PH.C_OXY)
		Kind.FUEL:
			return theme.get("fuel", PH.C_FUEL)
		_:
			return theme.get("barren", PH.C_BARREN)


func has_supply() -> bool:
	return kind != Kind.BARREN and reserve > 0.01


func orbit_radius() -> float:
	return radius + PH.ORBIT_GAP


## Cross this ring and the planet catches you. It is drawn, so what you see on
## screen is the actual rule.
func capture_radius() -> float:
	return radius * PH.CAPTURE_MULT + PH.CAPTURE_BASE


func _process(delta: float) -> void:
	_angle += spin * delta
	queue_redraw()


func _draw() -> void:
	var col := base_color()
	if kind != Kind.BARREN and not has_supply():
		col = col.lerp(Color(0.42, 0.44, 0.52), 0.62)

	# Flat body with a soft drop shadow and an inset highlight, which is what
	# gives these a lit, rounded read without any textures.
	draw_circle(Vector2.ZERO, radius * 1.13, Color(col.r, col.g, col.b, 0.07))
	draw_circle(Vector2(0, radius * 0.06), radius, Color(0, 0, 0, 0.28))
	draw_circle(Vector2.ZERO, radius, col)
	draw_circle(Vector2(-radius * 0.16, -radius * 0.16), radius * 0.80, col.lightened(0.10))
	for f in _features:
		draw_circle(Vector2(f.x, f.y).rotated(_angle), f.z, col.darkened(0.16))

	_draw_ring()
	if kind != Kind.BARREN and is_target:
		_draw_reserve_gauge(col)


## Three states, and the contrast between them is the whole aiming interface:
## a dim partial arc for scenery, a bright cyan circle with crosshair ticks for
## wherever the trajectory lands, and — for the planet you are currently on — a
## full circle that doubles as the supply gauge. Folding the gauge into the ring
## keeps the host to a single circle; drawing both put two concentric rings
## around it that read as noise.
func _draw_ring() -> void:
	var r := capture_radius()
	if is_target:
		var c: Color = theme.get("ring", PH.C_RING)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 80, c, 3.0, true)
		for i in 4:
			var d := Vector2.from_angle(PI * 0.25 + i * PI * 0.5)
			draw_line(d * (r - 9.0), d * (r + 9.0), c, 3.0, true)
		return

	var idle: Color = theme.get("ring_idle", PH.C_RING_IDLE)
	if is_host:
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 72, Color(idle.r, idle.g, idle.b, 0.35), 2.5, true)
		if has_supply():
			var frac := clampf(reserve / 140.0, 0.0, 1.0)
			var col := base_color()
			draw_arc(Vector2.ZERO, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 64,
				Color(col.r, col.g, col.b, 0.9), 4.5, true)
	else:
		draw_arc(Vector2.ZERO, r, PI * 0.15, PI * 0.85, 40, Color(idle.r, idle.g, idle.b, 0.55), 3.0, true)


## How much oxygen or fuel is left here, as an arc just outside the capture
## ring. Thin and low-contrast on purpose so it reads as an annotation on the
## ring rather than a second ring.
func _draw_reserve_gauge(col: Color) -> void:
	var frac := clampf(reserve / 140.0, 0.0, 1.0)
	if frac <= 0.0:
		return
	var r := capture_radius() + 12.0
	draw_arc(Vector2.ZERO, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, Color(col.r, col.g, col.b, 0.55), 3.0, true)
