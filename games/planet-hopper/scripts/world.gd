class_name World
extends Node2D
## Endless procedural space, generated in fixed-width chunks along +X.
##
## Each chunk is seeded from (world_seed, chunk_index) so it regenerates
## identically, and chunks far behind the ship are freed. Difficulty ramps with
## the chunk index: more moons, more black holes, more meteors, and oxygen
## planets get rarer — but every other chunk is guaranteed one, so a careful
## pilot always has somewhere to breathe.

var planets: Array[Planet] = []
var moons: Array[Moon] = []
var holes: Array[BlackHole] = []
var meteors: Array[Meteor] = []

var theme: Dictionary = {}
var world_seed: int = 0

var _chunks: Dictionary = {}  ## chunk index -> Array[Node]


func reset(p_seed: int, p_theme: Dictionary) -> void:
	for key in _chunks.keys():
		_free_chunk(key)
	_chunks.clear()
	planets.clear()
	moons.clear()
	holes.clear()
	meteors.clear()
	world_seed = p_seed
	theme = p_theme


## Generates any missing chunks around `center_x` and frees ones left behind.
## `protect` is the planet the ship is currently attached to; it is never freed.
func ensure(center_x: float, protect: Planet = null) -> void:
	var ci := int(floor(center_x / PH.CHUNK_W))
	for i in range(maxi(0, ci - PH.CHUNKS_BEHIND), ci + PH.CHUNKS_AHEAD + 1):
		if not _chunks.has(i):
			_gen_chunk(i)
	for key in _chunks.keys():
		if key < ci - PH.CHUNKS_BEHIND - 1 and not _chunk_holds(key, protect):
			_free_chunk(key)
			_chunks.erase(key)


## Bodies that bend trajectories: planets and black holes.
func gravity_bodies() -> Array:
	var out: Array = []
	out.append_array(planets)
	out.append_array(holes)
	return out


# --- generation --------------------------------------------------------------

func _gen_chunk(ci: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 1000003 + ci * 9176 + 7
	var nodes: Array[Node] = []
	_chunks[ci] = nodes

	# Chunk 0 is the tutorial-safe home: one oxygen planet, nothing hostile.
	if ci == 0:
		nodes.append(_make_planet(Vector2.ZERO, Planet.Kind.OXYGEN, 110.0, rng))
		return

	var diff := clampf(float(ci) / PH.RAMP_CHUNKS, 0.0, 1.0)
	var x0 := ci * PH.CHUNK_W
	# The lane opens up over the first few chunks rather than starting wide.
	var band := lerpf(430.0, PH.WORLD_BAND, minf(1.0, float(ci) / 8.0))
	var count := 1 if rng.randf() < 0.62 else 2

	for i in count:
		var pos := Vector2(x0 + rng.randf_range(0.18, 0.86) * PH.CHUNK_W, rng.randf_range(-band, band))
		var r := rng.randf_range(62.0, 135.0)
		if _too_close(pos, r + 200.0):
			continue

		var kind := Planet.Kind.BARREN
		if ci % 2 == 0 and i == 0:
			kind = Planet.Kind.OXYGEN  # guaranteed air every other chunk
		else:
			var roll := rng.randf()
			if roll < 0.34 - 0.10 * diff:
				kind = Planet.Kind.OXYGEN
			elif roll < 0.66:
				kind = Planet.Kind.FUEL
		var p := _make_planet(pos, kind, r, rng)
		nodes.append(p)

		# Moons ride outside the capture ring, so they threaten the approach and
		# the departure rather than the orbit you are parked in.
		var moon_chance := 0.18 + 0.50 * diff
		var cap := p.capture_radius()
		if rng.randf() < moon_chance:
			nodes.append(_make_moon(p, cap + rng.randf_range(45.0, 130.0), rng.randf_range(14.0, 26.0), rng))
		if rng.randf() < moon_chance * 0.35:
			nodes.append(_make_moon(p, cap + rng.randf_range(160.0, 260.0), rng.randf_range(12.0, 22.0), rng))

	if ci >= 3 and rng.randf() < 0.14 + 0.40 * diff:
		var hp := Vector2(x0 + rng.randf_range(0.1, 0.9) * PH.CHUNK_W, rng.randf_range(-band, band))
		if not _too_close(hp, 300.0):
			nodes.append(_make_hole(hp, rng.randf_range(26.0, 46.0), rng))

	if ci >= 2:
		var mcount := int(diff * 3.0) + (1 if rng.randf() < 0.5 else 0)
		for i in mcount:
			var mp := Vector2(x0 + rng.randf() * PH.CHUNK_W, rng.randf_range(-band * 1.15, band * 1.15))
			var vel := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(70.0, 190.0)
			nodes.append(_make_meteor(mp, vel, rng.randf_range(12.0, 24.0), rng))


func _make_planet(pos: Vector2, kind: Planet.Kind, r: float, rng: RandomNumberGenerator) -> Planet:
	var p := Planet.new()
	p.position = pos
	p.theme = theme
	p.z_index = -2
	p.setup(kind, r, rng)
	add_child(p)
	planets.append(p)
	return p


func _make_moon(host: Planet, dist: float, r: float, rng: RandomNumberGenerator) -> Moon:
	var m := Moon.new()
	m.theme = theme
	m.z_index = -1
	m.setup(host, dist, r, rng)
	add_child(m)
	moons.append(m)
	return m


func _make_hole(pos: Vector2, r: float, rng: RandomNumberGenerator) -> BlackHole:
	var h := BlackHole.new()
	h.position = pos
	h.theme = theme
	h.z_index = -3
	h.setup(r, rng)
	add_child(h)
	holes.append(h)
	return h


func _make_meteor(pos: Vector2, vel: Vector2, r: float, rng: RandomNumberGenerator) -> Meteor:
	var m := Meteor.new()
	m.position = pos
	m.theme = theme
	m.z_index = -1
	m.setup(r, vel, rng)
	add_child(m)
	meteors.append(m)
	return m


# --- housekeeping ------------------------------------------------------------

func _too_close(pos: Vector2, clearance: float) -> bool:
	for p in planets:
		if pos.distance_to(p.position) < clearance + p.capture_radius():
			return true
	for h in holes:
		if pos.distance_to(h.position) < clearance + h.influence * 0.45:
			return true
	return false


func _chunk_holds(key: int, node: Node) -> bool:
	return node != null and (_chunks[key] as Array).has(node)


func _free_chunk(key: int) -> void:
	for n in (_chunks[key] as Array):
		if n is Planet:
			planets.erase(n)
		elif n is Moon:
			moons.erase(n)
		elif n is BlackHole:
			holes.erase(n)
		elif n is Meteor:
			meteors.erase(n)
		if is_instance_valid(n):
			n.queue_free()
	# Moons whose planet just went away have nothing to orbit.
	for m in moons.duplicate():
		if not is_instance_valid(m.host):
			moons.erase(m)
			m.queue_free()
