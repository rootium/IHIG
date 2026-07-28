class_name Generator
extends RefCounted
## Builds a level, and does it backwards.
##
## Generating a puzzle and then checking it is solvable means throwing most of
## them away. So instead the solution is what gets built: pick a target, walk
## away from it placing the mirrors that would have brought a beam there, and
## plant a source at the far end. The board is correct the moment it exists,
## and scrambling a few pieces at the end is what makes it a puzzle.
##
## Walking backwards costs nothing, because a mirror that turns a beam
## travelling `a` into one travelling `b` also turns `b` into `a`. The same walk
## runs forwards for splitter branches, which grow away from an existing path.
##
## Two invariants keep independent paths from ruining each other:
##
##   _clear  cells a solution beam passes straight through. Nothing may be
##           placed here, but other beams may cross freely.
##   _used   cells holding a solution tile. Nothing else may touch these at all.
##
## Together they mean a solution beam only ever visits _clear and _used cells,
## so the decoy mirrors and walls scattered through everything else cannot
## affect the solution — they only muddy the *scrambled* board, which is the
## point of them.
##
## Levels are a pure function of their number, so level 40 is the same board for
## everyone. Everything random here draws from a seeded RandomNumberGenerator;
## nothing calls the global RNG, and Array.shuffle() is avoided for that reason.

var _g: Grid
var _rng: RandomNumberGenerator
var _clear: Dictionary = {}    ## cell -> direction of travel through it
var _cross: Dictionary = {}    ## cell -> how many solution beams cross it
var _ctint: Dictionary = {}    ## cell -> colour mask of the beam crossing it
var _used: Dictionary = {}
var _movable: Array[int] = []


## The level numbered `level`. Never returns null: if generation somehow cannot
## find a board it hands back a hand-built one rather than leaving the game
## with nothing to show.
static func build(level: int) -> Grid:
	for attempt in LM.GEN_ATTEMPTS:
		var g := Generator.new()._attempt(level, attempt)
		if g != null:
			return g
	push_warning("Lumen: generation gave up on level %d" % level)
	return _fallback(level)


func _attempt(level: int, salt: int) -> Grid:
	var t := clampf(float(level - 1) / LM.RAMP_LEVELS, 0.0, 1.0)
	var deep := clampf((float(level) - LM.RAMP_LEVELS) / LM.DEEP_LEVELS, 0.0, 1.0)
	_rng = RandomNumberGenerator.new()
	_rng.seed = level * 2654435761 + salt * 40503

	_g = Grid.new(
		LM.GRID_W_MIN + int(t * float(LM.GRID_W_MAX - LM.GRID_W_MIN) + 0.5),
		LM.GRID_H_MIN + int(t * float(LM.GRID_H_MAX - LM.GRID_H_MIN) + 0.5))
	_g.level = level

	var turns := LM.TURNS_MIN + int(t * LM.TURNS_SPAN + 0.5) + int(deep * LM.TURNS_DEEP)
	var colored := t >= LM.COLOR_AT
	var rotate := _rng.randi() % 3  # so early colour levels are not always red

	# Order here is deliberate, and the soak test is what found it. Mixes and
	# splitters both need to graft onto an existing path, and both need room to
	# do it — so they go second, while there is still space. Carving every
	# independent path first fills the board and quietly starves the two
	# features that make a level interesting rather than merely long.
	var first := _add_path(LM.WHITE if not colored else _channel(rotate), turns)
	if first < 0:
		return null

	# A target fed by two colours at once. This is the one rule the game is
	# really about, so it gets its own path rather than emerging by luck.
	if colored and t >= LM.MIX_AT and _rng.randf() < LM.MIX_CHANCE + deep * 0.4:
		_add_mix(first, _spare_channel(int(_g.tint[first])), maxi(1, turns - 1))

	if t >= LM.SPLIT_AT:
		for i in 1 + int(deep * LM.SPLITS_DEEP):
			if _rng.randf() < LM.SPLIT_CHANCE + deep * 0.4:
				_add_split(maxi(1, turns - 1))

	for i in range(1, LM.PATHS_MIN + int(t * LM.PATHS_SPAN + 0.35) + int(deep * LM.PATHS_DEEP)):
		_add_path(LM.WHITE if not colored else _channel(rotate + i), turns)

	if _movable.is_empty():
		return null  # nothing to tap is not a puzzle
	_decorate(t)

	# The board was constructed to be solved, but say so with the same tracer
	# the game renders through rather than on the strength of the construction.
	if not Beam.solved(_g, Beam.trace(_g).recv):
		return null

	_g.solution = _g.orient.duplicate()
	_g.movable = _movable
	# A little jitter so consecutive levels are not visibly the same sum.
	_g.par = _scramble(1 + int(t * LM.SCRAMBLE_SPAN) + int(deep * LM.SCRAMBLE_DEEP)
		+ (1 if _rng.randf() < 0.35 else 0))
	_g.start = _g.orient.duplicate()
	return _g


# --- paths -------------------------------------------------------------------

## Walks a beam across the board, alternating straight runs with turns, and
## reports the cells it needs without touching the grid — so a path that runs
## out of room costs nothing to abandon.
##
## Forwards, the beam leaves `start` travelling `dir`. Backwards, it arrives at
## `start` travelling `dir` and we retrace where it came from. The mirrors are
## the same either way.
##
## Returns {} on failure, else {cell, dir, line, pieces}, where `cell`/`dir` are
## where the walk ran out of turns — the caller decides what goes there.
func _walk(start: int, dir: int, turns: int, backward: bool) -> Dictionary:
	var pos := start
	var d := dir
	var line: Array[int] = []   ## packed cell * 4 + travel direction
	var pieces := {}            ## cell -> orientation

	for turn in turns + 1:
		var run := _rng.randi_range(LM.RUN_MIN, LM.RUN_MAX)
		var moved := 0
		for s in run:
			var nxt := _g.step(pos, ((d + 2) & 3) if backward else d)
			# Crossing another beam's clear cell is fine. Landing on any placed
			# tile is not.
			if nxt < 0 or _used.has(nxt) or pieces.has(nxt):
				break
			pos = nxt
			line.push_back((nxt << 2) | d)
			moved += 1
		if moved == 0:
			return {}

		# Whatever we stopped on takes a tile, so it stops being a clear cell.
		line.remove_at(line.size() - 1)
		if _used.has(pos) or _clear.has(pos) or pieces.has(pos) or _line_has(line, pos):
			return {}
		if turn == turns:
			return {"cell": pos, "dir": d, "line": line, "pieces": pieces}

		var nd := d ^ (3 if _rng.randf() < 0.5 else 1)
		pieces[pos] = Grid.orient_for(d, nd)
		d = nd
	return {}


func _commit(plan: Dictionary, tint: int) -> void:
	for packed in plan.line:
		var cell: int = packed >> 2
		_clear[cell] = packed & 3
		_cross[cell] = int(_cross.get(cell, 0)) + 1
		_ctint[cell] = int(_ctint.get(cell, 0)) | tint
	for cell in plan.pieces:
		_g.kind[cell] = Grid.Kind.MIRROR
		_g.orient[cell] = plan.pieces[cell]
		_used[cell] = true
		_movable.push_back(cell)


## A target somewhere on the board, fed by a source somewhere else.
## Returns the target's cell, or -1 if no room could be found for one.
func _add_path(tint: int, turns: int) -> int:
	for attempt in LM.PATH_ATTEMPTS:
		var target := _free_cell()
		if target < 0:
			return -1
		_used[target] = true
		var plan := _walk(target, _rng.randi() & 3, turns, true)
		if plan.is_empty():
			_used.erase(target)
			continue
		_commit(plan, tint)
		_place(target, Grid.Kind.TARGET, 0, tint)
		_place(plan.cell, Grid.Kind.SOURCE, plan.dir, tint)
		return target
	return -1


## A second source of a different colour into a target that already has one.
## The target then demands the mix of the two, which no single beam can supply.
func _add_mix(target: int, tint: int, turns: int) -> bool:
	for attempt in LM.PATH_ATTEMPTS:
		var plan := _walk(target, _rng.randi() & 3, turns, true)
		if plan.is_empty():
			continue
		_commit(plan, tint)
		_place(plan.cell, Grid.Kind.SOURCE, plan.dir, tint)
		_g.tint[target] |= tint
		return true
	return false


## Turns one cell of a finished path into a splitter and grows a branch to a new
## target. A splitter passes light straight through, so the path it is dropped
## onto keeps working untouched — only the new branch depends on which way the
## splitter faces, and that is what the player has to get right.
##
## Only cells crossed by exactly one beam qualify: on a crossing, the splitter
## would fire a branch for each beam and there is no single colour to ask for.
func _add_split(turns: int) -> bool:
	var options: Array[int] = []
	for cell in _clear:
		if int(_cross[cell]) == 1:
			options.push_back(cell)
	_shuffle(options)

	for cell in options:
		var through: int = _clear[cell]
		var o := _rng.randi() & 1
		var plan := _walk(cell, Grid.reflect(through, o), turns, false)
		if plan.is_empty():
			continue
		var tint: int = _ctint[cell]
		_clear.erase(cell)
		_place(cell, Grid.Kind.SPLITTER, o, 0)
		_movable.push_back(cell)
		_commit(plan, tint)
		_place(plan.cell, Grid.Kind.TARGET, 0, tint)
		return true
	return false


func _place(cell: int, kind: Grid.Kind, orient: int, tint: int) -> void:
	_g.kind[cell] = kind
	_g.orient[cell] = orient
	_g.tint[cell] = tint
	_used[cell] = true


# --- dressing ----------------------------------------------------------------

## Fills the cells no solution beam can reach with mirrors and walls.
##
## The mirrors are decoys: with the board solved they sit in the dark and do
## nothing. With it scrambled they are exactly what a stray beam bounces off,
## which is the mess the player is untangling — and it teaches the one habit
## that matters, which is to follow the light rather than fiddle with pieces.
func _decorate(t: float) -> void:
	var spare: Array[int] = []
	for cell in _g.size():
		if _g.kind[cell] == Grid.Kind.EMPTY and not _clear.has(cell):
			spare.push_back(cell)
	_shuffle(spare)

	var decoys := mini(LM.DECOY_MIN + int(t * LM.DECOY_SPAN), spare.size())
	for i in decoys:
		_g.kind[spare[i]] = Grid.Kind.MIRROR
		_g.orient[spare[i]] = _rng.randi() & 1
	var walls := mini(LM.WALL_MIN + int(t * LM.WALL_SPAN), spare.size() - decoys)
	for i in walls:
		_g.kind[spare[decoys + i]] = Grid.Kind.WALL


## Knocks `want` pieces out of true and returns how many it took — the level's
## par. Only pieces the solution depends on count, since turning a decoy is a
## wasted tap by definition, and there may be fewer of them than asked for.
func _scramble(want: int) -> int:
	var order := _movable.duplicate()
	_shuffle(order)
	var flips := clampi(want, 1, order.size())
	for i in flips:
		_g.orient[order[i]] ^= 1
	# Rare, but two wrongs can still light the board. Keep flipping until the
	# level is actually a level.
	while flips < order.size() and Beam.solved(_g, Beam.trace(_g).recv):
		_g.orient[order[flips]] ^= 1
		flips += 1
	return flips


# --- helpers -----------------------------------------------------------------

func _free_cell() -> int:
	for attempt in 24:
		var cell := _rng.randi() % _g.size()
		if not _used.has(cell) and not _clear.has(cell):
			return cell
	return -1


func _channel(i: int) -> int:
	return [LM.R, LM.G, LM.B][i % 3]


## A channel `mask` does not already contain, so mixing always changes the
## colour a target is asking for.
func _spare_channel(mask: int) -> int:
	var open: Array[int] = []
	for c in [LM.R, LM.G, LM.B]:
		if not (mask & c):
			open.push_back(c)
	if open.is_empty():
		return LM.R
	return open[_rng.randi() % open.size()]


func _line_has(line: Array[int], cell: int) -> bool:
	for packed in line:
		if packed >> 2 == cell:
			return true
	return false


## Seeded Fisher-Yates. Array.shuffle() draws from the global RNG, which would
## make levels differ between devices.
func _shuffle(a: Array[int]) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := a[i]
		a[i] = a[j]
		a[j] = tmp


## A board that cannot fail to generate, for the case where everything else did.
## One mirror, turned the wrong way.
static func _fallback(level: int) -> Grid:
	var g := Grid.new(5, 5)
	var src := g.cell_at(0, 4)
	var mirror := g.cell_at(4, 4)
	var target := g.cell_at(4, 0)
	g.kind[src] = Grid.Kind.SOURCE
	g.orient[src] = Grid.E
	g.tint[src] = LM.WHITE
	g.kind[mirror] = Grid.Kind.MIRROR
	g.orient[mirror] = Grid.orient_for(Grid.E, Grid.N)
	g.kind[target] = Grid.Kind.TARGET
	g.tint[target] = LM.WHITE
	g.level = level
	g.solution = g.orient.duplicate()
	g.movable = [mirror]
	g.orient[mirror] ^= 1
	g.start = g.orient.duplicate()
	g.par = 1
	return g
