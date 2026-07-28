class_name Beam
extends RefCounted
## Traces every beam on a Grid. The single source of truth for what the board
## is doing: the renderer draws what this returns, the win check reads what this
## returns, and the generator validates its own levels through it.
##
## `trace()` returns two dictionaries:
##
##   lit   (cell * 4 + dir) -> colour mask, for every beam crossing every cell
##   recv  cell -> colour mask, for targets only
##
## The state a beam has at a point is the *set* of colours reaching it, so the
## walk merges rather than overwrites: a key is re-followed only when it picks
## up a channel it did not already carry. Each key holds at most three bits and
## bits are only ever added, so the walk cannot loop forever even though the
## board can — a beam that circles between four mirrors simply stops adding
## anything and dies out.

## A queue entry packs a cell (bits 5+), a direction (bits 3-4) and a colour
## mask (bits 0-2) into one int, which keeps the frontier a flat Array[int].
static func _push(queue: Array[int], cell: int, dir: int, mask: int) -> void:
	if cell >= 0:
		queue.push_back((((cell << 2) | dir) << 3) | mask)


static func trace(g: Grid) -> Dictionary:
	var lit := {}
	var recv := {}
	var queue: Array[int] = []

	for i in g.size():
		if g.kind[i] == Grid.Kind.SOURCE:
			var d := int(g.orient[i])
			_push(queue, g.step(i, d), d, int(g.tint[i]))

	while not queue.is_empty():
		var packed: int = queue.pop_back()
		var key := packed >> 3
		var had: int = lit.get(key, 0)
		var mask := had | (packed & 7)
		if mask == had:
			continue
		lit[key] = mask

		var cell := key >> 2
		var dir := key & 3
		match g.kind[cell]:
			Grid.Kind.EMPTY:
				_push(queue, g.step(cell, dir), dir, mask)
			Grid.Kind.MIRROR:
				var nd := Grid.reflect(dir, g.orient[cell])
				_push(queue, g.step(cell, nd), nd, mask)
			Grid.Kind.SPLITTER:
				# Half carries straight on, half turns. The straight half is why
				# a splitter can be dropped onto a finished path without
				# disturbing it, and the turning half is what the player aims.
				var sd := Grid.reflect(dir, g.orient[cell])
				_push(queue, g.step(cell, dir), dir, mask)
				_push(queue, g.step(cell, sd), sd, mask)
			Grid.Kind.TARGET:
				recv[cell] = int(recv.get(cell, 0)) | mask
			_:
				pass  # Walls and sources absorb.

	return {"lit": lit, "recv": recv}


## Targets must receive exactly what they ask for. Exact rather than "at least"
## is the rule that gives mixing its teeth: spraying every colour at a target
## that wants green is a failure, not a shortcut.
static func solved(g: Grid, recv: Dictionary) -> bool:
	for i in g.size():
		if g.kind[i] == Grid.Kind.TARGET and int(recv.get(i, 0)) != int(g.tint[i]):
			return false
	return true
