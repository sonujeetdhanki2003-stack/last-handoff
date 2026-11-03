class_name AmbientDirector
extends Node3D
## Room tone + music layers for the facility, all generated in code (numpy) and
## routed to the existing buses:
##  * one room-tone loop per area on "Ambience", crossfaded by the player's distance
##    to each room box (so doorways blend naturally);
##  * a low drone on "Music" all the time, and a tension layer that swells in Lab 3,
##    in the dark (flashlight off), on a low battery, and in rare random surges;
##  * random one-shots around the player: drips, distant metal groans, far bangs.

const ROOMS := {
	# name: [x0, x1, z0, z1, loop, volume_db]
	"shaft": [-4.0, 4.0, 0.0, 8.0, "res://audio/ambience/room_shaft.wav", -9.0],
	"corridor": [-1.6, 1.6, -22.0, 0.0, "res://audio/ambience/room_corridor.wav", -12.0],
	"generator": [-10.0, -1.6, -9.0, -1.0, "res://audio/ambience/room_generator.wav", -10.0],
	"security": [1.6, 8.0, -11.0, -3.0, "res://audio/ambience/room_security.wav", -13.0],
	"storage": [-8.0, -1.6, -19.0, -12.0, "res://audio/ambience/room_storage.wav", -12.0],
	"lab": [-6.0, 6.0, -34.0, -22.0, "res://audio/ambience/room_lab.wav", -9.0],
	"archive": [1.6, 9.0, -21.5, -12.0, "res://audio/ambience/room_security.wav", -14.0],
	"crawlspace": [-25.0, -10.0, -9.0, -2.0, "res://audio/ambience/room_storage.wav", -11.0],
}
const ONESHOTS := {
	"drip": ["res://audio/ambience/drip0.wav", "res://audio/ambience/drip1.wav", "res://audio/ambience/drip2.wav"],
	"groan": ["res://audio/ambience/groan0.wav", "res://audio/ambience/groan1.wav", "res://audio/ambience/groan2.wav"],
	"bang": ["res://audio/ambience/bang0.wav", "res://audio/ambience/bang1.wav"],
}

var _room_players := {}
var _drone: AudioStreamPlayer
var _tension: AudioStreamPlayer
var _streams := {}
var _rng := RandomNumberGenerator.new()
var _next_shot := 4.0
var _surge := 0.0
var tension := 0.0          ## 0..1, readable by tests / later phases
var current_room := ""


func _ready() -> void:
	_rng.randomize()
	for r in ROOMS:
		var p := AudioStreamPlayer.new()
		p.bus = &"Ambience"
		p.stream = AudioLoop.make(load(ROOMS[r][4]))
		p.volume_db = -60.0
		add_child(p)
		p.play(_rng.randf() * 10.0)
		_room_players[r] = p
	_drone = AudioStreamPlayer.new()
	_drone.bus = &"Music"
	_drone.stream = AudioLoop.make(load("res://audio/music/drone.wav"))
	_drone.volume_db = -60.0
	add_child(_drone)
	_drone.play()
	_tension = AudioStreamPlayer.new()
	_tension.bus = &"Music"
	_tension.stream = AudioLoop.make(load("res://audio/music/tension.wav"))
	_tension.volume_db = -60.0
	add_child(_tension)
	_tension.play()
	for k in ONESHOTS:
		var arr := []
		for path in ONESHOTS[k]:
			arr.append(load(path))
		_streams[k] = arr


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


static func room_distance(pos: Vector3, r: Array) -> float:
	var dx := maxf(maxf(r[0] - pos.x, pos.x - r[1]), 0.0)
	var dz := maxf(maxf(r[2] - pos.z, pos.z - r[3]), 0.0)
	return sqrt(dx * dx + dz * dz)


func room_at(pos: Vector3) -> String:
	var best := ""
	var bd := INF
	for r in ROOMS:
		var d := room_distance(pos, ROOMS[r])
		if d < bd:
			bd = d
			best = r
	return best


func _process(delta: float) -> void:
	var pl := _player()
	if pl == null:
		return
	var pos := pl.global_position
	current_room = room_at(pos)
	for r in ROOMS:
		var d := room_distance(pos, ROOMS[r])
		var target: float = ROOMS[r][5] - d * 7.0
		if d > 6.0:
			target = -60.0
		var p: AudioStreamPlayer = _room_players[r]
		p.volume_db = move_toward(p.volume_db, target, delta * 18.0)
	# tension
	var t := 0.0
	if current_room == "lab":
		t += 0.55
	var fl = pl.get("flashlight")
	if fl and not fl.on:
		t += 0.35
	if GameState.battery_charge < 0.2:
		t += 0.3
	_surge = move_toward(_surge, 0.0, delta * 0.04)
	if _rng.randf() < delta * 0.006:
		_surge = _rng.randf_range(0.3, 0.6)
	tension = clampf(t + _surge, 0.0, 1.0)
	_drone.volume_db = move_toward(_drone.volume_db, -11.0 + tension * 3.0, delta * 10.0)
	var tt := lerpf(-40.0, -9.0, tension) if tension > 0.02 else -60.0
	_tension.volume_db = move_toward(_tension.volume_db, tt, delta * 6.0)
	# one-shots
	_next_shot -= delta
	if _next_shot <= 0.0:
		_next_shot = _rng.randf_range(5.0, 14.0)
		_one_shot(pos)


func _one_shot(around: Vector3) -> void:
	var roll := _rng.randf()
	var kind := "drip" if roll < 0.55 else ("groan" if roll < 0.88 else "bang")
	var arr: Array = _streams[kind]
	var a := AudioStreamPlayer3D.new()
	a.bus = &"Ambience"
	a.stream = arr[_rng.randi() % arr.size()]
	a.unit_size = 3.0 if kind == "drip" else 9.0
	a.max_db = 0.0
	a.volume_db = -4.0 if kind == "drip" else -10.0
	a.pitch_scale = _rng.randf_range(0.85, 1.1)
	var ang := _rng.randf() * TAU
	var dist := _rng.randf_range(2.5, 5.0) if kind == "drip" else _rng.randf_range(8.0, 16.0)
	add_child(a)
	a.global_position = around + Vector3(cos(ang) * dist, _rng.randf_range(0.5, 2.5), sin(ang) * dist)
	a.play()
	a.finished.connect(a.queue_free)
