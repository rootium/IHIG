class_name Hyper
extends RefCounted

## The four-dimensional geometry the whole game rests on.
##
## The world is a set of axis-aligned 4D boxes. The player sees a three
## dimensional cross-section of it: the hyperplane through the player's
## position, spanned by three of the four directions of a *frame*.
##
## A frame is four orthonormal vectors:
##
##   v[0]  screen right      v[2]  screen depth
##   v[1]  screen up         v[3]  hidden — the direction you cannot see along
##
## At rest every frame vector is a signed world axis, which keeps the whole
## game on an integer lattice. The two rotations the player can perform turn
## v[2] into v[3] (or v[0] into v[3]) through a right angle. Halfway through
## one of those the frame is genuinely oblique, and the cross-section of a box
## is still exactly a box — that is the fact that makes this cheap enough to
## run on a phone. See slice() for why.

const AX := 0
const AY := 1
const AZ := 2
const AW := 3

const EPS := 1.0e-6
## Seen nearly edge-on a box's cross-section stretches towards infinity. It is
## geometrically true and visually useless, so extents are clamped to this.
const CLAMP := 48.0

const AXIS_NAMES := ["X", "Y", "Z", "W"]

# --- frames -------------------------------------------------------------------

## The frame the player starts every chamber in.
static func identity_frame() -> Array:
	return [
		Vector4(1, 0, 0, 0),
		Vector4(0, 1, 0, 0),
		Vector4(0, 0, 1, 0),
		Vector4(0, 0, 0, 1),
	]


static func copy_frame(f: Array) -> Array:
	return [f[0], f[1], f[2], f[3]]


## The frame reached by rotating `slot` (0 for X, 2 for Z) into the hidden
## direction by `t` right angles, `t` in [0, 1]. `dir` picks the sense.
##
## This is an ordinary Givens rotation in the plane spanned by v[slot] and
## v[3]; every other frame vector is untouched, which is exactly why v[1] —
## up, the direction gravity runs along — can never be rotated away.
static func rotated_frame(f: Array, slot: int, dir: int, t: float) -> Array:
	var a := t * PI * 0.5 * float(dir)
	var c := cos(a)
	var s := sin(a)
	var out := copy_frame(f)
	out[slot] = f[slot] * c + f[3] * s
	out[3] = f[3] * c - f[slot] * s
	return out


## Snap a frame that should be at rest back onto the lattice. Floating point
## error accumulated over a few hundred rotations would otherwise drift the
## world off its integer grid.
static func quantize_frame(f: Array) -> Array:
	var out: Array = []
	for k in 4:
		var v: Vector4 = f[k]
		var q := Vector4.ZERO
		for a in 4:
			q[a] = float(roundi(v[a]))
		out.append(q)
	return out


## Frames are compared and stored as a short signature so the solver can use
## them as dictionary keys.
static func frame_key(f: Array) -> int:
	var key := 0
	for k in 4:
		var v: Vector4 = f[k]
		for a in 4:
			var q := roundi(v[a])
			if q != 0:
				key = key * 16 + (a * 2 + (0 if q > 0 else 1)) + 1
				break
	return key


## The signed world axis a resting frame vector points along, as (axis, sign).
static func axis_of(v: Vector4) -> Array:
	for a in 4:
		if absf(v[a]) > 0.5:
			return [a, 1 if v[a] > 0.0 else -1]
	return [-1, 0]


# --- slicing ------------------------------------------------------------------

## The cross-section of one 4D box, in render space.
##
## `lo`/`hi` are the box's corners. `frame` is the current (possibly mid-
## rotation) frame. `hidden` is the coordinate of the slicing hyperplane along
## v[3] — normally the player's own hidden coordinate, offset by `hidden` steps
## when drawing the ghosts of neighbouring slices.
##
## A render point r maps back to the world point
##
##   Q = r.x*v[0] + r.y*v[1] + r.z*v[2] + hidden*v[3]
##
## so each world axis `a` gives one constraint  lo[a] <= Q[a] <= hi[a]  which
## is linear in r. Because at most one *visible* frame vector ever has a
## component on any given world axis — true at rest by construction, and true
## mid-rotation because a Givens rotation only mixes two axes and hands both of
## them to the same pair (v[slot], v[3]) — each constraint touches exactly one
## component of r. Four constraints, three unknowns, one per axis: the solution
## set is an axis-aligned box, and the leftover constraint is a yes/no gate on
## whether the slice hits the box at all.
##
## Returns [] when the hyperplane misses the box, else [Vector3 min, Vector3 max].
static func slice(lo: Vector4, hi: Vector4, frame: Array, hidden: float) -> Array:
	var rmin := Vector3(-CLAMP, -CLAMP, -CLAMP)
	var rmax := Vector3(CLAMP, CLAMP, CLAMP)
	var hv: Vector4 = frame[3]

	for a in 4:
		var base := hidden * hv[a]
		var slot := -1
		var coef := 0.0
		for k in 3:
			var c: float = (frame[k] as Vector4)[a]
			if absf(c) > EPS:
				slot = k
				coef = c
				break

		if slot < 0:
			# No visible direction moves along this axis: the slice either sits
			# inside the box's extent here or misses it entirely.
			if base < lo[a] - EPS or base > hi[a] + EPS:
				return []
			continue

		var t0 := (lo[a] - base) / coef
		var t1 := (hi[a] - base) / coef
		if t0 > t1:
			var swap := t0
			t0 = t1
			t1 = swap
		if t0 > rmin[slot]:
			rmin[slot] = t0
		if t1 < rmax[slot]:
			rmax[slot] = t1
		if rmin[slot] > rmax[slot]:
			return []

	return [rmin, rmax]


## Where a single 4D point lands in render space. Used for the player, and for
## anchoring the board so a rotation pivots around them.
static func project(q: Vector4, frame: Array) -> Vector3:
	return Vector3(q.dot(frame[0]), q.dot(frame[1]), q.dot(frame[2]))


## The hyperplane coordinate of a 4D point under a frame.
static func hidden_of(q: Vector4, frame: Array) -> float:
	return q.dot(frame[3])


static func cell_center(c: Vector4i) -> Vector4:
	return Vector4(float(c.x) + 0.5, float(c.y) + 0.5, float(c.z) + 0.5, float(c.w) + 0.5)


static func step(c: Vector4i, v: Vector4, n: int) -> Vector4i:
	return Vector4i(
		c.x + roundi(v.x) * n,
		c.y + roundi(v.y) * n,
		c.z + roundi(v.z) * n,
		c.w + roundi(v.w) * n
	)
