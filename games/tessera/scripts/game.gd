class_name Game
extends Node3D

## The playfield: player state, the rules of moving through a 4D chamber, the
## camera, and the animation that carries one state into the next.

signal stats_changed
signal solved(moves: int, shards: int, par: int)
signal died
signal narrated(text: String)

enum St { IDLE, MOVING, SHIFTING, ROTATING, DYING, DONE }

const UP4 := Vector4i(0, 1, 0, 0)
const DOWN4 := Vector4i(0, -1, 0, 0)
## How far back the orthographic camera sits. Only depth sorting and the fog
## care, but both care a lot.
const CAM_DIST := 60.0

var level: Level = null
var world: World
var avatar: Avatar
var cam_pivot: Node3D
var cam: Camera3D

# --- player state -------------------------------------------------------------
var cell := Vector4i.ZERO
var frame: Array = Hyper.identity_frame()
var keys := 0
var shards := 0
var moves := 0
var rotations := 0
var shifts := 0

var state := St.IDLE
var _undo: Array = []

# --- animation ----------------------------------------------------------------
var _anim_t := 0.0
var _anim_len := 0.0
var _from_pos := Vector3.ZERO
var _to_pos := Vector3.ZERO
var _rot_slot := 0
var _rot_dir := 1
var _rot_from: Array = []
var _pinned := Vector3.ZERO
var board_offset := Vector3.ZERO
var _charge := 0.0
var _queued := []

# --- camera -------------------------------------------------------------------
var cam_yaw := PI * 0.25
var _cam_yaw_target := PI * 0.25
var cam_pitch := 0.62
var cam_zoom := 13.0
var _cam_focus := Vector3.ZERO
var _drag := false
var _drag_moved := 0.0

var ghost_depth := Cfg.GHOST_DEPTH


func _ready() -> void:
	world = World.new()
	add_child(world)

	avatar = Avatar.new()
	add_child(avatar)

	cam_pivot = Node3D.new()
	add_child(cam_pivot)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = cam_zoom
	cam.near = 0.05
	cam.far = 400.0
	cam_pivot.add_child(cam)

	# The backdrop is a full-screen quad under the 3D layer rather than a sky:
	# see shaders/backdrop.gdshader for why an orthographic camera cannot have
	# one.
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var back := CanvasLayer.new()
	back.layer = -10
	add_child(back)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://shaders/backdrop.gdshader")
	rect.material = _sky_mat
	back.add_child(rect)

	set_process(true)
	set_process_unhandled_input(true)


var _sky_mat: ShaderMaterial


# --- loading ------------------------------------------------------------------

func load_level(lv: Level) -> void:
	level = lv
	world.set_level(lv)
	cell = lv.start
	frame = Hyper.identity_frame()
	keys = 0
	shards = 0
	moves = 0
	rotations = 0
	shifts = 0
	board_offset = Vector3.ZERO
	_undo.clear()
	_queued.clear()
	_charge = 0.0
	state = St.IDLE
	_settle_gravity(true)
	_refresh(true)
	avatar.position = _player_pos()
	avatar.scale = Vector3.ONE
	_cam_focus = _player_pos()
	var ext := lv.content_hi - lv.content_lo
	var span: float = maxf(maxf(ext.x, ext.z), maxf(ext.w, float(ext.y) * 1.5))
	cam_zoom = clampf(span * 1.15 + 2.5, 9.0, 30.0)
	# The camera stands well back so the orthographic frustum clears the
	# chamber, so the fog has to be placed relative to *it*, not to the origin.
	world.set_fog(CAM_DIST - span * 0.35, CAM_DIST + span * 1.5)
	if lv.hint != "":
		narrated.emit(lv.hint)
	stats_changed.emit()


# --- geometry helpers ---------------------------------------------------------

func _player_pos(f: Array = frame) -> Vector3:
	return Hyper.project(Hyper.cell_center(cell), f) + board_offset


func _hidden(f: Array = frame) -> float:
	return Hyper.hidden_of(Hyper.cell_center(cell), f)


func _dir(slot: int, sign: int) -> Vector4i:
	var v: Vector4 = frame[slot]
	return Vector4i(roundi(v.x) * sign, roundi(v.y) * sign, roundi(v.z) * sign, roundi(v.w) * sign)


func _free(c: Vector4i) -> bool:
	return not level.blocks_movement(c, keys)


func _supported(c: Vector4i) -> bool:
	return not _free(c + DOWN4)


# --- rules --------------------------------------------------------------------

## Walk one cell along a horizontal frame direction, stepping up a single block
## if one is in the way and the headroom allows it.
func try_walk(slot: int, sign: int) -> bool:
	if state != St.IDLE:
		if _queued.size() < 1:
			_queued.append(["walk", slot, sign])
		return false
	var d := _dir(slot, sign)
	var target := cell + d
	if not _free(target):
		var up := target + UP4
		if _free(up) and _free(cell + UP4):
			target = up
		else:
			_bump()
			return false
	_push_undo()
	cell = target
	moves += 1
	_begin_move(Cfg.MOVE_TIME)
	Audio.step()
	return true


## The move that only exists here: one cell along the axis you cannot see.
func try_shift(sign: int) -> bool:
	if state != St.IDLE:
		if _queued.size() < 1:
			_queued.append(["shift", sign])
		return false
	var d := _dir(3, sign)
	var target := cell + d
	if not _free(target):
		_bump()
		narrated.emit("Something solid occupies that slice.")
		return false
	_push_undo()
	cell = target
	moves += 1
	shifts += 1
	_begin_move(Cfg.SHIFT_TIME)
	Audio.shift(sign)
	return true


## Turn a visible axis into the hidden one through a right angle. Because the
## turn pivots on the player's own position their cell never changes, so this
## can never strand them inside a wall — the chamber simply becomes a different
## chamber around them.
func try_rotate(slot: int, dir: int) -> bool:
	if state != St.IDLE:
		return false
	if slot == 2 and not level.allow_zw:
		_bump(); narrated.emit("This chamber will not turn that way.")
		return false
	if slot == 0 and not level.allow_xw:
		_bump(); narrated.emit("This chamber will not turn that way.")
		return false
	if level.kind_at(cell) == Cfg.Kind.FIELD:
		_bump(); narrated.emit("A stilling field. You cannot turn from inside it.")
		return false
	_push_undo()
	_rot_slot = slot
	_rot_dir = dir
	_rot_from = Hyper.copy_frame(frame)
	_pinned = _player_pos()
	moves += 1
	rotations += 1
	state = St.ROTATING
	_anim_t = 0.0
	_anim_len = Cfg.ROT_TIME
	Audio.rotate()
	return true


## Small predicates so a test script can ask about the state machine without
## naming the Game type — see tests/solve_test.gd for why that matters.
func is_idle() -> bool:
	return state == St.IDLE


func is_solved() -> bool:
	return state == St.DONE


func _bump() -> void:
	Audio.deny()
	_charge = maxf(_charge, 0.28)


func _begin_move(dur: float) -> void:
	_from_pos = avatar.position
	_settle_gravity(false)
	_to_pos = _player_pos()
	state = St.MOVING
	_anim_t = 0.0
	_anim_len = dur
	_refresh(true)


## Fall until something holds you up. Returns the number of cells dropped.
func _settle_gravity(instant: bool) -> int:
	var dropped := 0
	while dropped < 64:
		var below := cell + DOWN4
		if not _free(below):
			break
		cell = below
		dropped += 1
		# Nothing holds up the space under a chamber. Leaving through the
		# floor is a legitimate way to lose.
		if cell.y < 0:
			break
	if cell.y < 0 and not instant:
		_kill("You fell out of the chamber.")
	return dropped


func _touch_cell() -> void:
	var k := level.kind_at(cell)
	match k:
		Cfg.Kind.HAZARD:
			_kill("The lattice unmade you.")
		Cfg.Kind.KEY:
			if not world.taken.has(cell):
				world.taken[cell] = true
				keys |= 1 << level.hue_at(cell)
				world.keys_held = keys
				_charge = 1.0
				Audio.pickup(1)
				narrated.emit("A sigil. Doors of that colour will stand aside.")
				_refresh(true)
				stats_changed.emit()
		Cfg.Kind.SHARD:
			if not world.taken.has(cell):
				world.taken[cell] = true
				shards += 1
				_charge = 1.0
				Audio.pickup(0)
				_refresh(true)
				stats_changed.emit()
		Cfg.Kind.GOAL:
			state = St.DONE
			_charge = 1.0
			Audio.win()
			solved.emit(moves, shards, level.par)


func _kill(reason: String) -> void:
	if state == St.DYING or state == St.DONE:
		return
	state = St.DYING
	_anim_t = 0.0
	_anim_len = 0.55
	Audio.die()
	narrated.emit(reason)
	died.emit()


# --- undo / restart -----------------------------------------------------------

func _push_undo() -> void:
	_undo.append({
		"cell": cell, "frame": Hyper.copy_frame(frame), "keys": keys,
		"shards": shards, "taken": world.taken.duplicate(),
		"moves": moves, "rot": rotations, "shift": shifts,
		"offset": board_offset,
	})
	if _undo.size() > 256:
		_undo.pop_front()


func undo() -> void:
	if _undo.is_empty() or state == St.ROTATING:
		return
	var s: Dictionary = _undo.pop_back()
	cell = s.cell
	frame = s.frame
	keys = s.keys
	shards = s.shards
	world.taken = s.taken
	world.keys_held = keys
	moves = s.moves
	rotations = s.rot
	shifts = s.shift
	board_offset = s.offset
	state = St.IDLE
	avatar.position = _player_pos()
	_refresh(true)
	Audio.undo()
	stats_changed.emit()


func restart() -> void:
	if level:
		load_level(level)
		Audio.reset()


# --- frame update -------------------------------------------------------------

## The horizontal world axes currently on screen. Y is always one of the three
## visible directions and is never rotated, so only the other two vary.
func _axis_mask(f: Array = frame) -> int:
	return (1 << Hyper.axis_of(f[0])[0]) | (1 << Hyper.axis_of(f[2])[0]) | 2


func _refresh(force: bool) -> void:
	if level == null:
		return
	if force:
		world.position = board_offset
		world.update_slice(frame, _hidden(), ghost_depth, _axis_mask())


func _process(delta: float) -> void:
	if level == null:
		return

	_charge = maxf(0.0, _charge - delta * 2.2)
	avatar.update_body(_live_frame(), _charge)
	world.set_player(avatar.position)

	match state:
		St.MOVING, St.SHIFTING:
			_anim_t += delta
			var t := clampf(_anim_t / maxf(_anim_len, 0.001), 0.0, 1.0)
			var e := 1.0 - pow(1.0 - t, 3.0)
			avatar.position = _from_pos.lerp(_to_pos, e)
			if t >= 1.0:
				avatar.position = _to_pos
				state = St.IDLE
				var d := _settle_gravity(false)
				if d > 0 and state == St.IDLE:
					_from_pos = avatar.position
					_to_pos = _player_pos()
					state = St.MOVING
					_anim_t = 0.0
					_anim_len = Cfg.FALL_TIME * float(d)
					_refresh(true)
					Audio.land()
				elif state == St.IDLE:
					_touch_cell()
					stats_changed.emit()
					_flush_queue()

		St.ROTATING:
			_anim_t += delta
			var t := clampf(_anim_t / _anim_len, 0.0, 1.0)
			# Slow at both ends: the turn should feel like something heavy
			# being brought around, not a snap.
			var e := t * t * (3.0 - 2.0 * t)
			e = e * e * (3.0 - 2.0 * e)
			var live := Hyper.rotated_frame(_rot_from, _rot_slot, _rot_dir, e)
			# Keep the player nailed to the same point on screen while the
			# chamber swings around them.
			board_offset = _pinned - Hyper.project(Hyper.cell_center(cell), live)
			world.position = board_offset
			avatar.position = _pinned
			world.update_slice(live, Hyper.hidden_of(Hyper.cell_center(cell), live), ghost_depth,
				_axis_mask(_rot_from) | (1 << Hyper.axis_of(_rot_from[3])[0]))
			_sky_mat.set_shader_parameter("warp", sin(e * PI) * 1.4)
			world.set_ghost_intensity(1.0 + sin(e * PI) * 1.6)
			if t >= 1.0:
				frame = Hyper.quantize_frame(Hyper.rotated_frame(_rot_from, _rot_slot, _rot_dir, 1.0))
				board_offset = _pinned - Hyper.project(Hyper.cell_center(cell), frame)
				state = St.IDLE
				_sky_mat.set_shader_parameter("warp", 0.0)
				world.set_ghost_intensity(1.0)
				avatar.position = _player_pos()
				_refresh(true)
				var d := _settle_gravity(false)
				if d > 0:
					_from_pos = avatar.position
					_to_pos = _player_pos()
					state = St.MOVING
					_anim_t = 0.0
					_anim_len = Cfg.FALL_TIME * float(d)
					_refresh(true)
				else:
					_touch_cell()
				stats_changed.emit()
				_flush_queue()

		St.DYING:
			_anim_t += delta
			avatar.scale = Vector3.ONE * maxf(0.001, 1.0 - _anim_t / _anim_len)
			if _anim_t >= _anim_len:
				avatar.scale = Vector3.ONE
				# Rewind the step that killed you rather than the whole
				# chamber. Falling out of a room is a misread of the fourth
				# dimension, and making the player replay twenty correct moves
				# to punish one wrong one teaches nothing.
				if _undo.is_empty():
					restart()
				else:
					undo()

	_update_camera(delta)


func _flush_queue() -> void:
	if _queued.is_empty() or state != St.IDLE:
		return
	var a = _queued.pop_front()
	if a[0] == "walk":
		try_walk(a[1], a[2])
	else:
		try_shift(a[1])


## The frame as it stands right now, including a rotation in progress.
func _live_frame() -> Array:
	if state != St.ROTATING:
		return frame
	var t := clampf(_anim_t / _anim_len, 0.0, 1.0)
	var e := t * t * (3.0 - 2.0 * t)
	e = e * e * (3.0 - 2.0 * e)
	return Hyper.rotated_frame(_rot_from, _rot_slot, _rot_dir, e)


# --- camera -------------------------------------------------------------------

func _update_camera(delta: float) -> void:
	cam_yaw = lerp_angle(cam_yaw, _cam_yaw_target, clampf(delta * 8.0, 0.0, 1.0))
	var vp := get_viewport().get_visible_rect().size
	_sky_mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	_sky_mat.set_shader_parameter("pan", Vector2(cam_yaw * 0.11, -cam_pitch * 0.16))
	var want := avatar.position
	if level:
		# Bias towards the middle of the carved space so the whole chamber stays
		# in view instead of the camera glueing itself to the player.
		var c := Vector4(level.content_lo.x + level.content_hi.x, level.content_lo.y + level.content_hi.y,
			level.content_lo.z + level.content_hi.z, level.content_lo.w + level.content_hi.w) * 0.5
		var mid := Hyper.project(c, frame) + board_offset
		want = want.lerp(mid, 0.45)
	_cam_focus = _cam_focus.lerp(want, clampf(delta * Cfg.CAM_LERP, 0.0, 1.0))

	var dir := Vector3(
		cos(cam_pitch) * sin(cam_yaw),
		sin(cam_pitch),
		cos(cam_pitch) * cos(cam_yaw))
	cam.position = Vector3.ZERO
	cam_pivot.position = _cam_focus + dir * CAM_DIST
	cam_pivot.look_at(_cam_focus, Vector3.UP)
	cam.size = lerpf(cam.size, cam_zoom, clampf(delta * 6.0, 0.0, 1.0))


## Used by the title screen, where nobody is playing but the chamber should
## still be turning.
func drift_camera(delta: float) -> void:
	_cam_yaw_target += delta * 0.14


func spin_camera(steps: int) -> void:
	_cam_yaw_target += PI * 0.25 * float(steps)
	Audio.camera()


## Screen-relative input, resolved onto whichever frame axis it best matches.
func walk_screen(ix: int, iz: int) -> void:
	var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
	var want := fwd * float(-iz) + right * float(ix)
	if want.length_squared() < 0.001:
		return
	if absf(want.x) >= absf(want.z):
		try_walk(0, 1 if want.x > 0.0 else -1)
	else:
		try_walk(2, 1 if want.z > 0.0 else -1)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			_drag = e.pressed
			_drag_moved = 0.0
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_zoom = clampf(cam_zoom - 1.2, 6.0, 34.0)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_zoom = clampf(cam_zoom + 1.2, 6.0, 34.0)
	elif e is InputEventMouseMotion and _drag:
		_cam_yaw_target -= e.relative.x * 0.006
		cam_yaw = _cam_yaw_target
		cam_pitch = clampf(cam_pitch + e.relative.y * 0.004, 0.12, 1.40)
	elif e is InputEventScreenDrag:
		_cam_yaw_target -= e.relative.x * 0.006
		cam_yaw = _cam_yaw_target
		cam_pitch = clampf(cam_pitch + e.relative.y * 0.004, 0.12, 1.40)
