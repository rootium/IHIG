class_name Grid
extends RefCounted
## One puzzle: a rectangle of cells, plus the two orientation snapshots that
## make a level replayable — where it starts, and where it is solved.
##
## Cells are flat arrays indexed `y * w + x`. Three bytes describe a cell:
##
##   kind    what is in it
##   orient  0 or 1 for a mirror/splitter; the emission direction for a source
##   tint    colour mask a source emits, or a target demands
##
## Directions are indices into STEP, and the order below is load-bearing: East,
## South, West, North puts each direction's opposite at `dir ^ 2` and its two
## mirror reflections at `dir ^ 3` and `dir ^ 1`, which is the whole of reflect().

enum Kind { EMPTY, WALL, MIRROR, SPLITTER, SOURCE, TARGET }

const E := 0
const S := 1
const W := 2
const N := 3
const STEP := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

var w: int
var h: int
var kind: PackedByteArray
var orient: PackedByteArray
var tint: PackedByteArray

var level: int = 1
var par: int = 1              ## Taps the generator's own solution takes.
var start: PackedByteArray    ## Orientations the level is handed to you in.
var solution: PackedByteArray ## Orientations that solve it. Drives the hint.
var movable: Array[int] = []  ## Pieces the solution actually depends on.


func _init(p_w: int, p_h: int) -> void:
	w = p_w
	h = p_h
	var n := w * h
	kind.resize(n)
	orient.resize(n)
	tint.resize(n)


func size() -> int:
	return w * h


func cell_at(x: int, y: int) -> int:
	return y * w + x


func x_of(cell: int) -> int:
	return cell % w


func y_of(cell: int) -> int:
	return cell / w


## The neighbour of `cell` in direction `dir`, or -1 off the edge of the board.
func step(cell: int, dir: int) -> int:
	var d: Vector2i = STEP[dir]
	var x := cell % w + d.x
	if x < 0 or x >= w:
		return -1
	var y := cell / w + d.y
	if y < 0 or y >= h:
		return -1
	return y * w + x


static func vec(dir: int) -> Vector2:
	var d: Vector2i = STEP[dir]
	return Vector2(d)


## Where a beam travelling `dir` goes after a mirror at orientation `o`.
##
## Orientation 0 is "/", which swaps East with North and South with West — and
## on this direction order that is exactly `dir ^ 3`. Orientation 1 is "\",
## which swaps East with South and West with North: `dir ^ 1`.
static func reflect(dir: int, o: int) -> int:
	return dir ^ (3 if o == 0 else 1)


## The orientation of a mirror that turns a beam travelling `a` into one
## travelling `b`. Symmetric in its arguments, because a mirror that turns `a`
## into `b` turns `b` into `a` — which is what lets the generator trace a path
## backwards from a target and still place the right pieces.
static func orient_for(a: int, b: int) -> int:
	return 0 if (a ^ b) == 3 else 1


func is_movable(cell: int) -> bool:
	var k := kind[cell]
	return k == Kind.MIRROR or k == Kind.SPLITTER


func toggle(cell: int) -> void:
	orient[cell] ^= 1


func restart() -> void:
	orient = start.duplicate()


## The first piece the solution needs that is currently turned the wrong way,
## or -1 when every one of them is already right. Decoys are not considered:
## nudging one would not be a hint.
func wrong_piece() -> int:
	for cell in movable:
		if orient[cell] != solution[cell]:
			return cell
	return -1
