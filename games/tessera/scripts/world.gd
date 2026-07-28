class_name World
extends Node3D

## Turns the 4D chamber into what you actually see: the solids of the slice
## you are standing in, and the ghost outlines of the slices either side.
##
## One MultiMesh per material class keeps the whole chamber — usually a few
## hundred sliced boxes once the ghosts are counted — down to a dozen draw
## calls, which is what makes this run at rate in a phone browser.

const CAPACITY := 1400

var level: Level = null
var grain: Texture2D = null

var _classes := {}                      # class id -> {mmi, mat}
var _ghosts := {}          # slice offset -> MultiMeshInstance3D
var _box := BoxMesh.new()

var _block_shader := preload("res://shaders/block.gdshader")
var _ghost_shader := preload("res://shaders/ghost.gdshader")

## Pickups already taken, keyed by Vector4i.
var taken := {}
var keys_held := 0


func _ready() -> void:
	_box.size = Vector3.ONE
	grain = _make_grain()


## A small seamless noise field, generated rather than shipped. Everything the
## block shader needs for veining, wear and micro-relief comes out of this.
func _make_grain() -> Texture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = 20260728
	n.frequency = 0.021
	n.fractal_octaves = 4
	n.fractal_gain = 0.55
	var tex := NoiseTexture2D.new()
	tex.noise = n
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.as_normal_map = false
	return tex


## Per-instance colour is deliberately not used anywhere in this file. The
## Compatibility renderer — the only one that covers web, Android and desktop
## from one export — does not deliver a MultiMesh's instance colours to the
## shader, so everything that needs its own colour gets its own material and
## its own layer instead. There are only a dozen or so, which is cheaper than
## it sounds.
func _new_layer(shader: Shader, order: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _box
	mm.instance_count = CAPACITY
	mm.visible_instance_count = 0

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = order

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The slice is recomputed relative to the chamber, not the camera, so
	# Godot's own culling has nothing useful to say about it.
	mmi.extra_cull_margin = 16384.0
	add_child(mmi)
	return mmi


## Exits, keys and shards are props rather than boxes: the slicer gives them a
## position and a scale, and a real mesh stands there.
const PROP_KINDS := {
	Cfg.Kind.GOAL: "portal",
	Cfg.Kind.SHARD: "crystal",
	Cfg.Kind.KEY: "sigil",
}

var _props := {}
var _spin := 0.0
var _fog := Vector2(22.0, 62.0)


func _process(delta: float) -> void:
	_spin += delta
	if _spinning:
		_restage_props()


func _prop_layer(name: String, mesh_name: String, tint: Color, rate: float) -> Dictionary:
	if _props.has(name):
		return _props[name]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Props.get_mesh(mesh_name)
	mm.instance_count = 96
	mm.visible_instance_count = 0

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/energy.gdshader")
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("glow", 1.5)
	mat.set_shader_parameter("rim", 1.3)

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 16384.0
	add_child(mmi)
	_props[name] = {"mmi": mmi, "mm": mm, "mat": mat, "rate": rate, "n": 0, "stage": []}
	return _props[name]


func _prop_key(kind: int, hue: int) -> String:
	return "%s%d" % [PROP_KINDS[kind], hue] if kind == Cfg.Kind.KEY else PROP_KINDS[kind]


func _class_id(kind: int, hue: int) -> int:
	return kind * 8 + hue


func _layer_for(kind: int, hue: int) -> MultiMeshInstance3D:
	var id := _class_id(kind, hue)
	if _classes.has(id):
		return _classes[id].mmi
	var mmi := _new_layer(_block_shader, 0)
	var mat: ShaderMaterial = mmi.material_override
	mat.set_shader_parameter("grain", grain)
	mat.set_shader_parameter("body_color", Cfg.body_color(kind, hue))
	mat.set_shader_parameter("edge_color", Cfg.edge_color(kind, hue))
	mat.set_shader_parameter("deep_color", Cfg.VOID)
	match kind:
		Cfg.Kind.GOAL:
			mat.set_shader_parameter("edge_gain", 1.1)
			mat.set_shader_parameter("seam_gain", 0.4)
			mat.set_shader_parameter("vein_gain", 0.6)
		Cfg.Kind.SHARD:
			mat.set_shader_parameter("edge_gain", 1.2)
			mat.set_shader_parameter("vein_gain", 0.7)
		Cfg.Kind.KEY:
			mat.set_shader_parameter("edge_gain", 1.0)
			mat.set_shader_parameter("vein_gain", 0.6)
		Cfg.Kind.HAZARD:
			mat.set_shader_parameter("edge_gain", 1.0)
			mat.set_shader_parameter("wear", 0.9)
			mat.set_shader_parameter("panel_inset", 0.30)
		Cfg.Kind.FIELD:
			mat.set_shader_parameter("edge_gain", 0.7)
			mat.set_shader_parameter("rim_gain", 0.9)
			mat.set_shader_parameter("panel_inset", 0.34)
		Cfg.Kind.DOOR:
			mat.set_shader_parameter("edge_gain", 0.9)
			mat.set_shader_parameter("panel_inset", 0.26)
	_classes[id] = {"mmi": mmi, "mat": mat}
	return mmi


func set_level(lv: Level) -> void:
	level = lv
	taken.clear()
	keys_held = 0
	for id in _classes:
		_classes[id].mmi.multimesh.visible_instance_count = 0


func is_hidden(b: Dictionary) -> bool:
	match b.kind:
		Cfg.Kind.KEY, Cfg.Kind.SHARD, Cfg.Kind.GOAL:
			return taken.has(b.get("cell", Vector4i.ZERO))
		Cfg.Kind.DOOR:
			return (keys_held & (1 << b.hue)) != 0
	return false


## Rebuild every visible box for the given frame. `hidden` is the coordinate of
## the player's own hyperplane along the frame's unseen axis.
func update_slice(frame: Array, hidden: float, ghost_depth: int, axis_mask: int) -> void:
	if level == null:
		return
	var blocks := level.surface(axis_mask)

	var counts := {}
	for id in _classes:
		counts[id] = 0
	for name in _props:
		_props[name].n = 0
		_props[name].stage.clear()
	var ghost_n := {}

	for b in blocks:
		if is_hidden(b):
			continue
		var is_prop: bool = PROP_KINDS.has(b.kind)
		var id := _class_id(b.kind, b.hue)
		var mm: MultiMesh = null
		if not is_prop:
			mm = _layer_for(b.kind, b.hue).multimesh
			if not counts.has(id):
				counts[id] = 0

		var s := Hyper.slice(b.lo, b.hi, frame, hidden)
		if not s.is_empty():
			var mn: Vector3 = s[0]
			var mx: Vector3 = s[1]
			var size := mx - mn
			if size.x > 0.004 and size.y > 0.004 and size.z > 0.004:
				if is_prop:
					# Props keep their shape and shrink as the slice leaves
					# them, rather than being squashed into a slab.
					var slot := _prop_layer(_prop_key(b.kind, b.hue), PROP_KINDS[b.kind],
						Cfg.edge_color(b.kind, b.hue), 0.8 if b.kind == Cfg.Kind.GOAL else 1.6)
					var k: int = slot.n
					if k < 96:
						var thin: float = minf(size.x, minf(size.y, size.z))
						slot.stage.append({
							"at": (mn + mx) * 0.5,
							"s": clampf(thin, 0.0, 1.0) * 1.35,
							"phase": mn.x + mn.z,
						})
						slot.n = k + 1
				else:
					var i: int = counts[id]
					if i < CAPACITY:
						mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(size), (mn + mx) * 0.5))
						counts[id] = i + 1

		# The neighbouring slices, drawn as outlines. Nothing else in the game
		# tells you what is one step ana or kata of where you stand.
		for o in range(-ghost_depth, ghost_depth + 1):
			if o == 0:
				continue
			var n: int = ghost_n.get(o, 0)
			if n >= CAPACITY:
				continue
			var gs := Hyper.slice(b.lo, b.hi, frame, hidden + float(o))
			if gs.is_empty():
				continue
			var gmn: Vector3 = gs[0]
			var gmx: Vector3 = gs[1]
			var gsize := gmx - gmn
			if gsize.x <= 0.004 or gsize.y <= 0.004 or gsize.z <= 0.004:
				continue
			_ghost_layer(o).multimesh.set_instance_transform(n,
				Transform3D(Basis.IDENTITY.scaled(gsize), (gmn + gmx) * 0.5))
			ghost_n[o] = n + 1

	for id in _classes:
		_classes[id].mmi.multimesh.visible_instance_count = counts.get(id, 0)
	_restage_props()
	for o in _ghosts:
		_ghosts[o].multimesh.visible_instance_count = ghost_n.get(o, 0)


## Props turn and bob in place. Doing it per instance rather than by rotating
## the MultiMeshInstance keeps each one over its own cell instead of swinging
## the whole set around the chamber origin.
func _restage_props() -> void:
	for name in _props:
		var slot: Dictionary = _props[name]
		var mm: MultiMesh = slot.mm
		var i := 0
		for it in slot.stage:
			var a: float = _spin * slot.rate
			var basis := Basis(Vector3.UP, a).scaled(Vector3.ONE * it.s)
			if name == "portal":
				basis = Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, sin(_spin * 0.7) * 0.34)
				basis = basis.scaled(Vector3.ONE * it.s)
			var bob := sin(_spin * 2.1 + it.phase) * 0.07
			mm.set_instance_transform(i, Transform3D(basis, it.at + Vector3(0, bob, 0)))
			i += 1
		mm.visible_instance_count = i


## Whether anything on screen needs a per-frame refresh.
var _spinning := true


## Walls between the camera and the player are dissolved away, or an isometric
## chamber is unplayable the moment you step behind one.
func set_player(pos: Vector3) -> void:
	for id in _classes:
		_classes[id].mat.set_shader_parameter("player_pos", pos)


func set_fog(near: float, far: float) -> void:
	for id in _classes:
		_classes[id].mat.set_shader_parameter("fog_start", near)
		_classes[id].mat.set_shader_parameter("fog_end", far)
	for o in _ghosts:
		var m: ShaderMaterial = _ghosts[o].material_override
		m.set_shader_parameter("fog_start", near)
		m.set_shader_parameter("fog_end", far)
	_fog = Vector2(near, far)


func _ghost_layer(o: int) -> MultiMeshInstance3D:
	if _ghosts.has(o):
		return _ghosts[o]
	var mmi := _new_layer(_ghost_shader, 24)
	var mat: ShaderMaterial = mmi.material_override
	mat.set_shader_parameter("fog_start", _fog.x)
	mat.set_shader_parameter("fog_end", _fog.y)
	mat.set_shader_parameter("tint", Cfg.ANA if o > 0 else Cfg.KATA)
	mat.set_shader_parameter("alpha", pow(0.44, absf(float(o)) - 1.0) * 0.80)
	_ghosts[o] = mmi
	return mmi


func set_ghost_intensity(v: float) -> void:
	for o in _ghosts:
		(_ghosts[o].material_override as ShaderMaterial).set_shader_parameter("intensity", v)


func flash(kind: int, hue: int, amount: float) -> void:
	var id := _class_id(kind, hue)
	if _classes.has(id):
		_classes[id].mat.set_shader_parameter("pulse", amount)
