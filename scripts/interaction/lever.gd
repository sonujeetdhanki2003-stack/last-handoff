class_name Lever
extends Interactable
## Wall lever / breaker. Flips a power circuit on or off.
## `requires_flag`: refuses until GameState has that flag (e.g. fuse panel repaired).

signal flipped(on: bool)

@export var circuit_id := "corridor_lights"
@export var label_text := "BREAKER"
@export var requires_flag := ""
@export var requires_flag_text := "Nothing happens"
@export var one_way := false   ## cannot be switched back off

var _handle: Node3D
var _lamp_mat: StandardMaterial3D


func _ready() -> void:
	super._ready()
	_build()
	GameState.grid.circuit_changed.connect(func(_i, _p): _refresh())
	_refresh()


func _build() -> void:
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.36, 0.5, 0.12)
	box.mesh = bm
	var m := ArtMats.local("green_metal")
	box.material_override = m
	add_child(box)
	var cs := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = Vector3(0.4, 0.55, 0.3)
	cs.shape = shp
	cs.position.z = 0.08
	add_child(cs)
	_handle = Node3D.new()
	_handle.position = Vector3(0, 0, 0.08)
	add_child(_handle)
	var h := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.05, 0.26, 0.05)
	h.mesh = hm
	h.position.y = 0.13
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.7, 0.08, 0.05)
	h.material_override = red
	_handle.add_child(h)
	var lamp := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.025
	lm.height = 0.05
	lamp.mesh = lm
	lamp.position = Vector3(0.12, 0.19, 0.07)
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.emission_enabled = true
	lamp.material_override = _lamp_mat
	add_child(lamp)
	var l := Label3D.new()
	l.double_sided = false
	l.text = label_text
	l.font_size = 28
	l.pixel_size = 0.003
	l.position = Vector3(0, 0.32, 0.07)
	l.modulate = Color(0.9, 0.85, 0.7)
	add_child(l)


func get_prompt(_a: Node) -> String:
	var on := GameState.grid.is_on(circuit_id)
	return ("Switch off " if on else "Switch on ") + label_text.capitalize()


func can_interact(a: Node) -> bool:
	if requires_flag != "" and not GameState.get_flag(requires_flag):
		return false
	if one_way and GameState.grid.is_on(circuit_id):
		return false
	return super.can_interact(a)


func get_refusal(a: Node) -> String:
	if requires_flag != "" and not GameState.get_flag(requires_flag):
		return requires_flag_text
	if one_way and GameState.grid.is_on(circuit_id):
		return "Already on"
	return super.get_refusal(a)


func interact(a: Node) -> void:
	var on := GameState.grid.toggle(circuit_id)
	Sfx.play_at("breaker" if on else "lever", global_position)
	flipped.emit(on)
	Events.toast.emit("%s %s" % [label_text.capitalize(), "ON" if on else "OFF"])
	super.interact(a)
	store()


func _refresh() -> void:
	var on := GameState.grid.is_on(circuit_id)
	var t := create_tween()
	t.tween_property(_handle, "rotation:x", -0.9 if on else 0.9, 0.25).set_trans(Tween.TRANS_BACK)
	var powered := GameState.grid.is_powered(circuit_id)
	var c := Color(0.1, 1.0, 0.3) if powered else (Color(1.0, 0.6, 0.1) if on else Color(0.6, 0.05, 0.05))
	_lamp_mat.albedo_color = c * 0.3
	_lamp_mat.emission = c
	_lamp_mat.emission_energy_multiplier = 2.5


func save_state() -> Dictionary:
	return {"on": GameState.grid.is_on(circuit_id)}


func load_state(st: Dictionary) -> void:
	GameState.grid.set_on(circuit_id, st.get("on", false))
