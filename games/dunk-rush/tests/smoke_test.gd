extends SceneTree
## Headless smoke test: runs an autopilot up the real court and player code for
## a few simulated minutes, restarting on each death.
##
## It is not checking that the game is *fun* — it is checking that chunk
## generation, culling, scoring, clangs, banking, prediction and the draw calls
## survive a long run without erroring. Any script error fails the process.
##
## The autopilot plays the way a player is meant to: standing on a rim it sweeps
## Baller.predict() across a fan of aims and takes the one the preview says
## lands on a higher basket. It never floats to steer, only to arrest a fall —
## so the dunk count here is a direct measurement of whether the aim preview
## alone is enough to play the game, which is the whole design bet.
##
##   godot --headless --path . --script tests/smoke_test.gd [-- FRAMES]

const DEFAULT_FRAMES := 12000  ## ~200 s at a fixed 60 Hz step.
const DT := 1.0 / 60.0

## The autopilot aims the way a thumb does: sweep a coarse fan, see which way
## the line went, then narrow in. A single coarse grid is not a fair model of a
## player — 9 degrees of angle is about 78px of drift at the range of the next
## rim, wider than the scoring band, so a grid that size straddles every
## solution and concludes the game is impossible when it is not.
const PLAN_ANGLES := 17
const PLAN_POWERS := 4
const PLAN_REFINES := 3        ## Narrowing passes after the coarse sweep.
const PLAN_SHRINK := 0.32      ## How much the search window narrows each pass.
const REPLAN_EVERY := 0.25     ## Rims slide, so a failed search is worth retrying.
const DESPERATION := 7.0       ## Jump anyway rather than eat the shot clock.

var frame_budget: int = DEFAULT_FRAMES

var court: Court
var baller: Baller

var _frames := 0
var _dwell := 0.0
var _since_plan := 0.0
var _planned := false
var _deaths := 0
var _dunks := 0
var _clangs := 0
var _banks := 0
var _swishes := 0
var _blind_jumps := 0
var _gold := 0
var _points := 0
var _max_h := 0.0
var _best_run := 0.0
var _best_combo := 0
var _reasons: Dictionary = {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		frame_budget = int(args[0])

	court = Court.new()
	get_root().add_child(court)
	baller = Baller.new()
	baller.died.connect(_on_died)
	baller.scored.connect(_on_scored)
	baller.clanged.connect(_on_clanged)
	get_root().add_child(baller)
	_respawn()


func _process(_delta: float) -> bool:
	court.ensure(-baller.position.y, baller.host)
	court.step(DT)
	_autopilot()
	baller.step(DT, court)

	var h := -baller.position.y
	_best_run = maxf(_best_run, h)
	_max_h = maxf(_max_h, h)
	_best_combo = maxi(_best_combo, baller.combo)
	_collect_gold()
	_check_hazards()

	# Main applies the same bounds; mirror them so a botched jump ends the life
	# instead of drifting for the rest of the test.
	if baller.state != Baller.State.DEAD:
		if h < _best_run - BD.FALL_LIMIT:
			baller.die("Dropped out of the arena")
		elif absf(baller.position.x) > BD.COURT_BAND * BD.SIDE_LIMIT:
			baller.die("Out of bounds")

	if baller.state == Baller.State.DEAD:
		_respawn()

	_frames += 1
	if _frames < frame_budget:
		return false

	print("--- dunk rush smoke test ---")
	print("frames:          %d" % _frames)
	print("dunks:           %d" % _dunks)
	print("  swishes:       %d" % _swishes)
	print("  banked:        %d" % _banks)
	print("points:          %d" % _points)
	print("best combo:      %d" % _best_combo)
	print("clangs:          %d" % _clangs)
	print("blind jumps:     %d" % _blind_jumps)
	print("gold collected:  %d" % _gold)
	print("deaths:          %d" % _deaths)
	print("max height:      %.0f (%d chunks)" % [_max_h, int(_max_h / BD.CHUNK_H)])
	print("live hoops:      %d" % court.hoops.size())
	print("live defenders:  %d" % court.defenders.size())
	print("live balls:      %d" % court.loose.size())
	print("live gold:       %d" % court.golds.size())
	for r in _reasons:
		print("death: %-32s x%d" % [r, _reasons[r]])
	print("OK")
	return true


func _respawn() -> void:
	court.reset(randi(), Skins.arena("night_court"))
	court.ensure(0.0)
	baller.reset(Skins.baller("rookie"))
	baller.hang(court.hoops[0])
	_dwell = 0.0
	_since_plan = REPLAN_EVERY
	_planned = false
	_best_run = 0.0


func _on_died(reason: String) -> void:
	_deaths += 1
	_reasons[reason] = int(_reasons.get(reason, 0)) + 1


func _on_scored(_h: Hoop, gained: int, swish: bool, bank: bool) -> void:
	_points += gained
	if gained > 0:
		_dunks += 1
	if swish:
		_swishes += 1
	if bank:
		_banks += 1
	_dwell = 0.0
	_planned = false
	_since_plan = REPLAN_EVERY


func _on_clanged() -> void:
	_clangs += 1


func _collect_gold() -> void:
	for g in court.golds.duplicate():
		if baller.position.distance_to(g.position) < g.radius + BD.BALLER_R + 8.0:
			_gold += GoldBall.VALUE
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


# --- autopilot ---------------------------------------------------------------

func _autopilot() -> void:
	if baller.state == Baller.State.HANG:
		baller.floating = false
		_dwell += DT
		_since_plan += DT
		if not _planned and _since_plan >= REPLAN_EVERY:
			_since_plan = 0.0
			_planned = _plan()
		if _planned:
			baller.jump()
			_planned = false
		elif _dwell > DESPERATION:
			# Nothing in view. Take the best near-miss the search found rather
			# than stand still until the shot clock runs out.
			_blind_jumps += 1
			baller.jump()
		return

	# Coast by default — the point is to prove the preview is enough. Air is only
	# for arresting a fall the preview did not save us from.
	baller.floating = false
	if baller.vel.y > 520.0 and baller.air > 0.0:
		baller.touch_point = baller.position
		baller.floating = true


## Searches for an aim whose preview lands on a higher basket, and leaves the
## player aimed at it. Returns false when even a narrowed search cannot find one.
##
## A coarse sweep first, then a few passes that narrow the window around the
## most promising aim so far. "Most promising" is the closest the predicted path
## came to a rim above us, which is exactly the feedback a player reads off the
## dotted line when their first drag comes up short.
func _plan() -> bool:
	if not is_instance_valid(baller.host):
		return false

	var a_mid := -PI * 0.5
	var a_half := (PI - 2.0 * BD.AIM_MIN_ELEVATION) * 0.5
	var p_mid := 0.7
	var p_half := 0.3

	var best_a := a_mid
	var best_p := p_mid
	var best_cost := INF
	var hit := false

	for pass_i in PLAN_REFINES + 1:
		for i in PLAN_ANGLES:
			var a := a_mid + a_half * (2.0 * float(i) / float(PLAN_ANGLES - 1) - 1.0)
			for j in PLAN_POWERS:
				var p := clampf(p_mid + p_half * (2.0 * float(j) / float(PLAN_POWERS - 1) - 1.0),
						0.0, 1.0)
				var cost := _cost_of(a, p)
				if cost >= best_cost:
					continue
				best_cost = cost
				best_a = a
				best_p = p
				if cost <= 0.0:
					hit = true
		if hit:
			break
		# Narrow around the best near-miss and look again.
		a_mid = best_a
		p_mid = best_p
		a_half *= PLAN_SHRINK
		p_half *= PLAN_SHRINK

	baller.aim_dir = Vector2.from_angle(best_a)
	baller.aim_power = best_p
	return hit


## 0 when the preview dunks on a rim above us, otherwise how close the predicted
## path got to the nearest such rim. Lower is better, so the search can hill-
## climb toward a basket it has not hit yet.
func _cost_of(angle: float, power: float) -> float:
	baller.aim_dir = Vector2.from_angle(angle)
	baller.aim_power = power
	var from_y := baller.position.y - 60.0  # a genuine gain, not a sideways shuffle
	var pred := baller.predict(court)
	var target: Hoop = pred.target
	if target != null and target.position.y < from_y:
		return 0.0

	var best := INF
	for h in court.hoops:
		if h.position.y >= from_y:
			continue
		for p: Vector2 in pred.points:
			best = minf(best, p.distance_squared_to(h.position))
	return best
