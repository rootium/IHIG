class_name Planet
extends Node2D
## A body you can orbit. Oxygen and fuel planets carry a finite reserve, so
## camping one is only ever a temporary fix.

enum Kind { OXYGEN, FUEL, BARREN }

var kind: Kind = Kind.BARREN
var radius: float = 100.0
var mass: float = 10000.0
var influence: float = 800.0
var reserve: float = 0.0
var spin: float = 0.3
var theme: Dictionary = {}
## Set by Main each frame: the ship is inside this planet's capture window and
## slow enough to be caught. Drives the ring highlight.
var capture_ready: bool = false

var _features: Array[Vector3] = []  ## x, y, radius of surface blotches.
var _angle: float = 0.0


func setup(p_kind: Kind, p_radius: float, rng: RandomNumberGenerator) -> void:
	kind = p_kind
	radius = p_radius
	mass = radius * radius
	influence = radius * PH.INFLUENCE_MULT
	spin = rng.randf_range(-0.45, 0.45)
	reserve = 0.0
	if kind == Kind.OXYGEN:
		reserve = rng.randf_range(70.0, 130.0)
	elif kind == Kind.FUEL:
		reserve = rng.randf_range(65.0, 115.0)
	for i in rng.randi_range(3, 6):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.15, 0.62) * radius
		_features.append(Vector3(cos(a) * d, sin(a) * d, rng.randf_range(0.1, 0.25) * radius))


func base_color() -> Color:
	match kind:
		Kind.OXYGEN:
			return theme.get("oxygen", PH.C_OXY)
		Kind.FUEL:
			return theme.get("fuel", PH.C_FUEL)
		_:
			return theme.get("barren", PH.C_BARREN)


## True while the planet still has something left to give.
func has_supply() -> bool:
	return kind != Kind.BARREN and reserve > 0.01


func orbit_radius() -> float:
	return radius + PH.ORBIT_GAP


## Get inside this ring slowly enough and the planet catches you. It is drawn,
## so the ring on screen is the actual rule and not a decoration.
func capture_radius() -> float:
	return radius * PH.CAPTURE_MULT + PH.CAPTURE_BASE


## Heavier worlds can catch a faster ship, which gives big planets a second,
## subtler advantage over the small ones.
func capture_speed() -> float:
	return maxf(PH.CAPTURE_SPEED, sqrt(PH.GRAV * mass / capture_radius()) * 1.6)


func _process(delta: float) -> void:
	_angle += spin * delta
	queue_redraw()


func _draw() -> void:
	var col := base_color()
	var spent := kind != Kind.BARREN and not has_supply()
	if spent:
		col = col.lerp(theme.get("barren", PH.C_BARREN), 0.72)

	# Atmosphere halo, then body, then surface detail.
	draw_circle(Vector2.ZERO, radius * 1.1, Color(col.r, col.g, col.b, 0.13))
	draw_circle(Vector2.ZERO, radius, col)
	var shade := col.darkened(0.35)
	for f in _features:
		var p := Vector2(f.x, f.y).rotated(_angle)
		draw_circle(p, f.z, shade)
	# Terminator: a crescent of shadow on the far side.
	draw_arc(Vector2.ZERO, radius * 0.97, -PI * 0.45, PI * 0.55, 28, col.darkened(0.5), radius * 0.09, true)

	# The capture ring. It brightens the moment you are slow enough to be
	# caught, which is the only cue you get for when to stop braking.
	var ring := Color(col.lightened(0.4), 0.5 if has_supply() else 0.22)
	var width := 2.0
	if capture_ready:
		ring = Color(1.0, 1.0, 1.0, 0.85)
		width = 3.5
	draw_arc(Vector2.ZERO, capture_radius(), 0.0, TAU, 72, ring, width, true)

	if kind != Kind.BARREN:
		_draw_reserve_gauge(col)


## A short arc just outside the orbit ring showing what is left in the tank.
func _draw_reserve_gauge(col: Color) -> void:
	var frac := clampf(reserve / 130.0, 0.0, 1.0)
	if frac <= 0.0:
		return
	var r := capture_radius() + 11.0
	draw_arc(Vector2.ZERO, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, col.lightened(0.25), 4.0, true)
