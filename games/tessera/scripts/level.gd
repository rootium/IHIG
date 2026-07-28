class_name Level
extends RefCounted

## A chamber, and the text format it is authored in.
##
## Writing 4D geometry as a list of corner pairs is not something a person can
## do twice without going mad, so chambers are written as a stack of ASCII
## layers instead — one grid per (y, w) pair, rows running along z and columns
## along x:
##
##   name: Threshold
##   hint: Q and E step along the axis you cannot see.
##   rot: zw
##   size: 9 3 9 2
##   --- y0 w0
##   #########
##   #S..#..G#
##   #########
##   --- y1 w0
##   .........
##
## Layers that are not listed are empty. Cells are then merged greedily into
## the largest 4D boxes they will form, which is both far fewer draw calls and
## a better look: the chambers read as architecture rather than as voxels.

const GLYPHS := {
	"#": Cfg.Kind.SOLID,
	"^": Cfg.Kind.HAZARD,
	"*": Cfg.Kind.SHARD,
	"~": Cfg.Kind.FIELD,
	"G": Cfg.Kind.GOAL,
}
## Doors 1-4 and their keys a-d.
const DOOR_GLYPHS := "1234"
const KEY_GLYPHS := "abcd"

var name := "Chamber"
var stratum := 1
var hint := ""
var size := Vector4i(8, 4, 8, 2)
var start := Vector4i(1, 1, 1, 0)
var allow_zw := true
var allow_xw := false
var par := 0
var shard_total := 0
## Array of Dictionary: {lo: Vector4, hi: Vector4, kind: int, hue: int}
var blocks: Array = []
## Cell lookup for movement, keyed by Vector4i.
var cells := {}
## Bounds of the cells that actually exist. A chamber is carved out of a much
## larger block, so its declared size says almost nothing about how much room
## the camera needs.
var content_lo := Vector4i.ZERO
var content_hi := Vector4i.ONE
var _shell: Array = []
var _surface_cache := {}


static func parse(text: String) -> Level:
	var lv := Level.new()
	var grids := {}          # Vector2i(y, w) -> Array[String]
	var cur := Vector2i(-1, -1)
	var rows: Array = []

	for raw in text.split("\n"):
		var line := raw.rstrip(" \t\r")
		if line.begins_with("#!") or line.is_empty() and cur.x < 0:
			continue
		if line.begins_with("---"):
			if cur.x >= 0:
				grids[cur] = rows
			var parts := line.substr(3).strip_edges().split(" ", false)
			var y := 0
			var w := 0
			for p in parts:
				if p.begins_with("y"):
					y = int(p.substr(1))
				elif p.begins_with("w"):
					w = int(p.substr(1))
			cur = Vector2i(y, w)
			rows = []
			continue
		if cur.x >= 0:
			rows.append(line)
			continue

		var colon := line.find(":")
		if colon < 0:
			continue
		var key := line.substr(0, colon).strip_edges()
		var val := line.substr(colon + 1).strip_edges()
		match key:
			"name": lv.name = val
			"hint": lv.hint = val
			"par": lv.par = int(val)
			"stratum": lv.stratum = int(val)
			"rot":
				lv.allow_zw = val == "zw" or val == "both"
				lv.allow_xw = val == "xw" or val == "both"
			"size":
				var n := val.split(" ", false)
				if n.size() >= 4:
					lv.size = Vector4i(int(n[0]), int(n[1]), int(n[2]), int(n[3]))

	if cur.x >= 0:
		grids[cur] = rows

	lv._build(grids)
	return lv


func _build(grids: Dictionary) -> void:
	var typed := {}   # Vector4i -> [kind, hue]
	for yw in grids:
		var y: int = yw.x
		var w: int = yw.y
		var rows: Array = grids[yw]
		for z in rows.size():
			var row: String = rows[z]
			for x in row.length():
				var ch := row[x]
				if ch == "." or ch == " ":
					continue
				var cell := Vector4i(x, y, z, w)
				if ch == "S":
					start = cell
					continue
				if GLYPHS.has(ch):
					typed[cell] = [GLYPHS[ch], 0]
					if GLYPHS[ch] == Cfg.Kind.SHARD:
						shard_total += 1
					continue
				var di := DOOR_GLYPHS.find(ch)
				if di >= 0:
					typed[cell] = [Cfg.Kind.DOOR, di]
					continue
				var ki := KEY_GLYPHS.find(ch)
				if ki >= 0:
					typed[cell] = [Cfg.Kind.KEY, ki]

	cells = typed
	_measure()
	_shell = _find_shell()
	blocks = surface(0b1101)   # a sane default before the first slice


## Cells that could ever be drawn, in any orientation: a solid cell buried on
## all four axes never presents a face whichever way the player is facing.
## A late chamber is six thousand cells and a few hundred of them are surface,
## so doing this once turns every per-orientation pass from a full sweep of the
## rock into a sweep of its skin.
func _find_shell() -> Array:
	var out: Array = []
	for key in cells:
		var c: Vector4i = key
		if cells[c][0] != Cfg.Kind.SOLID:
			out.append(c)
			continue
		var exposed := false
		for a in 4:
			for sgn in [-1, 1]:
				var n: Vector4i = c
				n[a] += sgn
				if not _is_rock(n):
					exposed = true
					break
			if exposed:
				break
		if exposed:
			out.append(c)
	return out


func _measure() -> void:
	var first := true
	for key in cells:
		var c: Vector4i = key
		if first:
			content_lo = c
			content_hi = c
			first = false
			continue
		content_lo = Vector4i(mini(content_lo.x, c.x), mini(content_lo.y, c.y),
			mini(content_lo.z, c.z), mini(content_lo.w, c.w))
		content_hi = Vector4i(maxi(content_hi.x, c.x), maxi(content_hi.y, c.y),
			maxi(content_hi.z, c.z), maxi(content_hi.w, c.w))
	content_hi += Vector4i.ONE


## Which solid cells are worth drawing, given the axes currently visible.
##
## Chambers are carved out of solid rock, so drawing every solid cell would
## show the player the outside of a brick. Two rules fix that. A solid cell is
## drawn only where it borders open space along a *visible* axis — everything
## deeper in the rock is invisible from inside the corridor anyway — and the
## region outside the chamber counts as rock, so the outer shell is never
## drawn. Then ceilings are dropped: a cell whose only opening is downwards is
## the roof over a corridor, and roofs are what stop you seeing in.
##
## What is left is the corridor itself, open to the sky, which is the whole
## chamber the player can actually reach.
##
## `axis_mask` is a bitmask of the horizontal world axes in play. It changes
## only when the player turns, and there are three possible values, so the
## result is cached rather than recomputed.
func surface(axis_mask: int) -> Array:
	if _surface_cache.has(axis_mask):
		return _surface_cache[axis_mask]

	var axes: Array[int] = []
	for a in 4:
		if a != 1 and (axis_mask & (1 << a)) != 0:
			axes.append(a)

	var visible := {}
	for key in _shell:
		var c: Vector4i = key
		var tag: Array = cells[c]
		if tag[0] != Cfg.Kind.SOLID:
			visible[c] = tag
			continue

		var open := false
		for a in axes:
			for sgn in [-1, 1]:
				var n: Vector4i = c
				n[a] += sgn
				if not _is_rock(n):
					open = true
					break
			if open:
				break
		if not open:
			var above: Vector4i = c
			above.y += 1
			open = not _is_rock(above)
		if open:
			visible[c] = tag

	var out := _merge(visible)
	_surface_cache[axis_mask] = out
	return out


## Outside the chamber counts as rock. Without that the whole outer shell of a
## carved chamber qualifies as "borders open space" and gets drawn.
func _is_rock(c: Vector4i) -> bool:
	if not in_bounds(c):
		return true
	var t = cells.get(c)
	return t != null and t[0] == Cfg.Kind.SOLID


## Greedy 4D box merge: grow along x, then z, then y, then w, taking only
## slabs that are uniform in kind and hue. Cuts a 900-cell chamber down to a
## few dozen boxes.
func _merge(typed: Dictionary) -> Array:
	var used := {}
	var out: Array = []
	var keys := typed.keys()
	keys.sort_custom(func(a, b):
		if a.w != b.w: return a.w < b.w
		if a.y != b.y: return a.y < b.y
		if a.z != b.z: return a.z < b.z
		return a.x < b.x)

	# Pickups and exits stay one cell each: they wink out individually as they
	# are collected, so they must not be welded to a neighbour.
	const ATOMIC := [Cfg.Kind.GOAL, Cfg.Kind.KEY, Cfg.Kind.SHARD]

	for c in keys:
		if used.has(c):
			continue
		var tag: Array = typed[c]
		var ext := Vector4i(1, 1, 1, 1)
		if tag[0] in ATOMIC:
			used[c] = true
			out.append({
				"lo": Vector4(c.x, c.y, c.z, c.w),
				"hi": Vector4(c.x + 1, c.y + 1, c.z + 1, c.w + 1),
				"kind": tag[0], "hue": tag[1], "cell": c,
			})
			continue

		var uniform := func(lo: Vector4i, e: Vector4i) -> bool:
			for dw in e.w:
				for dy in e.y:
					for dz in e.z:
						for dx in e.x:
							var q := Vector4i(lo.x + dx, lo.y + dy, lo.z + dz, lo.w + dw)
							if used.has(q):
								return false
							var t = typed.get(q)
							if t == null or t[0] != tag[0] or t[1] != tag[1]:
								return false
			return true

		for axis in [0, 2, 1, 3]:
			while true:
				var probe := ext
				probe[axis] += 1
				if not uniform.call(c, probe):
					break
				ext = probe

		for dw in ext.w:
			for dy in ext.y:
				for dz in ext.z:
					for dx in ext.x:
						used[Vector4i(c.x + dx, c.y + dy, c.z + dz, c.w + dw)] = true

		out.append({
			"lo": Vector4(c.x, c.y, c.z, c.w),
			"hi": Vector4(c.x + ext.x, c.y + ext.y, c.z + ext.z, c.w + ext.w),
			"kind": tag[0],
			"hue": tag[1],
		})
	return out


func kind_at(c: Vector4i) -> int:
	var t = cells.get(c)
	return -1 if t == null else t[0]


func hue_at(c: Vector4i) -> int:
	var t = cells.get(c)
	return 0 if t == null else t[1]


func in_bounds(c: Vector4i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.z >= 0 and c.w >= 0 \
		and c.x < size.x and c.y < size.y and c.z < size.z and c.w < size.w


## Doors stop blocking once their key is in `keys` (a bitmask).
func blocks_movement(c: Vector4i, keys: int) -> bool:
	var t = cells.get(c)
	if t == null:
		return false
	var kind: int = t[0]
	if kind == Cfg.Kind.DOOR:
		return (keys & (1 << t[1])) == 0
	return kind in Cfg.BLOCKING
