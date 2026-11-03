class_name ChargingDock
extends Interactable
## Wall charger. Hold Interact to recharge the flashlight to full (needs power).

func _ready() -> void:
	if hold_time <= 0.0:
		hold_time = 3.0
	if required_circuit == "":
		required_circuit = "aux"
	super._ready()
	var m := ArtMats.local("metal")
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.4, 0.12)
	box.mesh = bm
	box.material_override = m
	add_child(box)
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.emission_enabled = true
	var lamp := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.2, 0.04, 0.01)
	lamp.mesh = lm
	lamp.material_override = lamp_mat
	lamp.position = Vector3(0, 0.12, 0.062)
	add_child(lamp)
	var l := Label3D.new()
	l.double_sided = false
	l.text = "CHARGE"
	l.font_size = 24
	l.pixel_size = 0.003
	l.position = Vector3(0, -0.05, 0.065)
	add_child(l)
	var cs := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = Vector3(0.34, 0.44, 0.3)
	cs.shape = shp
	cs.position.z = 0.06
	add_child(cs)
	var upd := func(_i = null, _p = null):
		var c := Color(0.2, 0.9, 1.0) if is_powered() else Color(0.02, 0.02, 0.02)
		lamp_mat.emission = c
		lamp_mat.albedo_color = c * 0.2
		lamp_mat.emission_energy_multiplier = 2.0
	GameState.grid.circuit_changed.connect(upd)
	upd.call()


func get_prompt(_a: Node) -> String:
	return "Hold to charge flashlight"


func can_interact(a: Node) -> bool:
	if not super.can_interact(a):
		return false
	var fl: Variant = a.get("flashlight") if a else null
	return fl == null or fl.battery.charge < 0.999


func get_refusal(a: Node) -> String:
	if not is_powered():
		return "Charger has no power"
	return "Battery already full"


func interact(a: Node) -> void:
	var fl: Variant = a.get("flashlight") if a else null
	if fl:
		fl.battery.replace()
		fl.sync_to_state()
	Events.toast.emit("Flashlight charged")
	super.interact(a)
