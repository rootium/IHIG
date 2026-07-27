extends Node2D
## Game manager: owns the world, the ship, the camera and the screens, and
## arbitrates between them. Everything else in this project is deliberately
## unaware of game state.
##
## The run climbs upward, so "height" throughout means -position.y.

enum Mode { MENU, PLAY, PAUSED, DEAD }

const CAM_LEAD := 0.28      ## Fraction of velocity the camera looks ahead by.
const CAM_LEAD_MAX := 320.0
const CAM_RISE := 200.0     ## Ship sits below centre so you can see upward.
const SIDE_LIMIT := 2.4     ## Multiples of the world band before you are lost.

var mode: Mode = Mode.MENU
var theme: Dictionary = {}

var world: World
var ship: Ship
var stars: Starfield
var traj: Trajectory
var cam: Camera2D
var hud: HUD
var menus: Menus

var best_height: float = 0.0
var planets_visited: int = 0
var stars_taken: int = 0

var _visited: Dictionary = {}


func _ready() -> void:
	SaveData.load_game()

	stars = Starfield.new()
	stars.z_index = -100
	add_child(stars)

	world = World.new()
	add_child(world)

	traj = Trajectory.new()
	traj.z_index = 5
	add_child(traj)

	ship = Ship.new()
	ship.died.connect(_on_died)
	ship.captured.connect(_on_captured)
	add_child(ship)

	cam = Camera2D.new()
	cam.zoom = Vector2(0.62, 0.62)
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
	ship.thrusting = false
	ship.has_aim = false
	menus.show_pause()


func _resume() -> void:
	if mode != Mode.PAUSED:
		return
	mode = Mode.PLAY
	menus.hide_all()


## Rebuilds the world and parks the ship in the home orbit. Used by both the
## title backdrop and a real run, so the menu always shows live scenery.
func _prepare() -> void:
	theme = Skins.theme(SaveData.theme_id)
	RenderingServer.set_default_clear_color(theme.get("bg", PH.C_BG))
	stars.theme = theme
	traj.color = theme.get("ring", PH.C_RING)

	world.reset(randi(), theme)
	world.ensure(0.0)
	var home: Planet = world.planets[0]

	ship.reset(Skins.ship(SaveData.ship_id))
	ship.attach(home, home.orbit_radius(), PI, 1.0)

	_visited = {home.get_instance_id(): true}
	planets_visited = 1
	stars_taken = 0
	best_height = 0.0
	cam.position = ship.position + Vector2(0, -CAM_RISE)
	_sync_hud()


func height_score() -> int:
	return int(best_height / 100.0)


# --- frame -------------------------------------------------------------------

func _process(delta: float) -> void:
	match mode:
		Mode.PLAY:
			_step_play(delta)
		Mode.MENU:
			ship.idle(delta)
		_:
			pass
	_update_camera(delta)

	stars.cam_pos = cam.position
	stars.view_size = get_viewport_rect().size
	stars.zoom = cam.zoom.x
	stars.queue_redraw()


func _step_play(delta: float) -> void:
	world.ensure(-ship.position.y, ship.host)
	ship.step(delta, world)
	if ship.state == Ship.State.DEAD:
		return
	_collect_stars()
	_check_hazards()
	if ship.state == Ship.State.DEAD:
		return
	_update_trajectory()
	_check_bounds()
	best_height = maxf(best_height, -ship.position.y)
	_sync_hud()


## Runs the same prediction the ship will actually follow, draws it, and marks
## the planet it lands on so its ring lights up.
func _update_trajectory() -> void:
	var pred := ship.predict(world)
	traj.points = pred.points
	traj.target = pred.target
	traj.queue_redraw()
	for p in world.planets:
		p.is_target = p == pred.target
		p.is_host = p == ship.host


func _collect_stars() -> void:
	for s in world.stars.duplicate():
		if ship.position.distance_to(s.position) < s.radius + PH.SHIP_RADIUS + 10.0:
			stars_taken += StarPickup.VALUE
			world.take_star(s)


func _check_hazards() -> void:
	var p := ship.position
	for m in world.moons:
		if p.distance_to(m.position) < m.radius + PH.SHIP_RADIUS:
			ship.die("Clipped a moon")
			return
	for m in world.meteors:
		if p.distance_to(m.position) < m.radius + PH.SHIP_RADIUS:
			ship.die("Hit by a meteorite")
			return
	for h in world.holes:
		if p.distance_to(h.position) < h.radius + PH.SHIP_RADIUS:
			ship.die("Crossed the event horizon")
			return


func _check_bounds() -> void:
	if -ship.position.y < best_height - PH.FALL_LIMIT:
		ship.die("Fell back into the dark")
	elif absf(ship.position.x) > PH.WORLD_BAND * SIDE_LIMIT:
		ship.die("Drifted out of the corridor")


func _sync_hud() -> void:
	hud.oxygen = ship.oxygen / PH.OXY_MAX
	hud.fuel = ship.fuel / PH.FUEL_MAX
	hud.height = height_score()
	hud.stars = stars_taken
	hud.status = _status()
	hud.refresh()


func _status() -> String:
	if absf(ship.position.x) > PH.WORLD_BAND * 1.5:
		return "OFF COURSE — steer back toward the planets"
	if -ship.position.y < best_height - PH.FALL_LIMIT * 0.6:
		return "FALLING — burn upward"
	if ship.oxygen < PH.OXY_MAX * 0.25:
		return "OXYGEN LOW — find a green world"
	if ship.fuel <= 0.0:
		return "OUT OF FUEL — you can still break orbit"
	return ""


func _update_camera(delta: float) -> void:
	var lead := (ship.vel * CAM_LEAD).limit_length(CAM_LEAD_MAX)
	var target := ship.position + lead + Vector2(0, -CAM_RISE)
	# Exponential smoothing that behaves the same at any frame rate.
	cam.position = cam.position.lerp(target, 1.0 - pow(0.0015, delta))
	var want := lerpf(0.62, 0.5, clampf(ship.speed() / 650.0, 0.0, 1.0))
	cam.zoom = cam.zoom.lerp(Vector2(want, want), 1.0 - pow(0.2, delta))


# --- events ------------------------------------------------------------------

func _on_captured(p: Planet) -> void:
	var key := p.get_instance_id()
	if not _visited.has(key):
		_visited[key] = true
		planets_visited += 1


func _on_died(reason: String) -> void:
	if mode != Mode.PLAY:
		return
	mode = Mode.DEAD
	hud.visible = false
	traj.visible = false
	var earned := SaveData.record_run(height_score(), planets_visited, stars_taken)
	menus.show_game_over(reason, height_score(), planets_visited, stars_taken, earned)


# --- input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.PLAY or menus.any_visible():
		return

	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.button_index != MOUSE_BUTTON_LEFT:
			return
		if e.pressed:
			ship.aim_point = _to_world(e.position)
			ship.has_aim = true
			# One press does both jobs: leave orbit, then burn toward the finger.
			if ship.state == Ship.State.ORBIT:
				ship.launch()
			ship.thrusting = true
		else:
			ship.thrusting = false
			ship.has_aim = false
	elif event is InputEventMouseMotion and ship.thrusting:
		ship.aim_point = _to_world((event as InputEventMouseMotion).position)


func _to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos
