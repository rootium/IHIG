class_name Avatar
extends Node3D

## The player, drawn as what the player actually is: a point in four
## dimensions. The body is a real hypercube — sixteen vertices, thirty-two
## edges — projected 4D to 3D through the *same frame the game is slicing
## with*, so when you turn Z into W the tesseract visibly tumbles inside out.
## Nothing else in the game communicates your orientation as directly.

const D := 2.35        ## eye distance along the hidden axis, for the projection
const SCALE := 0.46
const EDGE_R := 0.021

var _verts4: Array[Vector4] = []
var _edges: Array = []
var _edge_mm: MultiMesh
var _node_mm: MultiMesh
var _core: MeshInstance3D
var _halo: MeshInstance3D
var _spin := 0.0
var _tint := Cfg.PLAYER_EDGE


func _ready() -> void:
	for i in 16:
		_verts4.append(Vector4(
			-0.5 if (i & 1) == 0 else 0.5,
			-0.5 if (i & 2) == 0 else 0.5,
			-0.5 if (i & 4) == 0 else 0.5,
			-0.5 if (i & 8) == 0 else 0.5))
	# Two vertices of a hypercube share an edge when their indices differ in
	# exactly one bit.
	for i in 16:
		for bit in 4:
			var j := i ^ (1 << bit)
			if j > i:
				_edges.append([i, j])

	var cyl := CylinderMesh.new()
	cyl.top_radius = EDGE_R
	cyl.bottom_radius = EDGE_R
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 0
	_edge_mm = _layer(cyl, _edges.size(), Cfg.PLAYER_EDGE, 2.1, 1.8)

	_node_mm = _layer(Props.get_mesh("core"), 16, Cfg.PLAYER, 2.6, 1.1)

	var halo_mesh := SphereMesh.new()
	halo_mesh.radial_segments = 16
	halo_mesh.rings = 8
	halo_mesh.radius = 1.0
	halo_mesh.height = 2.0
	_halo = MeshInstance3D.new()
	_halo.mesh = halo_mesh
	_halo.scale = Vector3.ONE * 0.95
	var halo_mat := ShaderMaterial.new()
	halo_mat.shader = preload("res://shaders/halo.gdshader")
	halo_mat.set_shader_parameter("tint", Cfg.PLAYER_EDGE)
	halo_mat.render_priority = -1
	_halo.material_override = halo_mat
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.extra_cull_margin = 64.0
	add_child(_halo)

	_core = MeshInstance3D.new()
	_core.mesh = Props.get_mesh("core")
	_core.scale = Vector3.ONE * 1.7
	_core.material_override = _energy(Cfg.PLAYER, 3.2, 0.6)
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)


func _energy(tint: Color, glow: float, rim: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/energy.gdshader")
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("glow", glow)
	mat.set_shader_parameter("rim", rim)
	return mat


func _layer(mesh: Mesh, count: int, tint: Color, glow: float, rim: float) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _energy(tint, glow, rim)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 64.0
	add_child(mmi)
	return mm


func set_tint(c: Color) -> void:
	_tint = c
	for child in get_children():
		var mat = child.material_override
		if mat is ShaderMaterial:
			mat.set_shader_parameter("tint", c)


func _ready_halo() -> void:
	pass


## `frame` is the game's live frame, mid-rotation included. `charge` brightens
## the whole body — used when a shard is taken or the exit is reached.
func update_body(frame: Array, charge: float) -> void:
	_spin += get_process_delta_time() * 0.55

	# A slow idle turn in two planes that the player never controls, so the
	# body is always in motion even while they think.
	var ca := cos(_spin)
	var sa := sin(_spin)
	var cb := cos(_spin * 0.61)
	var sb := sin(_spin * 0.61)

	var proj: Array[Vector3] = []
	for v in _verts4:
		# idle rotation in the XW and YZ planes
		var p := Vector4(
			v.x * ca + v.w * sa,
			v.y * cb - v.z * sb,
			v.y * sb + v.z * cb,
			v.w * ca - v.x * sa)
		# then into the player's own frame, and down to three dimensions
		var c := Vector4(p.dot(frame[0]), p.dot(frame[1]), p.dot(frame[2]), p.dot(frame[3]))
		var k := SCALE * D / maxf(D - c.w, 0.35)
		proj.append(Vector3(c.x, c.y, c.z) * k)

	for i in 16:
		var depth := clampf((proj[i].length() / (SCALE * 0.95)), 0.35, 1.6)
		_node_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * depth * 0.55), proj[i]))

	for e in _edges.size():
		var a: Vector3 = proj[_edges[e][0]]
		var b: Vector3 = proj[_edges[e][1]]
		var d := b - a
		var len := d.length()
		if len < 1e-4:
			_edge_mm.set_instance_transform(e, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), a))
			continue
		var dir := d / len
		var up := Vector3.UP if absf(dir.y) < 0.97 else Vector3.RIGHT
		var side := up.cross(dir).normalized()
		var fwd := dir.cross(side)
		# Edges pointing along the hidden axis are the ones that vanish first
		# under a rotation; brightening the short ones makes that legible.
		var thick := clampf(0.55 / maxf(len, 0.12), 0.55, 1.9)
		_edge_mm.set_instance_transform(e,
			Transform3D(Basis(side * thick, dir * len, fwd * thick), (a + b) * 0.5))

	_core.scale = Vector3.ONE * (1.5 + 0.28 * sin(_spin * 3.4) + charge * 1.4)
	# Charge brightens the whole body through the materials, since instance
	# colour is not available (see world.gd).
	_halo.scale = Vector3.ONE * (0.92 + charge * 0.5)
	(_halo.material_override as ShaderMaterial).set_shader_parameter("strength", 0.42 + charge * 0.9)
	for child in get_children():
		if child == _halo:
			continue
		var mat = child.material_override
		if mat is ShaderMaterial:
			mat.set_shader_parameter("glow", (2.1 if child != _core else 3.6) + charge * 2.6)
