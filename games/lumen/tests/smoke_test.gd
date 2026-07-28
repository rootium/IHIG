extends SceneTree
## Headless soak test over the generator.
##
## Lumen makes one promise a player cannot check for themselves — that every
## level it hands them can actually be solved — so this is the test that matters.
## For each level it asserts, through the same tracer the game renders with:
##
##   * the level generates at all;
##   * the orientations it calls the solution really do light every target;
##   * the orientations it hands the player really do not (it is a puzzle);
##   * par matches the work: turning exactly the pieces that disagree with the
##     solution, and no others, solves the board in exactly par taps;
##   * building the same level twice gives byte-identical boards, because level
##     numbers are supposed to mean the same thing on every device.
##
## Any failure, and any script error, fails the process.
##
## It also reports the shape of the ladder in bands, which is not a pass/fail
## thing but is the only way to see whether difficulty is still going anywhere.
## Averaged over the whole run, a ramp that flattens out at level 26 looks
## identical to one that does not.
##
##   godot --headless --path . --script tests/smoke_test.gd [-- LEVELS]

const DEFAULT_LEVELS := 500
const BANDS := [1, 6, 15, 26, 60, 136, 300]

var levels: int = DEFAULT_LEVELS

var _failures: int = 0
var _stats: Dictionary = {}   ## band start -> tallies


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		levels = int(args[0])

	var started := Time.get_ticks_msec()
	for level in range(1, levels + 1):
		_check(level)
	var elapsed := Time.get_ticks_msec() - started

	print("--- lumen generator soak test ---")
	print("levels:   %d" % levels)
	print("failures: %d" % _failures)
	print("time:     %d ms (%.2f ms/level)" % [elapsed, float(elapsed) / float(levels)])
	print("")
	print("%-12s %6s %6s %7s %7s %7s %7s %7s" % [
		"levels", "n", "cells", "par", "pieces", "targets", "mix%", "split%"])
	for band in BANDS:
		var s: Dictionary = _stats.get(band, {})
		var n := int(s.get("n", 0))
		if n == 0:
			continue
		print("%-12s %6d %6.1f %7.2f %7.2f %7.2f %7.0f %7.0f" % [
			_band_name(band), n,
			float(s.cells) / n, float(s.par) / n, float(s.pieces) / n, float(s.targets) / n,
			100.0 * float(s.mix) / n, 100.0 * float(s.split) / n])
	print("FAIL" if _failures > 0 else "OK")
	quit(1 if _failures > 0 else 0)


func _check(level: int) -> void:
	var g := Generator.build(level)
	if g == null:
		_fail(level, "generator returned nothing")
		return

	var targets := 0
	var split := false
	var mixed := false
	for cell in g.size():
		match g.kind[cell]:
			Grid.Kind.SPLITTER:
				split = true
			Grid.Kind.TARGET:
				targets += 1
				# Exactly two channels means two sources had to agree on it.
				# Three is plain white light, which any single source emits.
				var tint := int(g.tint[cell])
				if tint == (LM.R | LM.G) or tint == (LM.R | LM.B) or tint == (LM.G | LM.B):
					mixed = true
			_:
				pass
	_tally(level, g, targets, mixed, split)

	if targets == 0:
		_fail(level, "no targets")
	if g.movable.is_empty():
		_fail(level, "nothing to tap")
	if g.par < 1:
		_fail(level, "par %d" % g.par)

	# The level as handed to the player must not already be finished.
	g.restart()
	if _solved(g):
		_fail(level, "starts solved")

	# ...and turning exactly the disagreeing pieces must finish it, in par taps.
	var taps := 0
	while true:
		var cell := g.wrong_piece()
		if cell < 0:
			break
		g.toggle(cell)
		taps += 1
		if taps > g.movable.size():
			_fail(level, "wrong_piece() will not converge")
			return
	if not _solved(g):
		_fail(level, "solution orientations do not light the board")
	if taps != g.par:
		_fail(level, "took %d taps against par %d" % [taps, g.par])

	var twin := Generator.build(level)
	if twin.w != g.w or twin.h != g.h or twin.kind != g.kind \
			or twin.tint != g.tint or twin.start != g.start or twin.solution != g.solution:
		_fail(level, "not deterministic")


func _tally(level: int, g: Grid, targets: int, mixed: bool, split: bool) -> void:
	var band: int = BANDS[0]
	for b in BANDS:
		if level >= b:
			band = b
	if not _stats.has(band):
		_stats[band] = {"n": 0, "cells": 0, "par": 0, "pieces": 0,
			"targets": 0, "mix": 0, "split": 0}
	var s: Dictionary = _stats[band]
	s.n += 1
	s.cells += g.size()
	s.par += g.par
	s.pieces += g.movable.size()
	s.targets += targets
	s.mix += 1 if mixed else 0
	s.split += 1 if split else 0


func _band_name(band: int) -> String:
	var i := BANDS.find(band)
	if i == BANDS.size() - 1:
		return "%d+" % band
	return "%d-%d" % [band, int(BANDS[i + 1]) - 1]


func _solved(g: Grid) -> bool:
	return Beam.solved(g, Beam.trace(g).recv)


func _fail(level: int, why: String) -> void:
	_failures += 1
	printerr("level %d: %s" % [level, why])
