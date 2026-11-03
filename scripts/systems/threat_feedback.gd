class_name ThreatFeedback
extends Node
## v1.2: the suit's heart monitor made audible and felt. As the Keeper gets closer (and
## when it is hunting you) a heartbeat speeds up and gets louder, and every beat can
## pulse the phone's vibration motor (or the controller's rumble). It is an honest cue:
## it follows the Keeper's REAL distance and state and nothing else (the fake-out
## director never touches it).
##
## Battery-sane by design: a pulse is one short buzz per beat (25-70 ms), never closer
## than MIN_PULSE_GAP apart, nothing while paused, in the background, hidden in the
## menus, dead, or when the Keeper is far / dormant.

const FAR := 16.0          ## metres: nothing beyond this (unless it is chasing you)
const NEAR := 2.0          ## metres: full intensity
const BPM_CALM := 62.0
const BPM_PANIC := 150.0
const MIN_LEVEL := 0.08    ## below this: silent, no buzz
const BUZZ_LEVEL := 0.3    ## vibration starts here
const MIN_PULSE_GAP := 0.38  ## seconds between two vibration pulses, at most ~2.6 per second
const VOL_QUIET := -24.0
const VOL_LOUD := -3.0

var game: Node
var level := 0.0            ## smoothed 0..1
var target := 0.0
var beats := 0              ## beats played (tests)
var pulses := 0             ## vibration pulses sent (tests)
var last_pulse_ms := 0      ## duration of the last pulse (tests)
var _beat_t := 0.0
var _since_pulse := 99.0
var _player: AudioStreamPlayer
var vibrate_fn: Callable    ## tests swap the hardware call for a counter


func _ready() -> void:
	name = "ThreatFeedback"
	_player = AudioStreamPlayer.new()
	_player.bus = &"SFX"
	_player.stream = load("res://audio/sfx/heartbeat_v12.wav") if ResourceLoader.exists("res://audio/sfx/heartbeat_v12.wav") else null
	add_child(_player)


## Pure rule (tested): how afraid the heart is, 0..1, from the Keeper's real distance and state.
static func level_for(dist: float, state: int) -> float:
	if state == Keeper.S.DORMANT:
		return 0.0
	var hunting := state in [Keeper.S.CHASE, Keeper.S.LUNGE, Keeper.S.GRAB, Keeper.S.WAIT_LIGHT]
	var k := clampf((FAR - dist) / (FAR - NEAR), 0.0, 1.0)
	k = pow(k, 1.3)
	match state:
		Keeper.S.PATROL:
			k *= 0.75
		Keeper.S.INVESTIGATE, Keeper.S.SEARCH:
			k = k * 0.9 + (0.1 if k > 0.0 else 0.0)
		Keeper.S.REPELLED, Keeper.S.RETREAT:
			k *= 0.6
	if hunting and dist < 24.0:
		k = maxf(k, 0.7)
	return clampf(k, 0.0, 1.0)


static func bpm_for(lvl: float) -> float:
	return lerpf(BPM_CALM, BPM_PANIC, clampf(lvl, 0.0, 1.0))


static func volume_for(lvl: float) -> float:
	return lerpf(VOL_QUIET, VOL_LOUD, clampf(lvl, 0.0, 1.0))


## Pulse length (ms) and strength (0..1) for a beat at this level.
static func pulse_for(lvl: float) -> Vector2:
	return Vector2(roundf(lerpf(25.0, 70.0, clampf(lvl, 0.0, 1.0))), lerpf(0.25, 0.85, clampf(lvl, 0.0, 1.0)))


func _active() -> bool:
	if game == null or Ux.in_background or get_tree().paused:
		return false
	if game.get("ended"):
		return false
	var p: Player = game.get("player")
	return p != null and not p.dead


func _process(delta: float) -> void:
	var k: Keeper = game.get("keeper") if game else null
	target = 0.0
	if _active() and k != null and is_instance_valid(k):
		var p: Player = game.get("player")
		target = level_for(k.global_position.distance_to(p.global_position), k.state)
	# the heart speeds up quickly and calms down slowly
	level = move_toward(level, target, delta * (1.2 if target > level else 0.25))
	_since_pulse += delta
	if level < MIN_LEVEL or not _active():
		_beat_t = 0.0
		return
	_beat_t -= delta
	if _beat_t <= 0.0:
		_beat_t = 60.0 / bpm_for(level)
		_beat()


func _beat() -> void:
	beats += 1
	if bool(Settings.get_value("audio", "heartbeat")) and _player.stream:
		_player.volume_db = volume_for(level)
		_player.pitch_scale = lerpf(0.96, 1.08, level)
		_player.play()
	if level >= BUZZ_LEVEL and _since_pulse >= MIN_PULSE_GAP and bool(Settings.get_value("controls", "vibration")):
		_since_pulse = 0.0
		var pv := pulse_for(level)
		pulses += 1
		last_pulse_ms = int(pv.x)
		if vibrate_fn.is_valid():
			vibrate_fn.call(int(pv.x), pv.y)
		else:
			ThreatFeedback.vibrate(int(pv.x), pv.y)


## One short buzz: the phone's motor on Android/iOS, the rumble motors of any pad.
static func vibrate(ms: int, strength: float) -> void:
	if Quality.is_phone_platform():
		Input.vibrate_handheld(ms, clampf(strength, 0.05, 1.0))
	for d in Input.get_connected_joypads():
		Input.start_joy_vibration(d, clampf(strength * 0.8, 0.0, 1.0), clampf(strength * 0.4, 0.0, 1.0), ms / 1000.0 + 0.04)
