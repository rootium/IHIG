extends Node2D
## Game manager: owns the court, the player, the camera and the screens, and
## arbitrates between them. Everything else in this project is deliberately
## unaware of game state.
##
## The run climbs upward, so "height" throughout means -position.y.

enum Mode { MENU, PLAY, PAUSED, DEAD }

## What the current touch is doing. Decided when the finger goes down and held
## until it lifts, so a rim culled mid-drag cannot turn an aim into a float.
enum Gesture { NONE, AIM, FLOAT }

const CAM_LEAD := 0.24      ## Fraction of velocity the camera looks ahead by.
const CAM_LEAD_MAX := 300.0
const CAM_RISE := 240.0     ## Player sits below centre so you can see upward.
const ZOOM_NEAR := 0.80
const ZOOM_FAR := 0.66

var mode: Mode = Mode.MENU
var theme: Dictionary = {}

var court: Court
var baller: Baller
var crowd: Crowd
var traj: Trajectory
var cam: Camera2D
var hud: HUD
var menus: Menus

var points: int = 0
var dunks: int = 0
var gold_taken: int = 0
var best_run_combo: int = 0
var best_height: float = 0.0

var _gesture: Gesture = Gesture.NONE


func _ready() -> void:
	SaveData.load_game()

	crowd = Crowd.new()
	crowd.z_index = -100
	add_child(crowd)

	court = Court.new()
	add_child(court)

	traj = Trajectory.new()
	traj.z_index = 5
	add_child(traj)

	baller = Baller.new()
	baller.died.connect(_on_died)
	baller.scored.connect(_on_scored)
	baller.clanged.connect(_on_clanged)
	add_child(baller)

	cam = Camera2D.new()
	cam.zoom = Vector2(ZOOM_NEAR, ZOOM_NEAR)
	add_child(cam)
	cam.make_current()

	hud = HUD.new()
	hud.pause_pressed.connect(_pause)
	add_child(hud)

	menus = Menus.new()
	menus.play_pressed.connect(start_run)
	menus.title_pressed.connect(to_title)
	menus.resume_pressed.connect(_resume)
	add_child(menus)

	to_title()


func _notification(what: int) -> void:
	# Android back button: step out of the run rather than closing the app.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if mode == Mode.PLAY:
			_pause()
		elif mode == Mode.PAUSED:
			to_title()
		else:
			get_tree().quit()


# --- run lifecycle -----------------------------------------------------------

func to_title() -> void:
	_prepare()
	mode = Mode.MENU
	hud.visible = false
	traj.visible = false
	menus.show_title()


func start_run() -> void:
	_prepare()
	mode = Mode.PLAY
	hud.visible = true
	traj.visible = true
	menus.hide_all()


func _pause() -> void:
	if mode != Mode.PLAY:
		return
	mode = Mode.PAUSED
	_end_gesture()
	menus.show_pause()


func _resume() -> void:
	if mode != Mode.PAUSED:
		return
	mode = Mode.PLAY
	menus.hide_all()


## Rebuilds the court and hangs the player on the home rim. Used by both the
## title backdrop and a real run, so the menu always shows a live arena.
func _prepare() -> void:
	theme = Skins.arena(SaveData.arena_id)
	RenderingServer.set_default_clear_color(theme.get("bg", BD.C_BG))
	crowd.theme = theme
	traj.color = theme.get("rim_target", BD.C_RIM_TARGET)

	court.reset(randi(), theme)
	court.ensure(0.0)

	baller.reset(Skins.baller(SaveData.baller_id))
	baller.hang(court.hoops[0])

	points = 0
	dunks = 0
	gold_taken = 0
	best_run_combo = 0
	best_height = 0.0
	_gesture = Gesture.NONE
	cam.position = baller.position + Vector2(0, -CAM_RISE)
	_sync_hud()


# --- frame -------------------------------------------------------------------

func _process(delta: float) -> void:
	match mode:
		Mode.PLAY:
			_step_play(delta)
		Mode.MENU:
			court.step(delta)
			baller.idle(delta)
		_:
			pass
	_update_camera(delta)

	crowd.cam_pos = cam.position
	crowd.view_size = get_viewport_rect().size
	crowd.zoom = cam.zoom.x
	crowd.queue_redraw()


func _step_play(delta: float) -> void:
	court.ensure(-baller.position.y, baller.host)
	# The court moves first: a player hanging on a sliding rim reads its position
	# this frame, and the preview has to agree with where things actually are.
	court.step(delta)
	baller.step(delta, court)
	if baller.state == Baller.State.DEAD:
		return
	_collect_gold()
	_check_hazards()
	if baller.state == Baller.State.DEAD:
		return
	_update_trajectory()
	_check_bounds()
	best_height = maxf(best_height, -baller.position.y)
	_sync_hud()


## Runs the same prediction the player will actually follow, draws it, and marks
## the rim it lands on so that basket lights up.
func _update_trajectory() -> void:
	var pred := baller.predict(court)
	traj.points = pred.points
	traj.target = pred.target
	traj.blocked = pred.blocked
	traj.show_aim = baller.state == Baller.State.HANG
	traj.aim_origin = baller.position
	# The arrow points along the *launch*, not along the raw aim. On a sliding
	# rim those differ by the rim's carry, and an arrow that disagreed with the
	# dotted line leaving the same point would read as a bug in the preview.
	traj.aim_dir = baller.launch_velocity().normalized()
	traj.aim_power = baller.aim_power
	traj.queue_redraw()
	for h in court.hoops:
		h.is_target = h == pred.target
		h.is_host = h == baller.host


func _collect_gold() -> void:
	for g in court.golds.duplicate():
		if baller.position.distance_to(g.position) < g.radius + BD.BALLER_R + 8.0:
			gold_taken += GoldBall.VALUE
			court.take_gold(g)


func _check_hazards() -> void:
	var p := baller.position
	for d in court.defenders:
		if p.distance_to(d.position) < d.radius + BD.BALLER_R:
			baller.die("Swatted by a defender")
			return
	for b in court.loose:
		if p.distance_to(b.position) < b.radius + BD.BALLER_R:
			baller.die("Hit by a loose ball")
			return


func _check_bounds() -> void:
	if -baller.position.y < best_height - BD.FALL_LIMIT:
		baller.die("Dropped out of the arena")
	elif absf(baller.position.x) > BD.COURT_BAND * BD.SIDE_LIMIT:
		baller.die("Out of bounds")


func _sync_hud() -> void:
	hud.points = points
	hud.clock = baller.shot_clock
	hud.air = baller.air / BD.AIR_MAX
	hud.combo = baller.combo
	hud.multiplier = baller.multiplier()
	hud.gold = gold_taken
	hud.status = _status()
	hud.refresh()


func _status() -> String:
	if baller.shot_clock < BD.CLOCK_WARN:
		return "SHOT CLOCK — get to a rim"
	if absf(baller.position.x) > BD.COURT_BAND * 1.4:
		return "OFF COURT — steer back toward the baskets"
	if -baller.position.y < best_height - BD.FALL_LIMIT * 0.6:
		return "FALLING — hold to hang"
	if baller.air <= 0.0:
		return "NO AIR — you can still jump"
	return ""


func _update_camera(delta: float) -> void:
	var lead := (baller.vel * CAM_LEAD).limit_length(CAM_LEAD_MAX)
	var target := baller.position + lead + Vector2(0, -CAM_RISE)
	# Exponential smoothing that behaves the same at any frame rate.
	cam.position = cam.position.lerp(target, 1.0 - pow(0.0015, delta))
	var want := lerpf(ZOOM_NEAR, ZOOM_FAR, clampf(baller.speed() / 1100.0, 0.0, 1.0))
	cam.zoom = cam.zoom.lerp(Vector2(want, want), 1.0 - pow(0.2, delta))


# --- events ------------------------------------------------------------------

func _on_scored(_h: Hoop, gained: int, swish: bool, bank: bool) -> void:
	points += gained
	best_run_combo = maxi(best_run_combo, baller.combo)
	if gained <= 0:
		# Re-dunking a rim you already scored on is a legal way to save a run,
		# but it does not pay twice.
		hud.toast("SAFE", Color(0.72, 0.78, 0.92))
		return
	dunks += 1
	var word := "DUNK"
	if swish and bank:
		word = "BANK SWISH!"
	elif swish:
		word = "SWISH!"
	elif bank:
		word = "OFF THE GLASS!"
	hud.toast("%s  +%d" % [word, gained], theme.get("rim_target", BD.C_RIM_TARGET))


func _on_clanged() -> void:
	hud.toast("CLANG", Color(1.0, 0.45, 0.40))


func _on_died(reason: String) -> void:
	if mode != Mode.PLAY:
		return
	mode = Mode.DEAD
	hud.visible = false
	traj.visible = false
	_end_gesture()
	var earned := SaveData.record_run(points, dunks, gold_taken, best_run_combo)
	menus.show_game_over(reason, points, dunks, gold_taken, best_run_combo, earned)


# --- input -------------------------------------------------------------------
#
# One thumb, two meanings, decided by where the player is: on a rim a touch aims
# the jump, in the air it holds them up. Mouse events cover both desktop and
# device, because Godot synthesises them from touch.

func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.PLAY or menus.any_visible():
		return

	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.button_index != MOUSE_BUTTON_LEFT:
			return
		if e.pressed:
			_begin_gesture(_to_world(e.position))
		else:
			_end_gesture()
	elif event is InputEventMouseMotion and _gesture != Gesture.NONE:
		var at := _to_world((event as InputEventMouseMotion).position)
		if _gesture == Gesture.AIM:
			baller.update_aim(at)
		else:
			baller.touch_point = at


func _begin_gesture(at: Vector2) -> void:
	if baller.state == Baller.State.HANG:
		_gesture = Gesture.AIM
		baller.begin_aim(at)
	elif baller.state == Baller.State.AIR:
		_gesture = Gesture.FLOAT
		baller.touch_point = at
		baller.floating = true


func _end_gesture() -> void:
	if _gesture == Gesture.AIM:
		baller.end_aim()
		baller.jump()
	baller.floating = false
	_gesture = Gesture.NONE


func _to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos
