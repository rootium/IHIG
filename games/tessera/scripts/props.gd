class_name Props
extends RefCounted

## Procedural meshes for everything that is not a wall. None of these are
## primitives: the crystals are faceted from a jittered subdivided icosahedron,
## the exit is a ring of ribbed segments, and the key sigils are stellated
## cross-polytopes. All built once at load and shared.

static var _cache := {}


static func get_mesh(name: String) -> Mesh:
	if not _cache.has(name):
		match name:
			"crystal": _cache[name] = _crystal()
			"portal": _cache[name] = _portal()
			"sigil": _cache[name] = _sigil()
			"core": _cache[name] = _core()
			_: _cache[name] = SphereMesh.new()
	return _cache[name]


# --- geodesic helpers ---------------------------------------------------------

static func _icosahedron() -> Array:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	for i in v.size():
		v[i] = v[i].normalized()
	var f := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]
	return [v, f]


static func _subdivide(verts: Array, faces: Array) -> Array:
	var mid := {}
	var out_f := []
	var v: Array = verts.duplicate()

	var midpoint := func(a: int, b: int) -> int:
		var k := "%d_%d" % [mini(a, b), maxi(a, b)]
		if mid.has(k):
			return mid[k]
		var p: Vector3 = ((v[a] + v[b]) * 0.5).normalized()
		v.append(p)
		mid[k] = v.size() - 1
		return v.size() - 1

	for f in faces:
		var a: int = midpoint.call(f[0], f[1])
		var b: int = midpoint.call(f[1], f[2])
		var c: int = midpoint.call(f[2], f[0])
		out_f.append([f[0], a, c])
		out_f.append([f[1], b, a])
		out_f.append([f[2], c, b])
		out_f.append([a, b, c])
	return [v, out_f]


static func _hash(p: Vector3) -> float:
	var d := sin(p.x * 127.1 + p.y * 311.7 + p.z * 74.7) * 43758.5453
	return d - floor(d)


## Flat-shaded triangle soup, so every facet catches the light separately —
## that is what reads as a cut crystal rather than a ball.
static func _faceted(verts: Array, faces: Array, radial: Callable, colorize: Callable) -> ArrayMesh:
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uvs := PackedVector2Array()

	var moved: Array[Vector3] = []
	for p in verts:
		moved.append(radial.call(p as Vector3))

	for f in faces:
		var a: Vector3 = moved[f[0]]
		var b: Vector3 = moved[f[1]]
		var c: Vector3 = moved[f[2]]
		var n := (b - a).cross(c - a).normalized()
		var centre := (a + b + c) / 3.0
		var shade: Color = colorize.call(centre)
		for p in [a, b, c]:
			pts.append(p)
			nrm.append(n)
			col.append(shade)
			uvs.append(Vector2(p.x, p.y) * 0.5 + Vector2(0.5, 0.5))

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# --- the props ----------------------------------------------------------------

## A shard: an icosahedron subdivided once, then pulled into a spiky habit by
## a per-vertex hash, and stretched along Y so it reads as a grown crystal.
static func _crystal() -> Mesh:
	var ico := _icosahedron()
	var sub := _subdivide(ico[0], ico[1])
	return _faceted(sub[0], sub[1],
		func(p: Vector3) -> Vector3:
			var h := _hash(p * 4.3)
			var r := 0.30 + 0.16 * h + 0.20 * pow(absf(p.y), 2.4)
			return Vector3(p.x * r * 0.72, p.y * r * 1.55, p.z * r * 0.72),
		func(c: Vector3) -> Color:
			return Color(1.0, 0.86, 0.42).lerp(Color(1.0, 0.42, 0.18), _hash(c * 9.1)))


## The exit: a ribbed ring, twelve segments, each a tapered wedge, so it
## catches light like a machined collar rather than a torus.
static func _portal() -> Mesh:
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uvs := PackedVector2Array()
	var segs := 16
	var ring := 12

	for i in segs:
		var gap := 0.30
		var a0 := TAU * (float(i) + gap * 0.5) / float(segs)
		var a1 := TAU * (float(i) + 1.0 - gap * 0.5) / float(segs)
		for j in ring:
			var b0 := TAU * float(j) / float(ring)
			var b1 := TAU * float(j + 1) / float(ring)
			var quad := []
			for pair in [[a0, b0], [a1, b0], [a1, b1], [a0, b1]]:
				var a: float = pair[0]
				var b: float = pair[1]
				# A slight taper towards the segment ends turns the tube into a wedge.
				var taper := 0.62 + 0.38 * sin(PI * (a - a0) / maxf(a1 - a0, 1e-4))
				var tube := 0.115 * taper
				var cx := (0.5 + tube * cos(b))
				quad.append([
					Vector3(cx * cos(a), tube * sin(b), cx * sin(a)),
					Vector3(cos(b) * cos(a), sin(b), cos(b) * sin(a)).normalized(),
				])
			for idx in [0, 1, 2, 0, 2, 3]:
				pts.append(quad[idx][0])
				nrm.append(quad[idx][1])
				col.append(Color(0.30, 1.0, 0.76))
				uvs.append(Vector2(float(i) / float(segs), float(idx) * 0.25))

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## A key sigil: the 3D cross-polytope with each face raised to a point, which
## gives the eight-pointed star that reads as "this opens something".
static func _sigil() -> Mesh:
	var v: Array[Vector3] = [
		Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0),
		Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
	]
	var f := [
		[0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4],
		[2, 0, 5], [1, 2, 5], [3, 1, 5], [0, 3, 5],
	]
	# Stellate: replace each face with three, meeting at a raised apex.
	var verts: Array[Vector3] = v.duplicate()
	var faces := []
	for tri in f:
		var apex: Vector3 = ((v[tri[0]] + v[tri[1]] + v[tri[2]]) / 3.0).normalized() * 1.62
		verts.append(apex)
		var ai := verts.size() - 1
		faces.append([tri[0], tri[1], ai])
		faces.append([tri[1], tri[2], ai])
		faces.append([tri[2], tri[0], ai])
	return _faceted(verts, faces,
		func(p: Vector3) -> Vector3: return p * 0.30,
		func(c: Vector3) -> Color:
			return Color(1, 1, 1).lerp(Color(1.0, 0.72, 0.30), clampf(c.length() - 0.3, 0.0, 1.0)))


## The glowing kernel inside the player's tesseract.
static func _core() -> Mesh:
	var ico := _icosahedron()
	var sub := _subdivide(ico[0], ico[1])
	return _faceted(sub[0], sub[1],
		func(p: Vector3) -> Vector3: return p * (0.13 + 0.02 * _hash(p * 7.0)),
		func(_c: Vector3) -> Color: return Color(1.0, 0.95, 0.86))
