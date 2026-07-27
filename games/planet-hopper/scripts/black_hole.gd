class_name BlackHole
extends Node2D
## Pulls far harder and far further than its size suggests, and kills inside the
## event horizon. Best used as a slingshot if you are brave, avoided if not.

var radius: float = 40.0        ## Event horizon. Touch it and the run ends.
var mass: float = 0.0
var influence: float = 0.0
var theme: Dictionary = {}

var _spin: float = 0.0
var _rate: float = 1.4


func setup(p_radius: float, rng: RandomNumberGenerator) -> void:
	radius = p_radius
	mass = radius * radius * PH.HOLE_MASS_MULT
	influence = radius * PH.HOLE_INFLUENCE_MULT
	_spin = rng.randf() * TAU
	_rate = rng.randf_range(1.0, 1.9) * (1.0 if rng.randf() < 0.5 else -1.0)


func _process(delta: float) -> void:
	_spin += _rate * delta
	queue_redraw()


func _draw() -> void:
	var col: Color = theme.get("hole", PH.C_HOLE)

	# Reach of the pull, so the danger is legible before you are inside it.
	draw_arc(Vector2.ZERO, influence, 0.0, TAU, 72, Color(col.r, col.g, col.b, 0.12), 2.0, true)

	# Accretion disc: a few offset arcs turning at different rates.
	for i in 3:
		var r := radius * (1.9 + i * 0.75)
		var a := _spin * (1.0 - i * 0.22)
		var alpha := 0.55 - i * 0.14
		draw_arc(Vector2.ZERO, r, a, a + TAU * 0.72, 40, Color(col.r, col.g, col.b, alpha), 3.5 - i * 0.7, true)

	# Photon ring and the hole itself.
	draw_circle(Vector2.ZERO, radius * 1.35, Color(col.r, col.g, col.b, 0.3))
	draw_arc(Vector2.ZERO, radius * 1.08, 0.0, TAU, 48, col.lightened(0.3), 2.5, true)
	draw_circle(Vector2.ZERO, radius, Color(0.02, 0.01, 0.05))
