@tool
class_name Door
extends Node3D
## Sliding facility door. Locks can stack: power circuit, keycard item, keypad code.
## The panel is an AnimatableBody3D (InteractProxy) so it blocks the player and
## is the thing you aim at.

signal opened
signal closed
signal unlocked

enum State { CLOSED, OPENING, OPEN, CLOSING }

@export var door_label := "DOOR"
@export var width := 1.6
@export var height := 2.4
@export var required_circuit := ""     ## needs power to move
@export var key_item := ""             ## e.g. "keycard_blue"
@export var needs_code := false        ## locked until a Keypad unlocks it
@export var start_open := false
@export var open_time := 0.9
@export var persist_id := ""

var state := State.CLOSED
var welded := false          ## sealed for good (the archive vault decision)
var code_unlocked := false
var key_used := false
var _panel: InteractProxy
var _status_mat: StandardMaterial3D
var _tween: Tween
var _sound: AudioStreamPlayer3D


func _ready() -> void:
	_build()
	if Engine.is_editor_hint():
		return
	add_to_group("doors")
	if persist_id != "":
		add_to_group("persistent")
		var st := GameState.get_world(persist_id)
		if not st.is_empty():
			code_unlocked = st.get("code_unlocked", false)
			key_used = st.get("key_used", false)
			start_open = st.get("open", start_open)
			welded = st.get("welded", false)
	if start_open and not welded:
		state = State.OPEN
		_panel.position.x = width
	if welded:
		_add_weld_visual()
	GameState.grid.circuit_changed.connect(func(_id, _p): _update_status())
	_update_status()


func _build() -> void:
	for c in get_children():
		if c.name.begins_with("_gen"):
			c.free()
	var frame_mat := ArtMats.local("rusty", Color(0.7, 0.7, 0.7))
	var panel_mat := ArtMats.local("green_metal")
	var stripe_mat := StandardMaterial3D.new()
	stripe_mat.albedo_color = Color(0.85, 0.6, 0.12)
	stripe_mat.roughness = 0.6

	# Frame (visual only; the wall around it is level geometry).
	var t := 0.12
	_mesh(self, "_genFrameL", Vector3(t, height + t, 0.34), Vector3(-width / 2 - t / 2, (height + t) / 2, 0), frame_mat)
	_mesh(self, "_genFrameR", Vector3(t, height + t, 0.34), Vector3(width / 2 + t / 2, (height + t) / 2, 0), frame_mat)
	_mesh(self, "_genFrameT", Vector3(width + 2 * t, t, 0.34), Vector3(0, height + t / 2, 0), frame_mat)

	_panel = InteractProxy.new()
	_panel.name = "_genPanel"
	_panel.target = self
	_panel.collision_layer = 1 | 4
	_panel.collision_mask = 0
	_panel.sync_to_physics = true
	add_child(_panel)
	_mesh(_panel, "Mesh", Vector3(width, height, 0.12), Vector3(0, height / 2, 0), panel_mat)
	_mesh(_panel, "Stripe", Vector3(width * 0.98, 0.14, 0.13), Vector3(0, 1.0, 0), stripe_mat)
	var w := _mesh(_panel, "Window", Vector3(width * 0.4, 0.35, 0.125), Vector3(0, 1.75, 0), null)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.07, 0.08)
	glass.metallic = 0.2
	glass.roughness = 0.08
	w.material_override = glass
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, height, 0.14)
	cs.shape = bs
	cs.position = Vector3(0, height / 2, 0)
	_panel.add_child(cs)

	# Status lamp above the door, on both faces.
	_status_mat = StandardMaterial3D.new()
	_status_mat.emission_enabled = true
	_status_mat.albedo_color = Color.BLACK
	_mesh(self, "_genStatus", Vector3(0.22, 0.07, 0.38), Vector3(0, height + 0.2, 0), _status_mat)

	# Label plate (both sides).
	for side in [1, -1]:
		var l := Label3D.new()
		l.double_sided = false
		l.name = "_genLabel%d" % side
		l.text = door_label
		l.font_size = 40
		l.pixel_size = 0.004
		l.modulate = Color(0.85, 0.85, 0.8)
		l.outline_size = 0
		l.double_sided = false
		l.position = Vector3(0, height + 0.42, 0.18 * side)
		l.rotation.y = 0.0 if side == 1 else PI
		add_child(l)

	if not Engine.is_editor_hint():
		_sound = AudioStreamPlayer3D.new()
		_sound.name = "_genSound"
		_sound.bus = &"SFX"
		_sound.position.y = height * 0.6
		var s := load("res://audio/sfx2/door_heavy.ogg")
		if s:
			_sound.stream = s
		add_child(_sound)


func _mesh(parent: Node3D, n: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	if mat:
		mi.material_override = mat
	parent.add_child(mi)
	return mi


# --- Lock logic ----------------------------------------------------------------
func is_powered() -> bool:
	return required_circuit == "" or GameState.grid.is_powered(required_circuit)


func is_locked_for(actor: Node) -> bool:
	return lock_reason(actor) != ""


func lock_reason(_actor: Node) -> String:
	if welded:
		return "Welded shut"
	if not is_powered():
		return "No power"
	if needs_code and not code_unlocked:
		return "Locked. Use the keypad"
	if key_item != "" and not key_used and not GameState.inventory.has(key_item):
		return "Locked. Needs %s" % ItemDB.display_name(key_item)
	return ""


## The Keeper can push an unlocked door open, but not a locked or unpowered one.
func keeper_can_open() -> bool:
	if welded:
		return false
	if not is_powered():
		return false
	if needs_code and not code_unlocked:
		return false
	if key_item != "" and not key_used:
		return false
	return true


func unlock_code() -> void:
	code_unlocked = true
	_update_status()
	unlocked.emit()
	_store()


func get_prompt(_a: Node) -> String:
	match state:
		State.OPEN, State.OPENING:
			return "Close " + door_label.capitalize()
	if key_item != "" and not key_used and GameState.inventory.has(key_item):
		return "Use %s" % ItemDB.display_name(key_item)
	return "Open " + door_label.capitalize()


func can_interact(a: Node) -> bool:
	return lock_reason(a) == ""


func get_refusal(a: Node) -> String:
	return lock_reason(a)


func get_hold_time(_a: Node) -> float:
	return 0.0


func interact(a: Node) -> void:
	if not can_interact(a):
		return
	if key_item != "" and not key_used:
		key_used = true  # card stays in the inventory; reader remembers it
	toggle()


func toggle() -> void:
	if state in [State.OPEN, State.OPENING]:
		close()
	else:
		open()


func open() -> void:
	if state in [State.OPEN, State.OPENING]:
		return
	_move(State.OPENING, State.OPEN, width)
	opened.emit()


func close() -> void:
	if state in [State.CLOSED, State.CLOSING]:
		return
	_move(State.CLOSING, State.CLOSED, 0.0)
	closed.emit()


func is_open() -> bool:
	return state == State.OPEN


func _move(during: State, after: State, x: float) -> void:
	state = during
	if _tween:
		_tween.kill()
	if _sound and _sound.stream:
		_sound.play()
		Sfx.caption_for("door_heavy", global_position)
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(_panel, "position:x", x, open_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(func():
		state = after
		_update_status()
		_store())
	_update_status()


## Instantly snap (used by tests and persistence).
func set_open_immediate(o: bool) -> void:
	if _tween:
		_tween.kill()
	state = State.OPEN if o else State.CLOSED
	_panel.position.x = width if o else 0.0
	_update_status()


func _update_status() -> void:
	if _status_mat == null:
		return
	var c := Color(0.02, 0.02, 0.02)
	var e := 0.0
	if is_powered():
		if lock_reason(null) == "" or code_unlocked or key_used:
			c = Color(0.1, 1.0, 0.35)
		else:
			c = Color(1.0, 0.12, 0.08)
		e = 3.0
		if needs_code and not code_unlocked:
			c = Color(1.0, 0.12, 0.08)
	_status_mat.albedo_color = c * 0.3
	_status_mat.emission = c
	_status_mat.emission_energy_multiplier = e


func weld() -> void:
	set_open_immediate(false)
	welded = true
	_update_status()
	_store()
	_add_weld_visual()


func _add_weld_visual() -> void:
	if get_node_or_null("_genWeld"):
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.18, 0.15, 0.12)
	m.metallic = 0.8
	m.roughness = 0.45
	m.emission_enabled = true
	m.emission = Color(1.0, 0.35, 0.08)
	m.emission_energy_multiplier = 0.25
	var holder := Node3D.new()
	holder.name = "_genWeld"
	add_child(holder)
	for x in [-width / 2.0, width / 2.0]:
		_mesh(holder, "Seam", Vector3(0.06, height, 0.2), Vector3(x, height / 2.0, 0), m)
	for k in 3:
		_mesh(holder, "Bar%d" % k, Vector3(width + 0.3, 0.12, 0.2), Vector3(0, 0.5 + k * 0.8, 0.0), m)


func _store() -> void:
	if persist_id != "" and not Engine.is_editor_hint():
		GameState.set_world(persist_id, {"open": state in [State.OPEN, State.OPENING], "code_unlocked": code_unlocked, "key_used": key_used, "welded": welded})
