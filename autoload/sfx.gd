extends Node
## Sound: 2D one-shots (UI-ish feedback), positional one-shots in the world,
## footstep sets per surface, the cassette player with timed subtitles, and the
## station PA. Gains here keep the mix sane: voices and tapes on top, the Keeper
## clear, foley well under them.

const SOUNDS := {
	# id: [path, gain_db]
	"pickup": ["res://audio/sfx2/pickup.ogg", -6.0],
	"pickup_paper": ["res://audio/sfx2/pickup_paper.ogg", -6.0],
	"pickup_key": ["res://audio/sfx2/pickup_key.ogg", -6.0],
	"beep": ["res://audio/sfx/keypad_beep.wav", 0.0],
	"deny": ["res://audio/sfx/deny.wav", 0.0],
	"granted": ["res://audio/sfx/granted.wav", 0.0],
	"click": ["res://audio/sfx2/flash_on.ogg", -4.0],
	"flash_on": ["res://audio/sfx2/flash_on.ogg", -4.0],
	"flash_off": ["res://audio/sfx2/flash_off.ogg", -4.0],
	"battery_swap": ["res://audio/sfx2/battery_swap.ogg", -2.0],
	"medkit": ["res://audio/sfx2/medkit.ogg", -4.0],
	"inv_open": ["res://audio/sfx2/inv_open.ogg", -6.0],
	"inv_close": ["res://audio/sfx2/inv_close.ogg", -6.0],
	"tape_start": ["res://audio/sfx/tape_start.wav", 0.0],
	"tape_stop": ["res://audio/sfx/tape_stop.wav", 0.0],
	"keeper_strike": ["res://audio/keeper/keeper_lunge.ogg", -2.0],
	"keeper_grab": ["res://audio/keeper/keeper_grab.ogg", 0.0],
	"heartbeat": ["res://audio/sfx2/heartbeat.ogg", -2.0],
	"hurt_1": ["res://audio/sfx2/hurt_1.ogg", -4.0],
	"hurt_2": ["res://audio/sfx2/hurt_2.ogg", -4.0],
	"gasp": ["res://audio/sfx2/gasp.ogg", -6.0],
	"zap": ["res://audio/sfx/zap.wav", 0.0],
	"steam_burst": ["res://audio/sfx/steam_burst.wav", 0.0],
	"gas_ignite": ["res://audio/sfx/gas_ignite.wav", 0.0],
	"sting_spotted": ["res://audio/stingers/sting_spotted.ogg", -3.0],
	"sting_death": ["res://audio/stingers/sting_death.ogg", -2.0],
	"sting_discover": ["res://audio/stingers/sting_discover.ogg", -6.0],
	"sting_title": ["res://audio/stingers/sting_title.ogg", -4.0],
	"sting_ending": ["res://audio/stingers/sting_ending.ogg", -2.0],
	"lift_stop": ["res://audio/sfx2/lift_stop.ogg", -2.0],
	"lift_gate": ["res://audio/sfx2/lift_gate.ogg", -4.0],
	"vent_bang": ["res://audio/sfx2/vent_bang.ogg", 0.0],
	"keeper_hurt": ["res://audio/keeper/keeper_hurt.ogg", 0.0],
	"keeper_scream": ["res://audio/keeper/keeper_scream.ogg", -2.0],
	"keeper_breath": ["res://audio/keeper/keeper_breath.ogg", -2.0],
	"lever": ["res://audio/sfx2/lever.ogg", -2.0],
	"breaker": ["res://audio/sfx2/breaker.ogg", -2.0],
	"pa_chime": ["res://audio/sfx2/pa_chime.ogg", -4.0],
	"gen_start": ["res://audio/sfx2/gen_start.ogg", -2.0],
	"lift_loop": ["res://audio/sfx2/lift_loop.ogg", -6.0],
}

## Positional sounds (play_at): id -> [path(s), gain_db, unit_size]
const WORLD := {
	"door_heavy": [["res://audio/sfx2/door_heavy.ogg"], -4.0, 5.0],
	"door_locked": [["res://audio/sfx2/door_locked.ogg"], -4.0, 3.0],
	"locker_open": [["res://audio/sfx2/locker_open.ogg"], -4.0, 3.0],
	"locker_close": [["res://audio/sfx2/locker_close.ogg"], -4.0, 3.0],
	"lever": [["res://audio/sfx2/lever.ogg"], -2.0, 4.0],
	"breaker": [["res://audio/sfx2/breaker.ogg"], -2.0, 4.0],
	"fuse_insert": [["res://audio/sfx2/fuse_insert.ogg"], -4.0, 3.0],
	"gen_start": [["res://audio/sfx2/gen_start.ogg"], -2.0, 6.0],
	"keycard": [["res://audio/sfx2/keycard.ogg"], -6.0, 3.0],
	"vent_bang": [["res://audio/sfx2/vent_bang.ogg"], 2.0, 9.0],
	"keeper_step": [["res://audio/keeper/keeper_step_1.ogg", "res://audio/keeper/keeper_step_2.ogg"], -3.0, 4.0],
	"keeper_click": [["res://audio/keeper/keeper_click.ogg"], 0.0, 4.0],
	"keeper_sniff": [["res://audio/keeper/keeper_sniff.ogg"], -2.0, 4.0],
	"keeper_alert": [["res://audio/keeper/keeper_alert.ogg"], 2.0, 10.0],
	"keeper_scream": [["res://audio/keeper/keeper_scream.ogg"], 2.0, 12.0],
	"keeper_hurt": [["res://audio/keeper/keeper_hurt.ogg"], 2.0, 10.0],
	"keeper_lunge": [["res://audio/keeper/keeper_lunge.ogg"], 0.0, 6.0],
	"keeper_crawl": [["res://audio/keeper/keeper_crawl.ogg"], 0.0, 7.0],
	"keeper_drag": [["res://audio/keeper/keeper_drag.ogg"], -2.0, 5.0],
	"vent_creak": [["res://audio/sfx/vent_creak.wav"], -4.0, 6.0],
	"distant_thud": [["res://audio/ambience/bang0.wav", "res://audio/ambience/bang1.wav"], -2.0, 8.0],
	"distant_steps": [["res://audio/foley/step_metal_1.ogg", "res://audio/foley/step_metal_2.ogg", "res://audio/foley/step_metal_3.ogg"], -6.0, 5.0],
	"cloth": [["res://audio/foley/cloth_1.ogg", "res://audio/foley/cloth_2.ogg", "res://audio/foley/cloth_3.ogg"], -16.0, 2.0],
}

## Captions for sounds that matter for play (Settings > Accessibility > Sound captions).
const CAPTIONS := {
	"door_heavy": "heavy door grinding", "door_locked": "locked door rattles",
	"locker_rattle": "a locker rattles", "vent_creak": "metal creaking in the vents",
	"distant_thud": "a distant thud", "distant_steps": "footsteps, far off",
	"vent_bang": "metal banging in the vents", "keeper_alert": "a shriek - it has seen you",
	"keeper_scream": "something screams", "keeper_hurt": "it recoils from the light, screeching",
	"keeper_click": "wet clicking nearby", "keeper_sniff": "sniffing, close",
	"keeper_crawl": "something crawling through the ducts", "keeper_lunge": "a lunge",
	"keeper_step": "heavy steps", "gen_start": "the generator coughs to life",
	"breaker": "a breaker thunks", "steam_burst": "steam bursts", "steam_warn": "steam hissing, building",
	"zap": "electric arc", "gas_ignite": "gas ignites", "lift_stop": "the lift slams to a stop",
}

const FOOTSTEPS := {
	"concrete": ["res://audio/foley/step_concrete_1.ogg", "res://audio/foley/step_concrete_2.ogg", "res://audio/foley/step_concrete_3.ogg"],
	"metal": ["res://audio/foley/step_metal_1.ogg", "res://audio/foley/step_metal_2.ogg", "res://audio/foley/step_metal_3.ogg"],
	"tile": ["res://audio/foley/step_tile_1.ogg", "res://audio/foley/step_tile_2.ogg", "res://audio/foley/step_tile_3.ogg"],
	"water": ["res://audio/foley/step_water_1.ogg", "res://audio/foley/step_water_2.ogg", "res://audio/foley/step_water_3.ogg"],
}

const PA := {
	"pa_intro": "Expedition personnel. Descend one at a time. Recover the research drive. Leave the crate for the next member.",
	"pa_generator": "Auxiliary power restored. Level B2 lighting available on the corridor breaker.",
	"pa_lab": "Lab 3 circuit restored. Containment systems: offline.",
	"pa_lift": "Lift cage at the bottom. One person per trip.",
}

var _pool: Array[AudioStreamPlayer] = []
var tape_playing := ""
var _tape: AudioStreamPlayer3D
var _hiss: AudioStreamPlayer3D
var _streams := {}
var _cache := {}
var _subs := {}
var _tape_lines: Array = []
var _tape_next := 0
var _pa: AudioStreamPlayer
var _last_caption := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_pool.append(p)
	_pa = AudioStreamPlayer.new()
	_pa.bus = &"SFX"
	add_child(_pa)
	for k in SOUNDS:
		if ResourceLoader.exists(SOUNDS[k][0]):
			_streams[k] = load(SOUNDS[k][0])
	if FileAccess.file_exists("res://audio/logs/subtitles.json"):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://audio/logs/subtitles.json"))
		if j is Dictionary:
			_subs = j
	Events.toast.connect(func(t: String): if t.begins_with("+ "): play("pickup"))
	Events.interaction_feedback.connect(func(_t): play("deny", -8.0))


func stream(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(sound):
		return
	for p in _pool:
		if not p.playing:
			p.stream = _streams[sound]
			p.volume_db = volume_db + float(SOUNDS[sound][1])
			p.pitch_scale = pitch
			p.play()
			return


## A positional one-shot at a point (or following a node). Captions it if it matters.
func play_at(id: String, at: Variant, volume_db := 0.0, pitch := 1.0, caption := true) -> AudioStreamPlayer3D:
	if not WORLD.has(id):
		return null
	var w: Array = WORLD[id]
	var paths: Array = w[0]
	var s := stream(paths[randi() % paths.size()])
	if s == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.bus = &"SFX"
	p.stream = s
	p.volume_db = volume_db + float(w[1])
	p.unit_size = float(w[2])
	p.max_distance = float(w[2]) * 8.0
	p.pitch_scale = pitch
	var parent: Node = at if at is Node3D else get_tree().current_scene
	if parent == null:
		return null
	parent.add_child(p)
	if at is Vector3:
		p.global_position = at
	p.play()
	p.finished.connect(p.queue_free)
	if caption:
		caption_for(id, p.global_position)
	return p


## Show a [caption] for an important sound the player can hear.
func caption_for(id: String, where: Vector3 = Vector3.INF, dur := 2.5) -> void:
	if not CAPTIONS.has(id):
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if where != Vector3.INF and cam and cam.global_position.distance_to(where) > 26.0:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_caption.get(id, -10000)) < 2500:
		return
	_last_caption[id] = now
	var dir := ""
	if where != Vector3.INF and cam:
		var local := cam.global_transform.affine_inverse() * where
		if local.z > 1.0:
			dir = " (behind)"
		elif local.x < -2.0:
			dir = " (left)"
		elif local.x > 2.0:
			dir = " (right)"
	Ux.subtitle(str(CAPTIONS[id]) + dir, "", dur, "sound")


func footstep_stream(surface: String) -> AudioStream:
	var list: Array = FOOTSTEPS.get(surface, FOOTSTEPS["concrete"])
	return stream(list[randi() % list.size()])


## Station public address: chime + voice, subtitled.
func play_pa(id: String) -> void:
	var path := "res://audio/pa/%s.ogg" % id
	var s := stream(path)
	if s:
		_pa.stream = s
		_pa.volume_db = -3.0
		_pa.play()
	if PA.has(id):
		var dur := s.get_length() if s else 5.0
		get_tree().create_timer(1.2, true, false, true).timeout.connect(func(): Ux.subtitle(PA[id], "", dur - 1.0, "pa"))


func stop_pa() -> void:
	if _pa:
		_pa.stop()


func pa_playing() -> bool:
	return _pa.playing


## Cassette playback: one tape at a time, voiced through the recorder in the world
## with tape hiss underneath. Emits Events.tape_started / tape_finished for the HUD
## and drives the timed subtitles.
func play_tape(id: String, at: Node3D) -> void:
	stop_tape(false)
	var path := AudioLogs.stream_path(id)
	if not ResourceLoader.exists(path):
		return
	_tape = AudioStreamPlayer3D.new()
	_tape.bus = &"SFX"
	_tape.stream = load(path)
	_tape.unit_size = 6.0
	_tape.max_db = 3.0
	_tape.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
	at.add_child(_tape)
	_hiss = AudioStreamPlayer3D.new()
	_hiss.bus = &"SFX"
	_hiss.stream = AudioLoop.make(load("res://audio/ambience/tape_hiss.wav"))
	_hiss.volume_db = -22.0
	_hiss.unit_size = 4.0
	at.add_child(_hiss)
	tape_playing = id
	play("tape_start", -6.0)
	_hiss.play()
	_tape.play(0.0)
	_tape.finished.connect(_on_tape_done.bind(_tape))
	_tape_lines = _subs.get(id, {}).get("lines", [])
	_tape_next = 0
	Events.tape_started.emit(AudioLogs.title(id), _tape.stream.get_length())


func tape_speaker(id: String) -> String:
	return str(_subs.get(id, {}).get("speaker", ""))


func tape_lines(id: String) -> Array:
	return _subs.get(id, {}).get("lines", [])


func _process(_delta: float) -> void:
	if tape_playing == "" or not is_instance_valid(_tape) or not _tape.playing:
		return
	var t := _tape.get_playback_position()
	while _tape_next < _tape_lines.size() and float(_tape_lines[_tape_next][0]) <= t:
		var l: Array = _tape_lines[_tape_next]
		Ux.subtitle(str(l[2]), tape_speaker(tape_playing), maxf(1.2, float(l[1]) - float(l[0]) + 0.2), "speech")
		_tape_next += 1


func _on_tape_done(p: AudioStreamPlayer3D) -> void:
	if p == _tape:
		stop_tape()


func stop_tape(click := true) -> void:
	if tape_playing == "":
		return
	tape_playing = ""
	_tape_lines = []
	for n in [_tape, _hiss]:
		if is_instance_valid(n):
			n.queue_free()
	_tape = null
	_hiss = null
	if click:
		play("tape_stop", -6.0)
	Events.tape_finished.emit()
