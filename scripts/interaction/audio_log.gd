class_name AudioLog
extends Interactable
## A cassette recorder left behind. Interact to play the tape: the voice plays
## through the recorder (3D) and the transcript opens in the document reader.
## Played tapes set the flag "log_<id>" (Phase 4 can persist / list them).

@export var log_id := "tape_okafor"

var _led: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	solid = false
	prompt = "Play tape"
	super._ready()
	if get_node_or_null("Visual") == null:
		var v: Node3D = load("res://assets/props/portable_cassette_player/portable_cassette_player_1k.gltf").instantiate()
		v.name = "Visual"
		v.scale = Vector3.ONE * 1.5
		v.position.y = 0.09
		add_child(v)
	_led = StandardMaterial3D.new()
	_led.albedo_color = Color(0.2, 0.02, 0.01)
	_led.emission_enabled = true
	_led.emission = Color(1.0, 0.1, 0.05)
	var led := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.008
	sm.height = 0.016
	led.mesh = sm
	led.material_override = _led
	led.position = Vector3(0.09, 0.15, 0.03)
	add_child(led)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.3, 0.22, 0.12)
	cs.shape = bs
	cs.position.y = 0.1
	add_child(cs)


func _process(delta: float) -> void:
	_t += delta
	var played: bool = GameState.get_flag("log_" + log_id)
	var playing := Sfx.tape_playing == log_id
	var blink := 1.0 if fmod(_t, 1.4) < 0.15 else 0.0
	_led.emission_energy_multiplier = 3.0 if playing else (blink * 4.0 if not played else 0.0)


func get_prompt(_a: Node) -> String:
	var who: String = AudioLogs.LOGS.get(log_id, {}).get("speaker", "")
	if Sfx.tape_playing == log_id:
		return "Stop tape"
	return ("Replay tape  -  " if GameState.get_flag("log_" + log_id) else "Play tape  -  ") + who


func interact(actor: Node) -> void:
	if Sfx.tape_playing == log_id:
		Sfx.stop_tape()
		return
	GameState.set_flag("log_" + log_id)
	Legacy.record_tape(log_id)
	Sfx.play_tape(log_id, self)
	Events.show_note.emit(AudioLogs.title(log_id), AudioLogs.transcript(log_id))
	super.interact(actor)
