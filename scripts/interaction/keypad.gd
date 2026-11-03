class_name Keypad
extends Interactable
## Puzzle 2: 4-digit code panel next to a door. The code is per-expedition
## (GameState.lab_code) and written on the security memo.

signal code_accepted
signal code_rejected(attempts: int)

@export var door_path: NodePath
@export var max_attempts := 3
@export var lockout_seconds := 8.0

var door: Door
var attempts := 0
var solved := false
var _lockout_until := 0.0
var _screen_mat: StandardMaterial3D


func _ready() -> void:
	super._ready()
	door = get_node_or_null(door_path) as Door
	_build()
	GameState.grid.circuit_changed.connect(func(_i, _p): _refresh())
	_refresh()


func _build() -> void:
	var m := ArtMats.local("metal", Color(0.55, 0.55, 0.55))
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.32, 0.06)
	box.mesh = bm
	box.material_override = m
	add_child(box)
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.emission_enabled = true
	var scr := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.16, 0.06, 0.01)
	scr.mesh = sm
	scr.material_override = _screen_mat
	scr.position = Vector3(0, 0.1, 0.032)
	add_child(scr)
	var keys := MeshInstance3D.new()
	var km := BoxMesh.new()
	km.size = Vector3(0.15, 0.16, 0.012)
	keys.mesh = km
	var kmat := StandardMaterial3D.new()
	kmat.albedo_color = Color(0.45, 0.47, 0.48)
	keys.material_override = kmat
	keys.position = Vector3(0, -0.04, 0.033)
	add_child(keys)
	var cs := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = Vector3(0.3, 0.4, 0.2)
	cs.shape = shp
	cs.position.z = 0.05
	add_child(cs)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func is_locked_out() -> bool:
	return _now() < _lockout_until


func get_prompt(_a: Node) -> String:
	return "Enter code"


func can_interact(a: Node) -> bool:
	return super.can_interact(a) and not solved and not is_locked_out()


func get_refusal(a: Node) -> String:
	if solved:
		return "Access granted"
	if is_locked_out():
		return "Keypad locked out (%ds)" % ceili(_lockout_until - _now())
	return super.get_refusal(a)


func interact(a: Node) -> void:
	if can_interact(a):
		Events.open_keypad.emit(self)
		super.interact(a)


## Called by the keypad UI (or tests). Returns true when the code is right.
func submit(code: String) -> bool:
	if solved or is_locked_out() or not is_powered():
		return false
	if code == GameState.lab_code:
		solved = true
		attempts = 0
		if door:
			door.unlock_code()
			door.open()
		code_accepted.emit()
		Events.toast.emit("Access granted")
		_refresh()
		store()
		return true
	attempts += 1
	code_rejected.emit(attempts)
	if attempts >= max_attempts:
		attempts = 0
		_lockout_until = _now() + lockout_seconds
		Events.toast.emit("Too many attempts. Keypad locked")
	_refresh()
	return false


func _refresh() -> void:
	var c := Color(0.02, 0.02, 0.02)
	if is_powered():
		c = Color(0.1, 1.0, 0.35) if solved else Color(1.0, 0.45, 0.1)
	_screen_mat.albedo_color = c * 0.2
	_screen_mat.emission = c
	_screen_mat.emission_energy_multiplier = 2.0 if is_powered() else 0.0


func save_state() -> Dictionary:
	return {"solved": solved}


func load_state(st: Dictionary) -> void:
	solved = st.get("solved", false)
