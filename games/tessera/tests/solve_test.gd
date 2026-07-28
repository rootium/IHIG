extends SceneTree

## Replays every chamber's optimal solution through the real game.
##
## The generator proves each chamber solvable with its own model of the rules.
## This proves that model is the same as the one the game actually runs: each
## recorded solution is fed through Game.try_walk / try_shift / try_rotate, and
## the chamber has to open in exactly the number of moves the generator claimed.
## If the two ever drift — a change to the step-up rule, to gravity, to what
## counts as blocking — every chamber past the change fails here.
##
##   godot --headless --path games/tessera -s tests/solve_test.gd
##
## Two things about running under -s are load-bearing here.
##
## The locals are untyped on purpose: a script run with -s is compiled before
## the autoloads are registered, so naming the Game type would pull in
## scripts/game.gd, which refers to Audio, and the test would fail to compile
## before it ran. Everything reaches the game through main.tscn at runtime
## instead, by which point the autoloads exist.
##
## And the work happens on the first frame rather than in _initialize(),
## because a node added before the tree starts does not get its _ready() until
## then — in _initialize() the game exists but has not built itself yet.

const SETTLE_DELTA := 4.0     ## longer than any single animation in the game

var _main


func _initialize() -> void:
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	var main = _main
	var game = main.game
	main.ui.go(main.ui.Screen.PLAY)

	var failures: Array[String] = []
	var moves_replayed := 0

	for i in Campaign.count():
		var lv := Campaign.get_level(i)
		var actions := Campaign.solution(i)
		game.load_level(lv)

		var refused := ""
		for a in actions:
			if not _apply(game, a):
				refused = a
				break
			_settle(game)
			if game.is_solved():
				break

		if refused != "":
			failures.append("%-22s (%2d) refused '%s' after %d moves"
				% [lv.name, i, refused, game.moves])
		elif not game.is_solved():
			failures.append("%-22s (%2d) ran out of moves short of the exit"
				% [lv.name, i, lv.par])
		elif game.moves != lv.par:
			failures.append("%-22s (%2d) opened in %d moves but par is %d"
				% [lv.name, i, game.moves, lv.par])
		else:
			moves_replayed += game.moves

	print("")
	if failures.is_empty():
		print("PASS  %d chambers, %d moves replayed, every one optimal"
			% [Campaign.count(), moves_replayed])
		quit(0)
	else:
		for f in failures:
			print("FAIL  ", f)
		print("\nFAILED  %d of %d chambers" % [failures.size(), Campaign.count()])
		quit(1)
	return true


## "w2+" walk along frame slot 2, "s-" step kata, "r0+" turn slot 0 into hidden.
func _apply(game, action: String) -> bool:
	var sign := 1 if action.ends_with("+") else -1
	match action[0]:
		"w": return game.try_walk(int(action[1]), sign)
		"s": return game.try_shift(sign)
		"r": return game.try_rotate(int(action[1]), sign)
	return false


## Run the state machine forward until it settles, so the next action is legal.
func _settle(game) -> void:
	for _i in 64:
		if game.is_idle() or game.is_solved():
			return
		game._process(SETTLE_DELTA)
