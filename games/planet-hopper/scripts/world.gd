class_name World
extends Node2D
## Endless procedural space, climbing upward (-Y) in fixed-height chunks.
##
## Each chunk is seeded from (world_seed, chunk index) so it regenerates
## identically, and chunks well below the ship are freed. Difficulty ramps with
## the chunk index, but nothing hostile spawns below PH.SAFE_CHUNKS, so the
## opening of every run is a place to learn the controls.
##
## Planets are placed relative to the previous one's column rather than
## anywhere in the band, which keeps consecutive hops within comfortable reach.

var planets: Array[Planet] = []
var moons: Array[Moon] = []
var holes: Array[BlackHole] = []
var meteors: Array[Meteor] = []
var stars: Array[StarPickup] = []

var theme: Dictionary = {}
var world_seed: int = 0

var _chunks: Dictionary = {}     ## chunk index -> Array[Node]
var _last_x: float = 0.0         ## column of the most recently placed planet


func reset(p_seed: int, p_theme: Dictionary) -> void:
	for key in _chunks.keys():
		_free_chunk(key)
	_chunks.clear()
	planets.clear()
	moons.clear()
	holes.clear()
	meteors.clear()
	stars.clear()
	world_seed = p_seed
	theme = p_theme
	_last_x = 0.0


## `height` is how far up the ship has climbed, i.e. -position.y.
func ensure(height: float, protect: Planet = null) -> void:
	var ci := int(floor(height / PH.CHUNK_H))
	for i in range(maxi(0, ci - PH.CHUNKS_BEHIND), ci + PH.CHUNKS_AHEAD + 1):
		if not _chunks.has(i):
			_gen_chunk(i)
	for key in _chunks.keys():
		if key < ci - PH.CHUNKS_BEHIND - 1 and not _chunk_holds(key, protect):
			_free_chunk(key)
			_chunks.erase(key)


# --- physics queries ---------------------------------------------------------

## Gravity at a point. `exclude` is the planet the ship most recently launched
## from: suppressing it is what turns a hop into a clean arc rather than a
## decaying spiral back to where you started. Ship flight and the on-screen
## trajectory preview both call this, so the two can never disagree.
func gravity_at(pos: Vector2, exclude: Planet = null) -> Vector2:
	var acc := Vector2.ZERO
	for b in planets:
		if b == exclude:
			continue
		acc += _pull(pos, b.position, b.mass, b.influence)
	for h in holes:
		acc += _pull(pos, h.position, h.mass, h.influence)
	return acc


func _pull(pos: Vector2, at: Vector2, mass: float, influence: float) -> Vector2:
	var d := at - pos
	var dist := d.length()
	if dist < 1.0 or dist > influence:
		return Vector2.ZERO
	return (d / dist) * minf(PH.GRAV * mass / (dist * dist), PH.MAX_GRAV_ACCEL)


## The planet whose capture ring contains `pos`, if any.
func capture_candidate(pos: Vector2, exclude: Planet = null) -> Planet:
	for p in planets:
		if p == exclude:
			continue
		if pos.distance_to(p.position) <= p.capture_radius():
			return p
	return null


# --- generation --------------------------------------------------------------

func _gen_chunk(ci: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 1000003 + ci * 9176 + 7
	var nodes: Array[Node] = []
	_chunks[ci] = nodes

	# Chunk 0 is home: one green planet at the origin, nothing else.
	if ci == 0:
		nodes.append(_make_planet(Vector2.ZERO, Planet.Kind.OXYGEN, 105.0, rng))
		_last_x = 0.0
		return

	var diff := clampf(float(ci) / PH.RAMP_CHUNKS, 0.0, 1.0)
	var safe := ci < PH.SAFE_CHUNKS
	var top := -float(ci) * PH.CHUNK_H

	# One planet per chunk. Chunk height and the sideways step are what set the
	# length of a hop, so keeping the count fixed keeps the climb evenly paced —
	# and a chunk that came out empty would leave a gap no hop could cross, so
	# the fallback relaxes spacing rather than skipping.
	if not _place_planet(nodes, ci, rng, diff, safe, 6, false):
		_place_planet(nodes, ci, rng, diff, safe, 14, true)

	if not safe and rng.randf() < 0.08 + 0.30 * diff:
		var hp := Vector2(rng.randf_range(-PH.WORLD_BAND, PH.WORLD_BAND), top - rng.randf() * PH.CHUNK_H)
		if not _too_close(hp, 340.0):
			nodes.append(_make_hole(hp, rng.randf_range(24.0, 40.0), rng))

	if not safe:
		for i in int(diff * 2.5) + (1 if rng.randf() < 0.35 else 0):
			var mp := Vector2(rng.randf_range(-PH.WORLD_BAND * 1.3, PH.WORLD_BAND * 1.3), top - rng.randf() * PH.CHUNK_H)
			# Mostly sideways drift, so meteors sweep across the climb.
			var vel := Vector2(rng.randf_range(60.0, 150.0) * (1.0 if rng.randf() < 0.5 else -1.0),
					rng.randf_range(-40.0, 40.0))
			nodes.append(_make_meteor(mp, vel, rng.randf_range(12.0, 22.0), rng))

	for i in rng.randi_range(1, 3):
		var sp := Vector2(clampf(_last_x + rng.randf_range(-320.0, 320.0), -PH.WORLD_BAND, PH.WORLD_BAND),
				top - rng.randf() * PH.CHUNK_H)
		if not _too_close(sp, 90.0):
			nodes.append(_make_star(sp))


## Tries to drop one planet into a chunk, retrying a few positions before
## giving up. `relaxed` drops the spacing requirement almost entirely and is
## only used as a last resort to keep a chunk from coming out empty.
func _place_planet(nodes: Array[Node], ci: int, rng: RandomNumberGenerator, diff: float,
		safe: bool, attempts: int, relaxed: bool) -> bool:
	var top := -float(ci) * PH.CHUNK_H
	var clearance := 40.0 if relaxed else 150.0
	for a in attempts:
		# Step sideways from the previous column so the next hop stays reachable,
		# and keep the vertical position mid-chunk so gaps stay predictable.
		var x := clampf(_last_x + rng.randf_range(-360.0, 360.0), -PH.WORLD_BAND, PH.WORLD_BAND)
		var y := top - rng.randf_range(0.25, 0.75) * PH.CHUNK_H
		var pos := Vector2(x, y)
		var r := rng.randf_range(66.0, 128.0)
		if _too_close(pos, r + clearance):
			continue

		var kind := Planet.Kind.BARREN
		if ci % 2 == 0:
			kind = Planet.Kind.OXYGEN  # guaranteed air every other chunk
		else:
			# Odd chunks lean amber and barren. The guaranteed green on every
			# even chunk already covers survival, so this is what keeps the
			# climb from turning into a column of identical green worlds.
			var roll := rng.randf()
			if roll < 0.16 - 0.06 * diff:
				kind = Planet.Kind.OXYGEN
			elif roll < 0.62:
				kind = Planet.Kind.FUEL

		var p := _make_planet(pos, kind, r, rng)
		nodes.append(p)
		_last_x = x

		# Moons ride outside the capture ring, so they threaten the approach and
		# the departure rather than the orbit you are parked in.
		if not safe and rng.randf() < 0.10 + 0.42 * diff:
			var cap := p.capture_radius()
			nodes.append(_make_moon(p, cap + rng.randf_range(55.0, 140.0), rng.randf_range(14.0, 24.0), rng))
		return true
	return false


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


func _make_star(pos: Vector2) -> StarPickup:
	var s := StarPickup.new()
	s.position = pos
	s.theme = theme
	s.z_index = -1
	add_child(s)
	stars.append(s)
	return s


func take_star(s: StarPickup) -> void:
	stars.erase(s)
	for key in _chunks.keys():
		(_chunks[key] as Array).erase(s)
	s.queue_free()


# --- housekeeping ------------------------------------------------------------

func _too_close(pos: Vector2, clearance: float) -> bool:
	for p in planets:
		if pos.distance_to(p.position) < clearance + p.capture_radius():
			return true
	for h in holes:
		if pos.distance_to(h.position) < clearance + h.influence * 0.4:
			return true
	return false


func _chunk_holds(key: int, node: Node) -> bool:
	# is_instance_valid() rather than a null check: a freed Node compares equal
	# to null in GDScript, and an already-freed planet protects nothing anyway.
	return is_instance_valid(node) and (_chunks[key] as Array).has(node)


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
		elif n is StarPickup:
			stars.erase(n)
		if is_instance_valid(n):
			n.queue_free()
	# Moons whose planet just went away have nothing to orbit.
	for m in moons.duplicate():
		if not is_instance_valid(m.host):
			moons.erase(m)
			m.queue_free()
