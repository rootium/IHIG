extends Node

## Every sound in the game is synthesised here at startup. Nothing is
## downloaded and nothing is sampled: each effect is a few hundred milliseconds
## of arithmetic, which costs less to generate than a file of the same sound
## would cost to load.
##
## The music is the exception — see res://audio/, rendered offline by
## tools/tessera/make_music.py, because a two minute bed is not something you
## want to compute on a phone at boot.

const RATE := 22050
const VOICES := 10

var sfx_volume := 0.85
var music_volume := 0.55

var _bank := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _music_tracks := {}
var _current_track := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Master"
	add_child(_music)
	_build_bank()


# --- synthesis ----------------------------------------------------------------

func _render(dur: float, fn: Callable) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v: float = clampf(fn.call(t, float(i) / float(n)), -1.0, 1.0)
		var s := int(v * 32000.0)
		data.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


static func _noise(t: float) -> float:
	var x := sin(t * 12543.9898) * 43758.5453
	return (x - floor(x)) * 2.0 - 1.0


## Decay envelope with a short attack, which is all a percussive effect needs.
static func _env(p: float, attack: float, curve: float) -> float:
	if p < attack:
		return p / maxf(attack, 1e-5)
	return pow(1.0 - (p - attack) / maxf(1.0 - attack, 1e-5), curve)


func _build_bank() -> void:
	# A footstep: a soft wooden knock with a little grit.
	_bank["step"] = _render(0.085, func(t: float, p: float) -> float:
		var e := _env(p, 0.02, 2.4)
		return (sin(TAU * 210.0 * t) * 0.6 + _noise(t) * 0.25 * _env(p, 0.005, 6.0)) * e * 0.42)

	_bank["land"] = _render(0.16, func(t: float, p: float) -> float:
		var e := _env(p, 0.01, 2.0)
		var f := 150.0 * (1.0 - p * 0.45)
		return (sin(TAU * f * t) * 0.8 + _noise(t) * 0.2 * _env(p, 0.004, 8.0)) * e * 0.5)

	# Ana and kata: a glide along the axis you cannot see, up or down.
	for s in [1, -1]:
		var up: bool = s > 0
		_bank["shift%d" % s] = _render(0.42, func(t: float, p: float) -> float:
			var e := _env(p, 0.06, 1.5)
			var a := 330.0
			var b := 660.0 if up else 165.0
			var f: float = lerpf(a, b, p * p)
			var v := sin(TAU * f * t) * 0.5
			v += sin(TAU * f * 2.005 * t) * 0.22
			v += sin(TAU * f * 3.01 * t) * 0.1
			# a breath of noise so it does not read as a pure test tone
			v += _noise(t * 1.3) * 0.06 * sin(PI * p)
			return v * e * 0.5)

	# The quarter turn into the fourth dimension: two detuned sweeps crossing,
	# with a rising shimmer on top. It is the biggest sound in the game.
	_bank["rotate"] = _render(0.95, func(t: float, p: float) -> float:
		var e := sin(PI * pow(p, 0.75))
		var down: float = lerpf(420.0, 118.0, p)
		var up: float = lerpf(118.0, 420.0, p)
		var v := sin(TAU * down * t) * 0.34 + sin(TAU * up * t * 1.005) * 0.34
		v += sin(TAU * up * 3.0 * t) * 0.12 * p
		v += sin(TAU * (up * 6.0 + 40.0 * sin(TAU * 3.0 * t)) * t) * 0.07 * p * p
		v += _noise(t) * 0.05 * sin(PI * p)
		return v * e * 0.5)

	_bank["deny"] = _render(0.14, func(t: float, p: float) -> float:
		var e := _env(p, 0.005, 3.0)
		return (sin(TAU * 88.0 * t) * 0.5 + sin(TAU * 93.0 * t) * 0.5) * e * 0.45)

	# Pickups: struck-bell partials, gold for shards and warmer for sigils.
	for k in 2:
		var root := 880.0 if k == 0 else 587.33
		_bank["pickup%d" % k] = _render(0.55, func(t: float, p: float) -> float:
			var e := _env(p, 0.004, 2.6)
			var v := sin(TAU * root * t) * 0.5
			v += sin(TAU * root * 2.76 * t) * 0.26 * _env(p, 0.002, 4.5)
			v += sin(TAU * root * 5.4 * t) * 0.12 * _env(p, 0.002, 7.0)
			return v * e * 0.45)

	# The way out: a major triad arriving one note at a time.
	_bank["win"] = _render(1.5, func(t: float, p: float) -> float:
		var notes := [523.25, 659.25, 783.99, 1046.5]
		var v := 0.0
		for i in notes.size():
			var start := float(i) * 0.11
			if p < start:
				continue
			var q := (p - start) / maxf(1.0 - start, 1e-4)
			v += sin(TAU * notes[i] * t) * _env(q, 0.01, 2.2) * 0.24
			v += sin(TAU * notes[i] * 2.0 * t) * _env(q, 0.01, 3.4) * 0.07
		return v * 0.85)

	_bank["die"] = _render(0.7, func(t: float, p: float) -> float:
		var e := _env(p, 0.01, 1.6)
		var f: float = lerpf(300.0, 55.0, pow(p, 0.6))
		return (sin(TAU * f * t) * 0.55 + _noise(t) * 0.35 * (1.0 - p)) * e * 0.5)

	_bank["undo"] = _render(0.24, func(t: float, p: float) -> float:
		var e := sin(PI * p)
		var f: float = lerpf(180.0, 520.0, p)
		return sin(TAU * f * t) * e * 0.32)

	_bank["reset"] = _render(0.34, func(t: float, p: float) -> float:
		var e := _env(p, 0.02, 1.8)
		var f: float = lerpf(620.0, 240.0, p)
		return (sin(TAU * f * t) * 0.5 + sin(TAU * f * 1.5 * t) * 0.2) * e * 0.36)

	_bank["camera"] = _render(0.09, func(t: float, p: float) -> float:
		return _noise(t) * _env(p, 0.004, 5.0) * 0.16)

	_bank["ui"] = _render(0.07, func(t: float, p: float) -> float:
		return sin(TAU * 1320.0 * t) * _env(p, 0.004, 4.0) * 0.22)

	_bank["ui_big"] = _render(0.3, func(t: float, p: float) -> float:
		var e := _env(p, 0.006, 2.6)
		return (sin(TAU * 392.0 * t) * 0.4 + sin(TAU * 587.33 * t) * 0.3) * e * 0.4)


# --- playback -----------------------------------------------------------------

func play(name: String, pitch := 1.0, gain := 1.0) -> void:
	if not _bank.has(name) or sfx_volume <= 0.001:
		return
	var p := _pool[_next]
	_next = (_next + 1) % VOICES
	p.stream = _bank[name]
	p.pitch_scale = pitch
	p.volume_db = linear_to_db(clampf(sfx_volume * gain, 0.0001, 1.0))
	p.play()


func step() -> void: play("step", randf_range(0.94, 1.07))
func land() -> void: play("land", randf_range(0.96, 1.04))
func shift(sign: int) -> void: play("shift%d" % sign)
func rotate() -> void: play("rotate")
func deny() -> void: play("deny")
func pickup(k: int) -> void: play("pickup%d" % k)
func win() -> void: play("win")
func die() -> void: play("die")
func undo() -> void: play("undo")
func reset() -> void: play("reset")
func camera() -> void: play("camera")
func ui() -> void: play("ui")
func ui_big() -> void: play("ui_big")


func music(track: String) -> void:
	if _current_track == track:
		return
	_current_track = track
	if track == "":
		_music.stop()
		return
	if not _music_tracks.has(track):
		var path := "res://audio/%s.wav" % track
		if not ResourceLoader.exists(path):
			return
		_music_tracks[track] = load(path)
	_music.stream = _music_tracks[track]
	_music.volume_db = linear_to_db(maxf(music_volume, 0.0001))
	_music.play()


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_music.volume_db = linear_to_db(maxf(music_volume, 0.0001))
	if music_volume <= 0.001:
		_music.stop()
	elif _current_track != "" and not _music.playing:
		_music.play()
