extends SceneTree
## Headless smoke test: climbs an autopilot through the real world and ship code
## for a few simulated minutes, restarting on each death.
##
## It is not checking that the game is *fun* — it is checking that chunk
## generation, culling, capture, gravity, prediction and the draw calls survive
## a long run without erroring. Any script error fails the process.
##
## The autopilot aims the way a player is meant to: it sits in orbit watching
## Ship.predict() and launches the moment the predicted path lands on a planet
## higher than the one it is on. It never thrusts to steer, only to arrest a
## fall — so a healthy capture count here means the trajectory preview alone is
## enough to play the game, which is the whole design bet.
##
##   godot --headless --path . --script tests/smoke_test.gd [-- FRAMES]

const DEFAULT_FRAMES := 12000  ## ~200 s at a fixed 60 Hz step.
const DT := 1.0 / 60.0

var frame_budget: int = DEFAULT_FRAMES

var world: World
var ship: Ship

var _frames := 0
var _dwell := 0.0
var _deaths := 0
var _captures := 0
var _stars := 0
var _max_h := 0.0
var _best_run := 0.0
var _reasons: Dictionary = {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		frame_budget = int(args[0])

	world = World.new()
	get_root().add_child(world)
	ship = Ship.new()
	ship.died.connect(_on_died)
	ship.captured.connect(_on_captured)
	get_root().add_child(ship)
	_respawn()


func _process(_delta: float) -> bool:
	world.ensure(-ship.position.y, ship.host)
	_autopilot()
	ship.step(DT, world)

	var h := -ship.position.y
	_best_run = maxf(_best_run, h)
	_max_h = maxf(_max_h, h)
	_collect_stars()

	# Main applies the same bounds; mirror them so a botched hop ends the life
	# instead of drifting for the rest of the test.
	if h < _best_run - PH.FALL_LIMIT:
		ship.die("Fell back into the dark")
	elif absf(ship.position.x) > PH.WORLD_BAND * 2.4:
		ship.die("Drifted out of the corridor")

	if ship.state == Ship.State.DEAD:
		_respawn()

	_frames += 1
	if _frames < frame_budget:
		return false

	print("--- planet hopper smoke test ---")
	print("frames:          %d" % _frames)
	print("captures:        %d" % _captures)
	print("stars collected: %d" % _stars)
	print("deaths:          %d" % _deaths)
	print("max height:      %.0f (%d chunks)" % [_max_h, int(_max_h / PH.CHUNK_H)])
	print("live planets:    %d" % world.planets.size())
	print("live moons:      %d" % world.moons.size())
	print("live meteors:    %d" % world.meteors.size())
	print("live holes:      %d" % world.holes.size())
	print("live stars:      %d" % world.stars.size())
	for r in _reasons:
		print("death: %-32s x%d" % [r, _reasons[r]])
	print("OK")
	return true


func _respawn() -> void:
	world.reset(randi(), Skins.theme("deep_field"))
	world.ensure(0.0)
	ship.reset(Skins.ship("scout"))
	var home: Planet = world.planets[0]
	ship.attach(home, home.orbit_radius(), PI, 1.0)
	_dwell = 0.0
	_best_run = 0.0


func _on_died(reason: String) -> void:
	_deaths += 1
	_reasons[reason] = int(_reasons.get(reason, 0)) + 1


func _on_captured(_p: Planet) -> void:
	_captures += 1
	_dwell = 0.0


func _collect_stars() -> void:
	for s in world.stars.duplicate():
		if ship.position.distance_to(s.position) < s.radius + PH.SHIP_RADIUS + 10.0:
			_stars += StarPickup.VALUE
			world.take_star(s)


func _autopilot() -> void:
	if ship.state == Ship.State.ORBIT:
		ship.thrusting = false
		ship.has_aim = false
		_dwell += DT
		var pred := ship.predict(world)
		var target: Planet = pred.target
		# Launch when the preview says we land somewhere higher up.
		if target != null and target.position.y < ship.position.y - 120.0:
			ship.launch()
		elif _dwell > 9.0:
			ship.launch()  # nothing good in view; go anyway rather than suffocate
		return

	# Coast by default — the point is to prove the preview is enough. Thrust is
	# only for arresting a fall that the preview did not save us from.
	ship.has_aim = false
	ship.thrusting = false
	if ship.vel.y > 140.0 and ship.fuel > 0.0:
		ship.has_aim = true
		ship.aim_point = ship.position + Vector2(0, -600)
		ship.thrusting = true
