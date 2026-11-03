extends Node3D
## Look-dev for the Keeper: renders it in a neutral dark room, saves a PNG, quits.
## xvfb-run godot --path . res://tools/keeper_lookdev.tscn -- --out=/tmp/k.png --variant=full
var keepers: Array = []

func _ready() -> void:
	GameState.threat_enabled = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.025)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.27, 0.3)
	e.ambient_light_energy = float(Harness.get_arg("amb", "0.4"))
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.12, 0.12, 0.12)
	floor.material_override = fm
	add_child(floor)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(20, 0.2, 20)
	cs.shape = bs
	cs.position.y = -0.1
	sb.add_child(cs)
	add_child(sb)
	var n := int(Harness.get_arg("n", "1"))
	var variants := Harness.get_arg("variant", "full").split(",")
	for i in variants.size():
		var k: Keeper = load("res://scripts/threat/keeper.gd").new()
		k.think = false
		add_child(k)
		k.global_position = Vector3((i - (variants.size() - 1) * 0.5) * 1.4, 0, 0)
		k.rotation.y = float(Harness.get_arg("rot", "0.35"))
		_variant(k, variants[i])
		keepers.append(k)
	var cam := Camera3D.new()
	add_child(cam)
	var dist := float(Harness.get_arg("dist", "3.2"))
	cam.position = Vector3(0, float(Harness.get_arg("camy", "1.5")), dist)
	cam.look_at(Vector3(0, float(Harness.get_arg("looky", "1.3")), 0))
	cam.fov = float(Harness.get_arg("fov", "50"))
	cam.current = true
	var key := SpotLight3D.new()
	key.light_energy = float(Harness.get_arg("light", "5"))
	key.spot_range = 14.0
	key.spot_angle = 30.0
	key.light_color = Color(1.0, 0.93, 0.8)
	key.shadow_enabled = true
	add_child(key)
	key.position = cam.position + Vector3(0.6, 0.3, 0)
	key.look_at(Vector3(0, 1.3, 0))
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.5, 0.6, 0.8)
	rim.light_energy = float(Harness.get_arg("rim", "1.5"))
	rim.omni_range = 6
	rim.position = Vector3(-1.5, 2.2, -2.0)
	add_child(rim)
	var st := int(Harness.get_arg("state", "-1"))
	for f in 3:
		await get_tree().process_frame
	for k in keepers:
		if st >= 0:
			k.set_state(st)
		var cl := Harness.get_arg("clip", "")
		if cl != "":
			k.pose_clip(cl, float(Harness.get_arg("clip_t", "0")))
		if k.poser:
			for kv in Harness.get_arg("pose", "").split(",", false):
				var pr := kv.split("=")
				k.poser.set(pr[0], float(pr[1]))
	for f in int(Harness.get_arg("frames", "4")):
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(Harness.get_arg("out", "/tmp/keeper_lookdev.png"))
	get_tree().quit()


func _variant(k: Keeper, v: String) -> void:
	if v == "full":
		return
	var body := k.find_child("Body", true, false) as MeshInstance3D
	var m: StandardMaterial3D = (body.material_override as StandardMaterial3D).duplicate()
	if v.contains("nonormal"):
		m.normal_enabled = false
	if v.contains("nocc"):
		m.clearcoat_enabled = false
	if v.contains("nosss"):
		m.subsurf_scatter_enabled = false
	if v.contains("norim"):
		m.rim_enabled = false
	body.material_override = m
