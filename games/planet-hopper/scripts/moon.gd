class_name Moon
extends Node2D
## A small body circling a planet. Harmless to look at, lethal to touch —
## moons are what make an otherwise safe orbit a timing problem.

var host: Planet = null
var dist: float = 200.0
var radius: float = 22.0
var ang: float = 0.0
var speed: float = 0.8
var theme: Dictionary = {}

var _craters: Array[Vector3] = []


func setup(p_host: Planet, p_dist: float, p_radius: float, rng: RandomNumberGenerator) -> void:
	host = p_host
	dist = p_dist
	radius = p_radius
	ang = rng.randf() * TAU
	speed = rng.randf_range(0.55, 1.25) * (1.0 if rng.randf() < 0.5 else -1.0)
	for i in rng.randi_range(2, 4):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.2, 0.55) * radius
		_craters.append(Vector3(cos(a) * d, sin(a) * d, rng.randf_range(0.14, 0.28) * radius))


func _process(delta: float) -> void:
	if not is_instance_valid(host):
		return
	ang += speed * delta
	position = host.position + Vector2(cos(ang), sin(ang)) * dist
	queue_redraw()


func _draw() -> void:
	var col: Color = theme.get("moon", PH.C_MOON)
	draw_circle(Vector2.ZERO, radius, col)
	for c in _craters:
		draw_circle(Vector2(c.x, c.y), c.z, col.darkened(0.28))
	# Faint trace of the path it sweeps, drawn in the moon's local space.
	if is_instance_valid(host):
		draw_arc(host.position - position, dist, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.1), 1.0, true)
