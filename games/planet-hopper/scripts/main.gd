extends Node2D
## Game manager: owns the world, the ship, the camera and the screens, and
## arbitrates between them. Everything else in this project is deliberately
## unaware of game state.

enum Mode { MENU, PLAY, DEAD }

const CAM_LEAD := 0.45      ## How far ahead of the ship the camera sits.
const OUT_OF_LANE := 2.2    ## Multiples of the world band before you are lost.
const BACKTRACK_LIMIT := 2600.0

var mode: Mode = Mode.MENU
var theme: Dictionary = {}

var world: World
var ship: Ship
var stars: Starfield
var cam: Camera2D
var hud: HUD
var menus: Menus

var best_x: float = 0.0
var planets_visited: int = 0

var _visited: Dictionary = {}


func _ready() -> void:
	SaveData.load_game()

	stars = Starfield.new()
	stars.z_index = -100
	add_child(stars)

	world = World.new()
	add_child(world)

	ship = Ship.new()
	ship.died.connect(_on_died)
	ship.captured.connect(_on_captured)
	add_child(ship)

	cam = Camera2D.new()
	cam.zoom = Vector2(0.7, 0.7)
	add_child(cam)
	cam.make_current()

	hud = HUD.new()
	add_child(hud)

	menus = Menus.new()
	menus.play_pressed.connect(start_run)
	menus.title_pressed.connect(to_title)
	add_child(menus)

	to_title()


func _notification(what: int) -> void:
	# Android back button: step out of the run rather than closing the app.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if mode == Mode.PLAY:
			to_title()
		else:
			get_tree().quit()


# --- run lifecycle -----------------------------------------------------------

func to_title() -> void:
	_prepare()
	mode = Mode.MENU
	hud.visible = false
	menus.show_title()


func start_run() -> void:
	_prepare()
	mode = Mode.PLAY
	hud.visible = true
	menus.hide_all()


## Rebuilds the world and parks the ship in the home orbit. Used by both the
## title backdrop and a real run, so the menu always shows live scenery.
func _prepare() -> void:
	theme = Skins.theme(SaveData.theme_id)
	RenderingServer.set_default_clear_color(theme.get("bg", PH.C_BG))
	stars.theme = theme

	world.reset(randi(), theme)
	world.ensure(0.0)
	var home: Planet = world.planets[0]

	ship.reset(Skins.ship(SaveData.ship_id))
	ship.attach(home, home.orbit_radius(), -PI * 0.5, 1.0)

	_visited = {home.get_instance_id(): true}
	planets_visited = 1
	best_x = 0.0
	cam.position = ship.position
	_sync_hud()


func distance_km() -> int:
	return int(best_x / 10.0)


# --- frame -------------------------------------------------------------------

func _process(delta: float) -> void:
	if mode == Mode.PLAY:
		_step_play(delta)
	else:
		ship.idle(delta)
	_update_camera(delta)

	stars.cam_pos = cam.position
	stars.view_size = get_viewport_rect().size
	stars.zoom = cam.zoom.x
	stars.queue_redraw()


func _step_play(delta: float) -> void:
	world.ensure(ship.position.x, ship.host)
	ship.step(delta, world)
	if ship.state == Ship.State.DEAD:
		return
	_check_hazards()
	_check_bounds()
	_update_hints()
	best_x = maxf(best_x, ship.position.x)
	_sync_hud()


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
	if absf(ship.position.y) > PH.WORLD_BAND * OUT_OF_LANE or ship.position.x < best_x - BACKTRACK_LIMIT:
		ship.die("Lost in deep space")


## Highlights the planet you are lined up for, and surfaces the one piece of
## advice a new player needs: you are coming in too hot to be caught.
func _update_hints() -> void:
	for pl in world.planets:
		pl.capture_ready = false

	var status := ""
	if ship.state == Ship.State.FLY:
		var near: Planet = null
		var best := INF
		for pl in world.planets:
			var d := ship.position.distance_to(pl.position) - pl.capture_radius()
			if d < best:
				best = d
				near = pl
		if near != null and best < 260.0:
			if ship.speed() <= near.capture_speed():
				near.capture_ready = true
			else:
				status = "TOO FAST — burn backwards to slow down"

	# Drifting out of the lane is fatal and there is nothing to see out there,
	# so it needs a warning well before the bound is reached.
	if absf(ship.position.y) > PH.WORLD_BAND * 1.45:
		status = "OFF COURSE — steer back toward the planets"
	if ship.oxygen < PH.OXY_MAX * 0.25:
		status = "OXYGEN LOW — find a green world"
	elif ship.fuel <= 0.0 and status == "":
		status = "OUT OF FUEL — you can still break orbit"
	hud.status = status


func _update_camera(delta: float) -> void:
	var target := ship.position + ship.vel * CAM_LEAD
	# Exponential smoothing that behaves the same at any frame rate.
	cam.position = cam.position.lerp(target, 1.0 - pow(0.0015, delta))
	var want := lerpf(0.72, 0.48, clampf(ship.speed() / 700.0, 0.0, 1.0))
	cam.zoom = cam.zoom.lerp(Vector2(want, want), 1.0 - pow(0.2, delta))


func _sync_hud() -> void:
	hud.oxygen = ship.oxygen / PH.OXY_MAX
	hud.fuel = ship.fuel / PH.FUEL_MAX
	hud.distance = distance_km()
	hud.refresh()


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
	var earned := SaveData.record_run(distance_km(), planets_visited)
	menus.show_game_over(reason, distance_km(), planets_visited, earned)


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
