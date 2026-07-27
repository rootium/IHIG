extends SceneTree
## Headless smoke test: flies an autopilot through the real world/ship code for
## a few simulated minutes, restarting on each death.
##
## It is not checking that the game is *fun* — it is checking that chunk
## generation, culling, capture, gravity and the draw calls survive a long run
## without erroring. Any push_error or script crash fails the process.
##
##   godot --headless --path . --script tests/smoke_test.gd

const DEFAULT_FRAMES := 12000  ## ~200 s at a fixed 60 Hz step.
const DT := 1.0 / 60.0

## Override the length with: ... --script tests/smoke_test.gd -- 45000
var frame_budget: int = DEFAULT_FRAMES

var world: World
var ship: Ship

var _frames := 0
var _dwell := 0.0
var _deaths := 0
var _captures := 0
var _max_x := 0.0
var _reasons: Dictionary = {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		frame_budget = int(args[0])
	world = World.new()
	get_root().add_child(world)
	ship = Ship.new()
	ship.died.connect(_on_died)
	ship.captured.connect(func(_p: Planet) -> void: _captures += 1)
	get_root().add_child(ship)
	_respawn()


func _process(_delta: float) -> bool:
	world.ensure(ship.position.x, ship.host)
	_autopilot()
	ship.step(DT, world)
	_max_x = maxf(_max_x, ship.position.x)
	# Main applies the same lane bound; mirror it so a stray hop ends the life
	# instead of drifting into empty space for the rest of the test.
	if absf(ship.position.y) > PH.WORLD_BAND * 2.2:
		ship.die("Lost in deep space")

	if ship.state == Ship.State.DEAD:
		_respawn()

	_frames += 1
	if _frames < frame_budget:
		return false

	print("--- planet hopper smoke test ---")
	print("frames:          %d" % _frames)
	print("captures:        %d" % _captures)
	print("deaths:          %d" % _deaths)
	print("max x reached:   %.0f (%d chunks)" % [_max_x, int(_max_x / PH.CHUNK_W)])
	print("live planets:    %d" % world.planets.size())
	print("live moons:      %d" % world.moons.size())
	print("live meteors:    %d" % world.meteors.size())
	print("live holes:      %d" % world.holes.size())
	for r in _reasons:
		print("death: %-32s x%d" % [r, _reasons[r]])
	print("OK")
	return true


func _respawn() -> void:
	world.reset(randi(), Skins.theme("deep_field"))
	world.ensure(0.0)
	ship.reset(Skins.ship("scout"))
	var home: Planet = world.planets[0]
	ship.attach(home, home.orbit_radius(), -PI * 0.5, 1.0)
	_dwell = 0.0


func _on_died(reason: String) -> void:
	_deaths += 1
	_reasons[reason] = int(_reasons.get(reason, 0)) + 1


## Plays roughly the way a competent human does: wait in orbit until the
## tangent lines up with the next planet, launch, steer, then retro-burn on
## approach so the capture ring can catch you.
func _autopilot() -> void:
	var target := _next_planet()

	if ship.state == Ship.State.ORBIT:
		ship.thrusting = false
		ship.has_aim = false
		_dwell += DT
		if target == null:
			return
		var aligned := ship.vel.normalized().dot((target.position - ship.position).normalized())
		# Launch on a good tangent, or give up waiting and go anyway.
		if (_dwell > 0.25 and aligned > 0.94) or _dwell > 5.0:
			_dwell = 0.0
			ship.launch()
		return

	if target == null:
		ship.has_aim = false
		ship.thrusting = false
		return

	var gap := ship.position.distance_to(target.position) - target.capture_radius()
	ship.has_aim = true
	if gap < 420.0 and ship.speed() > target.capture_speed() * 0.8:
		# Retro-burn: aim behind the direction of travel.
		ship.aim_point = ship.position - ship.vel.normalized() * 600.0
		ship.thrusting = ship.fuel > 0.0
	else:
		ship.aim_point = target.position
		var off := ship.vel.normalized().dot((target.position - ship.position).normalized())
		ship.thrusting = ship.fuel > 0.0 and (off < 0.97 or ship.speed() < 220.0)


func _next_planet() -> Planet:
	var best: Planet = null
	var best_d := INF
	for p in world.planets:
		if p == ship.host or p.position.x < ship.position.x - 200.0:
			continue
		var d := ship.position.distance_to(p.position)
		if d < best_d:
			best_d = d
			best = p
	return best
