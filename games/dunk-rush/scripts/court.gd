class_name Court
extends Node2D
## The endless court, climbing upward (-Y) in fixed-height chunks.
##
## Chunk `ci` owns exactly one hoop, sitting on its top edge at y = -ci*CHUNK_H,
## and whatever hazards fill the space below it. That layout is deliberate: the
## hazards of a chunk are the ones you fly *through* on the way to its rim, so
## generation and difficulty read the same way the player experiences them.
##
## Each chunk is seeded from (world_seed, chunk index) so it regenerates
## identically, and chunks well below the player are freed. Difficulty ramps
## with the chunk index, but nothing hostile spawns below BD.SAFE_CHUNKS, so
## every run opens with room to learn the jump.

var hoops: Array[Hoop] = []
var defenders: Array[Defender] = []
var loose: Array[LooseBall] = []
var golds: Array[GoldBall] = []

var theme: Dictionary = {}
var world_seed: int = 0

var _chunks: Dictionary = {}     ## chunk index -> Array[Node]
var _last_x: float = 0.0         ## column of the most recently placed hoop
var _zig: float = 1.0            ## which way the next hoop steps


func reset(p_seed: int, p_theme: Dictionary) -> void:
	for key in _chunks.keys():
		_free_chunk(key)
	_chunks.clear()
	hoops.clear()
	defenders.clear()
	loose.clear()
	golds.clear()
	world_seed = p_seed
	theme = p_theme
	_last_x = 0.0
	_zig = 1.0 if (p_seed & 1) == 0 else -1.0


## `height` is how far up the player has climbed, i.e. -position.y.
func ensure(height: float, protect: Hoop = null) -> void:
	var ci := int(floor(height / BD.CHUNK_H))
	for i in range(maxi(0, ci - BD.CHUNKS_BEHIND), ci + BD.CHUNKS_AHEAD + 1):
		if not _chunks.has(i):
			_gen_chunk(i)
	for key in _chunks.keys():
		if key < ci - BD.CHUNKS_BEHIND - 1 and not _chunk_holds(key, protect):
			_free_chunk(key)
			_chunks.erase(key)


## Everything the player can collide with is stepped from here rather than from
## its own _process, so the court and the player advance on exactly one clock —
## which is what lets the headless test run at a fixed step and mean something.
func step(delta: float) -> void:
	for h in hoops:
		h.step(delta)
	for d in defenders:
		d.step(delta)
	for b in loose:
		b.step(delta)


# --- flight ------------------------------------------------------------------

## Advances one point of flight by `dt` and resolves everything it can hit.
##
## Real flight and the aim preview both run through here, which is what makes
## the dotted line a promise rather than an estimate: a line that banks off the
## glass is a bank the player will get, and a line that ends on the iron is a
## clang they can see coming and re-aim away from.
func advance(f: Flight, dt: float, grav_mult: float, steer_x: float) -> void:
	f.scored_on = null
	f.hit_iron = null
	var prev := f.pos
	f.vel = Baller.step_velocity(f.vel, dt, grav_mult, steer_x)
	f.pos += f.vel * dt
	_bounce_off_boards(f)
	f.scored_on = dunk_through(prev, f.pos)
	if f.scored_on == null:
		f.hit_iron = rim_contact(f.pos, BD.BALLER_R)


## Backboards deflect rather than kill, which makes them a route as much as an
## obstacle: bank off one and you can drop into a rim no clean arc could reach.
func _bounce_off_boards(f: Flight) -> void:
	for h in hoops:
		var r := h.board_rect()
		var closest := Vector2(clampf(f.pos.x, r.position.x, r.end.x),
				clampf(f.pos.y, r.position.y, r.end.y))
		var away := f.pos - closest
		var dist := away.length()
		if dist >= BD.BALLER_R:
			continue
		# Dead centre inside the board: push out the way we came in.
		var n: Vector2 = (away / dist) if dist > 0.01 else Vector2(-h.side, 0.0)
		f.pos = closest + n * (BD.BALLER_R + 0.5)
		f.vel = (f.vel - 2.0 * n * f.vel.dot(n)) * BD.BOARD_BOUNCE
		f.banked = true
		return


# --- collision queries -------------------------------------------------------

## The hoop that a move from `prev` to `now` dunks through, if any.
##
## Real flight and the aim preview both call this, so the two can never disagree
## about what counts as a score. Crossing is tested against the rim plane rather
## than by proximity, so a fast jump cannot tunnel through a basket.
func dunk_through(prev: Vector2, now: Vector2) -> Hoop:
	if now.y <= prev.y:
		return null  # must be on the way down
	for h in hoops:
		var y := h.position.y
		if prev.y > y or now.y < y:
			continue
		var t := (y - prev.y) / maxf(now.y - prev.y, 0.0001)
		if absf(lerpf(prev.x, now.x, t) - h.position.x) <= h.score_half():
			return h
	return null


## The hoop whose iron a circle at `pos` is touching.
##
## The scoring band is skipped rather than tested: that part of a hoop is the
## hole, not the iron. Without that exemption a player lined up dead centre
## trips this check on the frame *before* they cross the rim plane — they are
## within a body radius of a rim they are about to drop cleanly through — and a
## perfect dunk gets stolen and called a clang.
func rim_contact(pos: Vector2, radius: float) -> Hoop:
	for h in hoops:
		if absf(pos.x - h.position.x) <= h.score_half():
			continue
		if pos.distance_to(h.rim_closest_point(pos)) < radius:
			return h
	return null


func take_gold(g: GoldBall) -> void:
	golds.erase(g)
	for key in _chunks.keys():
		(_chunks[key] as Array).erase(g)
	g.queue_free()


# --- generation --------------------------------------------------------------

func _gen_chunk(ci: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 1000003 + ci * 9176 + 7
	var nodes: Array[Node] = []
	_chunks[ci] = nodes

	# Chunk 0 is the home basket: dead centre, full-width rim, nothing else.
	if ci == 0:
		nodes.append(_make_hoop(Vector2.ZERO, BD.RIM_HALF, 1.0, 0.0, 0.0, rng))
		_last_x = 0.0
		return

	var diff := clampf(float(ci) / BD.RAMP_CHUNKS, 0.0, 1.0)
	var safe := ci < BD.SAFE_CHUNKS
	var y := -float(ci) * BD.CHUNK_H

	var hoop := _place_hoop(nodes, y, rng, diff)

	if not safe:
		_place_defenders(nodes, ci, y, rng, diff)
		_place_loose(nodes, y, rng, diff)
	_place_golds(nodes, hoop, y, rng)


## Hoops zigzag: each one steps sideways from the last, turning around at the
## edge of the column. A fixed step length is what keeps the climb evenly paced,
## and the turn is what stops a run drifting into one wall and staying there.
func _place_hoop(nodes: Array[Node], y: float, rng: RandomNumberGenerator, diff: float) -> Hoop:
	var step_x := rng.randf_range(BD.STEP_MIN, BD.STEP_MAX)
	var x := _last_x + _zig * step_x
	if absf(x) > BD.COURT_BAND:
		_zig = -_zig
		x = _last_x + _zig * step_x
	x = clampf(x, -BD.COURT_BAND, BD.COURT_BAND)

	var rim_half := lerpf(BD.RIM_HALF, BD.RIM_HALF_MIN, diff)
	# The backboard goes on the outward side, so banking off it always sends you
	# back toward the middle of the court rather than out of bounds.
	var side := 1.0 if x >= 0.0 else -1.0

	var slide := 0.0
	var span := 0.0
	if rng.randf() < 0.10 + 0.45 * diff:
		slide = rng.randf_range(BD.SLIDE_SPEED_MIN, BD.SLIDE_SPEED_MAX)
		# Keep the whole travel inside the column.
		span = minf(rng.randf_range(60.0, 150.0), BD.COURT_BAND - absf(x))
		if span < 30.0:
			slide = 0.0
			span = 0.0

	_last_x = x
	return _make_hoop(Vector2(x, y), rim_half, side, slide, span, rng)


## Defenders patrol the gap *below* a rim — the space you rise through on the
## way to it — rather than level with the rim itself. A hazard parked on the
## basket would just be a wall.
func _place_defenders(nodes: Array[Node], ci: int, y: float, rng: RandomNumberGenerator,
		diff: float) -> void:
	var count := int(diff * 1.8) + (1 if rng.randf() < 0.30 + 0.35 * diff else 0)
	for i in count:
		var dy := y + BD.CHUNK_H * rng.randf_range(0.32, 0.72)
		var cx := clampf(rng.randf_range(-BD.COURT_BAND, BD.COURT_BAND) * 0.85,
				-BD.COURT_BAND, BD.COURT_BAND)
		var pos := Vector2(cx, dy)
		if _too_close(pos, 150.0):
			continue
		var d := Defender.new()
		d.position = pos
		d.theme = theme
		d.z_index = -1
		d.setup(rng.randf_range(19.0, 26.0),
				rng.randf_range(90.0, 220.0),
				rng.randf_range(70.0, 150.0), rng)
		add_child(d)
		defenders.append(d)
		nodes.append(d)


func _place_loose(nodes: Array[Node], y: float, rng: RandomNumberGenerator, diff: float) -> void:
	for i in int(diff * 2.2) + (1 if rng.randf() < 0.28 else 0):
		var pos := Vector2(rng.randf_range(-BD.COURT_BAND, BD.COURT_BAND) * 1.25,
				y + BD.CHUNK_H * rng.randf())
		if _too_close(pos, 120.0):
			continue
		var vel := Vector2(rng.randf_range(70.0, 175.0) * (1.0 if rng.randf() < 0.5 else -1.0),
				rng.randf_range(-45.0, 45.0))
		var b := LooseBall.new()
		b.position = pos
		b.theme = theme
		b.z_index = -1
		b.setup(rng.randf_range(12.0, 19.0), vel, rng)
		add_child(b)
		loose.append(b)
		nodes.append(b)


## Gold sits off the straight line between rims, so collecting it is a decision
## rather than something that happens to you on the way past.
func _place_golds(nodes: Array[Node], hoop: Hoop, y: float, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(1, 3):
		var pos := Vector2(clampf(hoop.position.x + rng.randf_range(-330.0, 330.0),
				-BD.COURT_BAND * 1.1, BD.COURT_BAND * 1.1),
				y + BD.CHUNK_H * rng.randf_range(0.15, 0.9))
		if _too_close(pos, 80.0):
			continue
		var g := GoldBall.new()
		g.position = pos
		g.theme = theme
		g.z_index = -1
		add_child(g)
		golds.append(g)
		nodes.append(g)


func _make_hoop(pos: Vector2, rim_half: float, side: float, slide: float, span: float,
		rng: RandomNumberGenerator) -> Hoop:
	var h := Hoop.new()
	h.position = pos
	h.theme = theme
	h.z_index = -2
	h.setup(rim_half, side, slide, span, rng)
	add_child(h)
	hoops.append(h)
	return h


# --- housekeeping ------------------------------------------------------------

func _too_close(pos: Vector2, clearance: float) -> bool:
	for h in hoops:
		if pos.distance_to(h.position) < clearance + h.rim_half:
			return true
	for d in defenders:
		if pos.distance_to(d.position) < clearance:
			return true
	return false


func _chunk_holds(key: int, node: Node) -> bool:
	# is_instance_valid() rather than a null check: a freed Node compares equal
	# to null in GDScript, and an already-freed hoop protects nothing anyway.
	return is_instance_valid(node) and (_chunks[key] as Array).has(node)


func _free_chunk(key: int) -> void:
	for n in (_chunks[key] as Array):
		if n is Hoop:
			hoops.erase(n)
		elif n is Defender:
			defenders.erase(n)
		elif n is LooseBall:
			loose.erase(n)
		elif n is GoldBall:
			golds.erase(n)
		if is_instance_valid(n):
			n.queue_free()
