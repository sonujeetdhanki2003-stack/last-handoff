extends RefCounted
## Phase 3 set dressing for Level B2: real CC0 props (Poly Haven), decals, story
## marks, audio logs, readable documents, animated details (fans, sway, sparks,
## steam, CRTs), extra lighting and the ambient director. Called by build_scenes.gd
## after the greybox geometry, so every node name / interactable from Phase 2 stays.

const PROP := "res://assets/props/%s/%s_1k.gltf"
const DEC := "res://assets/decals/%s.png"
const LAYER_PROPS := 8   # physics layer 4: blocks the player, not the camera or aim ray
const NO_PLAYER := 0xFFFFF & ~2

var b: Node   # the scene builder (box/cyl/light/label/inst/mats)
var level: Node3D
var root: Node3D
var _piece_cache := {}
var _aabb_cache := {}


func _init(builder: Node) -> void:
	b = builder


func run(lvl: Node3D) -> void:
	level = lvl
	root = Node3D.new()
	root.name = "Dressing"
	level.add_child(root)
	_shaft()
	_corridor()
	_generator()
	_security()
	_storage()
	_lab()
	_lift()
	_archive()
	_camp()
	_phase4_extras()
	var amb := Node3D.new()
	amb.name = "AmbientDirector"
	amb.set_script(load("res://scripts/world/ambient_director.gd"))
	level.add_child(amb)


# ============================================================================ helpers
func _group(n: String) -> Node3D:
	var g := Node3D.new()
	g.name = n
	root.add_child(g)
	return g


func _mesh_aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var a: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
		acc[0] = a if acc[0] == null else (acc[0] as AABB).merge(a)
	for c in n.get_children():
		_mesh_aabb(c, t, acc)


func _scene_aabb(n: Node) -> AABB:
	var acc := [null]
	_mesh_aabb(n, Transform3D.IDENTITY, acc)
	return acc[0] if acc[0] != null else AABB(Vector3.ZERO, Vector3.ONE * 0.1)


## A subset of a multi-object Poly Haven file saved as its own small scene.
func _piece(id: String, picks: Array) -> PackedScene:
	var key := id + "|" + ",".join(picks)
	if _piece_cache.has(key):
		return _piece_cache[key]
	var src: Node3D = load(PROP % [id, id]).instantiate()
	var out := Node3D.new()
	out.name = id
	for c in src.get_children():
		if picks.has(String(c.name)):
			var dup: Node = c.duplicate()
			out.add_child(dup)
	for c in out.get_children():
		_own_all(c, out)
	DirAccess.make_dir_recursive_absolute("res://assets/props/_pieces")
	var path := "res://assets/props/_pieces/%s__%s.scn" % [id, str(abs(key.hash()))]
	var ps := PackedScene.new()
	ps.pack(out)
	ResourceSaver.save(ps, path)
	src.free()
	out.free()
	var res: PackedScene = load(path)
	_piece_cache[key] = res
	return res


func _own_all(n: Node, o: Node) -> void:
	n.owner = o
	for c in n.get_children():
		_own_all(c, o)


## Place a prop so its footprint centre / bottom sits at `pos`.
## opts: scale, pick (Array), collide ("props" default | "world" | "none"),
## rot (Vector3 radians, overrides rot_y), name, raw (keep file origin), tint
func prop(parent: Node3D, id: String, pos: Vector3, rot_y := 0.0, opts := {}) -> Node3D:
	var ps: PackedScene = _piece(id, opts["pick"]) if opts.has("pick") else load(PROP % [id, id])
	var inst: Node3D = ps.instantiate()
	var akey := ps.resource_path
	if not _aabb_cache.has(akey):
		_aabb_cache[akey] = _scene_aabb(inst)
	var a: AABB = _aabb_cache[akey]
	var holder := Node3D.new()
	holder.name = opts.get("name", id.to_pascal_case())
	holder.position = pos
	holder.rotation = opts.get("rot", Vector3(0, rot_y, 0))
	holder.scale = Vector3.ONE * float(opts.get("scale", 1.0))
	parent.add_child(holder)
	var c := a.get_center()
	if not opts.get("raw", false):
		inst.position = -Vector3(c.x, a.position.y, c.z)
	holder.add_child(inst)
	var col: String = opts.get("collide", "props")
	if col != "none":
		var body := StaticBody3D.new()
		body.name = "Collision"
		body.collision_layer = LAYER_PROPS if col == "props" else 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = a.size
		cs.shape = bs
		cs.position = inst.position + c
		body.add_child(cs)
		holder.add_child(body)
	return holder


## Decal on a wall. `n` = the wall's outward normal (axis aligned), `c` = centre on
## the wall surface. Texture up = world up.
func decal_wall(parent: Node3D, tex: String, c: Vector3, n: Vector3, w: float, h: float, opts := {}) -> Decal:
	var d := Decal.new()
	d.name = opts.get("name", "Decal_" + tex)
	d.texture_albedo = load(DEC % tex)
	d.size = Vector3(w, float(opts.get("depth", 0.3)), h)
	var y := n.normalized()
	var z := Vector3.DOWN
	var x := y.cross(z)
	var basis := Basis(x, y, z)
	var roll: float = opts.get("roll", 0.0)
	if roll != 0.0:
		basis = Basis(y, roll) * basis
	d.transform = Transform3D(basis, c)
	_decal_common(d, opts)
	parent.add_child(d)
	return d


func decal_floor(parent: Node3D, tex: String, c: Vector3, w: float, l: float, yaw := 0.0, opts := {}) -> Decal:
	var d := Decal.new()
	d.name = opts.get("name", "Decal_" + tex)
	d.texture_albedo = load(DEC % tex)
	d.size = Vector3(w, float(opts.get("depth", 0.4)), l)
	d.position = c
	d.rotation.y = yaw
	_decal_common(d, opts)
	parent.add_child(d)
	return d


func _decal_common(d: Decal, opts: Dictionary) -> void:
	d.cull_mask = NO_PLAYER
	d.modulate = opts.get("modulate", Color.WHITE)
	d.albedo_mix = float(opts.get("mix", 1.0))
	d.upper_fade = 0.05
	d.lower_fade = 0.05
	d.normal_fade = float(opts.get("normal_fade", 0.35))
	d.distance_fade_enabled = true
	d.distance_fade_begin = 22.0
	d.distance_fade_length = 6.0
	if opts.has("orm"):
		d.texture_orm = load(DEC % opts["orm"])
	if opts.has("emission"):
		d.texture_emission = load(DEC % opts["emission"])
		d.emission_energy = float(opts.get("emission_energy", 1.0))


func audio_log(parent: Node3D, id: String, pos: Vector3, rot_y := 0.0) -> Node3D:
	return b.inst(parent, "res://scripts/interaction/audio_log.gd", "Log_" + id, pos, rot_y, {"log_id": id})


func readable(parent: Node3D, note: String, pos: Vector3, rot_y := 0.0, visual := "clipboard", box := Vector3(0.3, 0.06, 0.36)) -> Node3D:
	var r: Node3D = b.inst(parent, "res://scripts/interaction/readable.gd", "Doc_" + note, pos, rot_y, {"note_id": note, "box_size": box})
	if visual != "":
		var v := prop(r, visual, Vector3.ZERO, 0.0, {"collide": "none", "name": "Visual"})
		v.position.y = -box.y / 2.0
	return r


func spinner(parent: Node3D, n: String, pos: Vector3, axis: Vector3, speed: float, circuit := "", idle := 0.0) -> Node3D:
	var s := Node3D.new()
	s.name = n
	s.position = pos
	s.set_script(load("res://scripts/world/spinner.gd"))
	s.set("axis", axis)
	s.set("speed", speed)
	s.set("circuit", circuit)
	s.set("idle_speed", idle)
	parent.add_child(s)
	return s


func fan(parent: Node3D, n: String, pos: Vector3, normal: Vector3, radius: float, circuit := "", idle := 0.6) -> void:
	# wall extractor: square housing + grille + spinning 5-blade rotor
	var holder := Node3D.new()
	holder.name = n
	holder.position = pos
	parent.add_child(holder)
	holder.look_at_from_position(pos, pos + normal, Vector3.UP if absf(normal.y) < 0.9 else Vector3.FORWARD)
	var hs := radius * 2.3
	for k in 4:
		var horiz := k < 2
		var off := (radius * 1.1) * (1 if k % 2 == 0 else -1)
		var sz := Vector3(hs, 0.08, 0.25) if horiz else Vector3(0.08, hs, 0.25)
		var bx: Node3D = b.box(holder, "Frame%d" % k, sz, Vector3(0, off, 0) if horiz else Vector3(off, 0, 0), "rusty", false)
		bx.position.z = -0.1
	var rotor := spinner(holder, "Rotor", Vector3(0, 0, -0.12), Vector3(0, 0, 1), 9.0, circuit, idle)
	b.cyl(rotor, "Hub", radius * 0.18, 0.1, Vector3.ZERO, "dark_metal", Vector3(PI / 2, 0, 0))
	for k in 5:
		var blade: Node3D = b.box(rotor, "Blade%d" % k, Vector3(radius * 0.32, radius * 0.9, 0.015), Vector3.ZERO, "metal", false)
		blade.rotation = Vector3(0, 0.35, k * TAU / 5.0)
		blade.position = Vector3(0, radius * 0.5, 0).rotated(Vector3(0, 0, 1), k * TAU / 5.0)
	for k in 7:
		var bar: Node3D = b.box(holder, "Grille%d" % k, Vector3(radius * 2.1, 0.012, 0.012), Vector3(0, -radius + k * radius / 3.0, -0.02), "dark_metal", false)


func sway_cable(parent: Node3D, n: String, top: Vector3, length: float, with_lamp := false, circuit := "", flicker := 0.0) -> Node3D:
	var s := Node3D.new()
	s.name = n
	s.position = top
	s.set_script(load("res://scripts/world/sway.gd"))
	s.set("amplitude_deg", 4.0 if with_lamp else 7.0)
	s.set("period", 2.6 + length)
	s.set("phase", top.x * 3.1 + top.z)
	parent.add_child(s)
	b.cyl(s, "Cable", 0.011, length, Vector3(0, -length / 2.0, 0), "cable")
	if with_lamp:
		var lamp := prop(s, "caged_hanging_light", Vector3(0, -length, 0), 0.0, {"collide": "none", "raw": true, "name": "Lamp", "scale": 0.55})
		var pl: Node3D = b.light(s, "Bulb", Vector3(0, -length - 0.2, 0), Color(1.0, 0.78, 0.5), 1.2, 6.0, circuit, flicker, "lamp_warm", true, false)
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.1
		bulb.mesh = sm
		bulb.material_override = (b.mats["lamp_warm"] as StandardMaterial3D).duplicate()
		pl.add_child(bulb)
		bulb.position.y = 0.0
	else:
		# frayed end
		for k in 3:
			var w: Node3D = b.cyl(s, "Strand%d" % k, 0.004, 0.08, Vector3(0.01 * (k - 1), -length - 0.03, 0), "pipe", Vector3(0, 0, 0.3 * (k - 1)))
	return s


func sparker(parent: Node3D, n: String, pos: Vector3, rot_y: float, circuit := "") -> Node3D:
	var s := Node3D.new()
	s.name = n
	s.position = pos
	s.rotation.y = rot_y
	s.set_script(load("res://scripts/world/sparker.gd"))
	s.set("circuit", circuit)
	parent.add_child(s)
	return s


func steam(parent: Node3D, n: String, pos: Vector3, dir_yaw: float, strength := 1.0) -> void:
	var s := Node3D.new()
	s.name = n
	s.position = pos
	s.rotation.y = dir_yaw
	s.set_script(load("res://scripts/world/steam_vent.gd"))
	s.set("strength", strength)
	parent.add_child(s)


func crt(parent: Node3D, n: String, pos: Vector3, rot_y: float, content: String, circuit := "", glitchy := 0.5) -> void:
	var tv := prop(parent, "television_02", pos, rot_y, {"collide": "props", "name": n})
	var scr := MeshInstance3D.new()
	scr.name = "Screen"
	scr.set_script(load("res://scripts/world/crt_screen.gd"))
	var q := QuadMesh.new()
	q.size = Vector2(0.26, 0.2)
	scr.mesh = q
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/crt.gdshader")
	m.set_shader_parameter("content", load("res://assets/textures/" + content))
	scr.material_override = m
	scr.set("circuit", circuit)
	scr.set("glitchy", glitchy)
	scr.position = Vector3(-0.02, 0.22, 0.176)
	tv.add_child(scr)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.5, 1.0, 0.7)
	glow.omni_range = 2.2
	glow.light_energy = 0.4
	glow.shadow_enabled = false
	glow.position = Vector3(0, 0, 0.25)
	scr.add_child(glow)


func emitter(parent: Node3D, n: String, pos: Vector3, stream: String, unit := 6.0, vol := -6.0) -> void:
	var a := AudioStreamPlayer3D.new()
	a.name = n
	a.position = pos
	a.bus = &"Ambience"
	a.stream = load(stream)
	a.unit_size = unit
	a.volume_db = vol
	a.autoplay = true
	a.max_distance = 30.0
	a.set_script(load("res://scripts/world/loop_emitter.gd"))
	parent.add_child(a)


func sleeping_bag(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var g := Node3D.new()
	g.name = "SleepingBag"
	g.position = pos
	g.rotation.y = yaw
	parent.add_child(g)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.36
	cap.height = 1.95
	body.mesh = cap
	body.rotation.z = PI / 2
	body.scale = Vector3(0.22, 1.0, 1.0)
	body.position = Vector3(0, 0.075, 0)
	body.material_override = b.mats["sleeping_bag"]
	g.add_child(body)
	# folded-back top flap and a rolled jacket as a pillow
	var flap := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.55, 0.04, 0.62)
	flap.mesh = fb
	flap.position = Vector3(0.62, 0.17, 0.05)
	flap.rotation = Vector3(0.08, 0.2, 0.05)
	var fm: StandardMaterial3D = (b.mats["sleeping_bag"] as StandardMaterial3D).duplicate()
	fm.albedo_color = Color(0.3, 0.32, 0.28)
	flap.material_override = fm
	g.add_child(flap)
	var pillow := MeshInstance3D.new()
	var pc := CapsuleMesh.new()
	pc.radius = 0.12
	pc.height = 0.55
	pillow.mesh = pc
	pillow.rotation.x = PI / 2
	pillow.position = Vector3(1.05, 0.12, 0)
	var pmat: StandardMaterial3D = fm.duplicate()
	pmat.albedo_color = Color(0.22, 0.24, 0.2)
	pillow.material_override = pmat
	g.add_child(pillow)


func old_crate(parent: Node3D, n: String, pos: Vector3, yaw: float, chalk: String) -> void:
	var c := prop(parent, "wooden_military_crate", pos, yaw, {"name": n, "pick": ["wooden_military_crate", "wooden_military_crate_latch"]})
	var lid := prop(parent, "wooden_military_crate", pos + Vector3(0.0, 0.0, 0.0), yaw, {"name": n + "Lid", "pick": ["wooden_military_crate_lid"], "collide": "none"})
	lid.position += Vector3(cos(yaw + 1.2) * 0.75, 0.0, -sin(yaw + 1.2) * 0.75)
	lid.rotation = Vector3(0.0, yaw + 0.5, 0.06)
	if chalk != "":
		# chalk on the crate's front face
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		decal_wall(parent, chalk, pos + Vector3(0, 0.25, 0) + fwd * 0.26, fwd, 0.7, 0.35, {"depth": 0.12, "name": n + "Chalk"})


func pipe_run(parent: Node3D, n: String, a: Vector3, b2: Vector3, r: float, mat := "rusty") -> void:
	var mid := (a + b2) / 2.0
	var len := a.distance_to(b2)
	var holder := Node3D.new()
	holder.name = n
	parent.add_child(holder)
	holder.look_at_from_position(mid, b2, Vector3.UP if absf((b2 - a).normalized().y) < 0.95 else Vector3.FORWARD)
	b.cyl(holder, "Pipe", r, len, Vector3.ZERO, mat, Vector3(PI / 2, 0, 0))
	var k := 0
	var d := 0.0
	while d < len:
		b.cyl(holder, "Flange%d" % k, r * 1.35, 0.04, Vector3(0, 0, -len / 2.0 + d), "dark_metal", Vector3(PI / 2, 0, 0))
		d += 2.0
		k += 1


# ============================================================================ rooms
func _shaft() -> void:
	var g := _group("Shaft")
	# light shaft from the surface: a cold spot straight down through the dust
	var sun := SpotLight3D.new()
	sun.name = "SurfaceShaft"
	sun.light_color = Color(0.6, 0.7, 0.9)
	sun.light_energy = 6.0
	sun.spot_range = 22.0
	sun.spot_angle = 16.0
	sun.spot_attenuation = 0.4
	sun.shadow_enabled = true
	sun.light_volumetric_fog_energy = 5.0
	sun.position = Vector3(-0.8, 15.5, 3.4)
	sun.rotation.x = -PI / 2
	sun.light_cull_mask = NO_PLAYER | 2
	g.add_child(sun)
	# rotating amber/red beacon by the lift (battery backed, always on)
	var bea := spinner(g, "Beacon", Vector3(-1.8, 2.95, 5.42), Vector3.UP, 3.2)
	b.box(g, "BeaconPost", Vector3(0.1, 2.85, 0.1), Vector3(-1.8, 1.425, 5.42), "rusty", false)
	b.box(g, "LiftPanelPost", Vector3(0.08, 0.97, 0.08), Vector3(2.0, 0.485, 5.5), "rusty", false)
	b.cyl(g, "BeaconBase", 0.08, 0.1, Vector3(-1.8, 2.87, 5.42), "dark_metal")
	var bl := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.06
	bm.bottom_radius = 0.075
	bm.height = 0.12
	bl.mesh = bm
	bl.material_override = b.mats["lamp_red"]
	bl.position = Vector3(-1.8, 2.98, 5.42)
	g.add_child(bl)
	var bs := SpotLight3D.new()
	bs.light_color = Color(1.0, 0.18, 0.05)
	bs.light_energy = 5.0
	bs.spot_range = 9.0
	bs.spot_angle = 30.0
	bs.light_volumetric_fog_energy = 2.0
	bs.shadow_enabled = false
	bs.rotation.x = -0.25
	bea.add_child(bs)

	# old handoff crates from earlier relays, chalked by their owners
	old_crate(g, "OldCrateRelay2", Vector3(-3.3, 0.0, 1.0), PI / 2, "chalk_x")
	old_crate(g, "OldCrateExp1", Vector3(-3.35, 0.0, 6.6), PI / 2, "chalk_exp1")
	prop(g, "old_military_crate", Vector3(3.35, 0.0, 2.2), -PI / 2, {"pick": ["old_military_crate_a", "old_military_crate_lid_a", "old_military_crate_latch_a", "old_military_crate_loop_a"]})
	prop(g, "cardboard_box_01", Vector3(3.4, 0.31, 2.0), 0.4, {"collide": "none"})
	prop(g, "metal_jerrycan", Vector3(3.5, 0.0, 3.4), -1.4)
	prop(g, "portable_searchlight", Vector3(2.9, 0.0, 3.0), 2.4, {"collide": "none"})
	prop(g, "hand_truck", Vector3(3.55, 0.0, 0.8), -PI / 2 - 0.3, {"rot": Vector3(-0.28, -PI / 2, 0)})
	prop(g, "propane_tank", Vector3(-3.5, 0.0, 2.3), 0.0)
	prop(g, "can_rusted", Vector3(-2.8, 0.06, 1.9), 0.0, {"collide": "none", "rot": Vector3(PI / 2, 0.4, 0)})
	audio_log(g, "tape_relay", Vector3(-3.3, 0.48, 0.95), PI / 2)
	readable(g, "doc_relay_card", Vector3(3.8, 1.45, 5.9), -PI / 2, "", Vector3(0.05, 0.46, 0.4))
	b.box(g, "RelayCardBoard", Vector3(0.02, 0.5, 0.42), Vector3(3.83, 1.45, 5.9), "metal", false)
	decal_wall(g, "papers", Vector3(3.82, 1.45, 5.9), Vector3(-1, 0, 0), 0.5, 0.5, {"depth": 0.06})

	# story marks: tally of everyone who came down, scrawls
	decal_wall(g, "chalk_tally", Vector3(3.84, 1.6, 4.2), Vector3(-1, 0, 0), 1.6, 0.4, {"name": "TallyMarks"})
	decal_wall(g, "scrawl_count", Vector3(3.84, 2.2, 4.2), Vector3(-1, 0, 0), 1.5, 0.75, {"name": "SixBeforeMe"})
	decal_wall(g, "scrawl_one", Vector3(0.0, 4.4, 7.84), Vector3(0, 0, -1), 3.6, 1.8)
	decal_wall(g, "chalk_exp3", Vector3(-3.84, 1.4, 3.6), Vector3(1, 0, 0), 1.1, 0.55)
	decal_wall(g, "stencil_b2", Vector3(-1.9, 1.7, 0.16), Vector3(0, 0, 1), 1.1, 0.55, {"modulate": Color(0.9, 0.85, 0.7)})
	for k in 4:
		decal_wall(g, "leak_streak", Vector3(-3.0 + k * 2.1, 7.0 + (k % 2) * 2.0, 7.84), Vector3(0, 0, -1), 1.6, 6.0, {"depth": 0.25})
		decal_wall(g, "leak_streak", Vector3(-3.84, 6.0 + k, 1.0 + k * 1.9), Vector3(1, 0, 0), 1.4, 5.0, {"depth": 0.25})
	decal_floor(g, "grime", Vector3(-1.5, 0.0, 2.5), 3.0, 3.0, 0.4)
	decal_floor(g, "grime", Vector3(2.0, 0.0, 1.6), 2.5, 2.5, 1.4)
	decal_floor(g, "puddle", Vector3(-0.9, 0.0, 3.6), 1.8, 1.3, 0.3, {"orm": "puddle_orm"})
	decal_floor(g, "hazard_stripes", Vector3(0.0, 0.12, 5.42), 3.2, 0.3, 0.0, {"depth": 0.4})
	decal_floor(g, "chalk_floor_arrow", Vector3(0.4, 0.0, 1.0), 0.8, 0.8, PI / 2)
	# the dark above: dangling cables
	sway_cable(g, "ShaftCable1", Vector3(1.2, 12.0, 2.0), 5.5)
	sway_cable(g, "ShaftCable2", Vector3(-2.2, 12.0, 5.2), 7.0)
	emitter(g, "ShaftWind", Vector3(0, 10.0, 4.0), "res://audio/ambience/room_shaft.wav", 8.0, -10.0)


func _corridor() -> void:
	var g := _group("Corridor")
	# ceiling services
	pipe_run(g, "MainPipeA", Vector3(1.25, 2.85, 0.0), Vector3(1.25, 2.85, -22.0), 0.09)
	pipe_run(g, "MainPipeB", Vector3(0.98, 2.92, 0.0), Vector3(0.98, 2.92, -22.0), 0.06, "metal")
	steam(g, "SteamLeak", Vector3(1.1, 2.8, -10.6), -PI / 2, 0.9)
	decal_wall(g, "leak_streak", Vector3(1.59, 2.0, -10.6), Vector3(-1, 0, 0), 1.0, 2.4)
	decal_floor(g, "puddle", Vector3(0.75, 0.0, -10.6), 1.5, 1.8, 0.2, {"orm": "puddle_orm"})
	# a lamp hanging loose on its cable, swaying, flickering
	sway_cable(g, "LooseLamp", Vector3(-0.6, 3.15, -12.4), 0.9, true, "corridor_lights", 0.5)
	sway_cable(g, "LooseCable", Vector3(0.3, 3.15, -17.5), 0.75)
	# shorting junction box by the fuse panel
	prop(g, "power_box_01", Vector3(1.58, 2.1, -16.2), -PI / 2, {"collide": "none", "raw": true, "rot": Vector3(0, -PI / 2, 0)})
	sparker(g, "Sparks", Vector3(1.3, 2.05, -16.2), -PI / 2, "aux")
	decal_wall(g, "scorch", Vector3(1.59, 2.1, -16.2), Vector3(-1, 0, 0), 1.1, 1.3)
	# clutter left in the rush
	prop(g, "WetFloorSign_01", Vector3(-0.9, 0.15, -2.6), 0.0, {"rot": Vector3(0, 0.7, PI / 2), "collide": "none"})
	prop(g, "metal_trash_can", Vector3(-1.25, 0.0, -9.8), PI / 2, {"pick": ["metal_trash_can_rust", "metal_trash_can_rust_handle_left", "metal_trash_can_rust_handle_right"]})
	prop(g, "metal_trash_can", Vector3(-0.9, 0.0, -11.0), 0.6, {"pick": ["metal_trash_can_rust_lid"], "collide": "none"})
	prop(g, "cardboard_box_01", Vector3(1.22, 0.0, -3.2), 0.2)
	prop(g, "cardboard_box_01", Vector3(1.25, 0.34, -3.15), 1.1, {"collide": "none"})
	prop(g, "fire_alarm", Vector3(-1.58, 1.5, -8.5), PI / 2, {"collide": "none", "raw": true})
	prop(g, "security_camera_01", Vector3(-1.45, 2.95, -0.5), 0.0, {"collide": "none", "raw": true, "rot": Vector3(0.0, 2.6, 0.0)})
	prop(g, "wall_clock", Vector3(1.58, 2.35, -12.5), -PI / 2, {"collide": "none", "raw": true})
	prop(g, "industrial_wall_lamp", Vector3(-1.58, 2.4, -19.6), PI / 2, {"collide": "none", "raw": true})
	# signage, scrawls and handoff marks
	decal_wall(g, "chalk_arrow_gen", Vector3(-1.59, 1.6, -3.4), Vector3(1, 0, 0), 0.9, 0.45)
	decal_wall(g, "scrawl_lights", Vector3(1.59, 1.65, -13.5), Vector3(-1, 0, 0), 2.8, 1.4)
	decal_wall(g, "chalk_code", Vector3(1.59, 1.55, -19.6), Vector3(-1, 0, 0), 0.9, 0.45)
	decal_wall(g, "sign_caution", Vector3(-0.85, 1.85, -21.84), Vector3(0, 0, 1), 0.9, 0.45)
	decal_floor(g, "stencil_lab3", Vector3(0.0, 0.0, -18.8), 1.4, 0.7, 0.0, {"modulate": Color(0.85, 0.8, 0.6, 0.8)})
	for z in [-5.0, -7.0, -15.0]:
		var x := -1.25 if z != -7.0 else 1.25
		decal_floor(g, "hazard_stripes", Vector3(x, 0.0, z), 0.32, 1.8, PI / 2)
	decal_floor(g, "hazard_stripes", Vector3(0.0, 0.0, -21.7), 1.8, 0.32, 0.0)
	decal_floor(g, "papers", Vector3(-0.3, 0.0, -6.2), 1.6, 1.6, 0.4)
	decal_floor(g, "papers", Vector3(0.4, 0.0, -14.3), 1.4, 1.4, 2.1)
	decal_floor(g, "papers", Vector3(-0.5, 0.0, -20.4), 1.2, 1.2, 1.0)
	for k in 6:
		decal_floor(g, "grime", Vector3(-0.6 + (k % 3) * 0.6, 0.0, -1.5 - k * 3.6), 2.2, 2.6, k * 1.3)
	for k in 5:
		decal_wall(g, "leak_streak", Vector3(-1.59, 2.0, -1.8 - k * 4.3), Vector3(1, 0, 0), 1.0, 2.6)
		decal_wall(g, "rust_drip", Vector3(1.59, 2.2, -2.6 - k * 4.1), Vector3(-1, 0, 0), 0.8, 1.6)
	emitter(g, "MachineryBehindWall", Vector3(-3.0, 1.0, -11.0), "res://audio/ambience/distant_machinery.wav", 5.0, -14.0)


func _generator() -> void:
	var g := _group("GeneratorRoom")
	prop(g, "old_military_compressor", Vector3(-8.9, 0.0, -6.2), 0.0, {"collide": "world"})
	prop(g, "portable_generator", Vector3(-3.2, 0.0, -1.55), PI)
	prop(g, "Barrel_01", Vector3(-3.0, 0.0, -8.4), 0.0)
	prop(g, "barrel_03", Vector3(-2.3, 0.0, -8.45), 1.0)
	prop(g, "Barrel_01", Vector3(-3.3, 0.28, -7.6), 2.0, {"rot": Vector3(PI / 2, 0, 1.9), "collide": "props"})
	prop(g, "metal_tool_chest", Vector3(-7.4, 0.0, -8.65), 0.0)
	prop(g, "metal_toolbox", Vector3(-4.6, 0.0, -6.4), 0.9, {"collide": "none"})
	prop(g, "oil_tin", Vector3(-4.95, 0.0, -6.1), 0.0, {"collide": "none"})
	prop(g, "tool_cart", Vector3(-8.9, 0.0, -1.7), PI)
	prop(g, "metal_jerrycan_green", Vector3(-4.2, 0.0, -8.75), 0.1)
	# extractor fan in the north wall: turns on its own even with no power (ticket #0419)
	fan(g, "ExtractorFan", Vector3(-5.6, 2.3, -1.17), Vector3(0, 0, -1), 0.55, "aux", 0.8)
	readable(g, "doc_fan_ticket", Vector3(-7.4, 0.68, -8.6), 0.3, "clipboard", Vector3(0.24, 0.05, 0.34))
	audio_log(g, "tape_brandt", Vector3(-8.85, 0.97, -1.65), 0.4)
	pipe_run(g, "GenExhaust", Vector3(-6.0, 1.6, -5.4), Vector3(-6.0, 3.35, -5.4), 0.1)
	pipe_run(g, "GenPipeWall", Vector3(-9.85, 2.9, -1.2), Vector3(-9.85, 2.9, -8.8), 0.08)
	pipe_run(g, "GenPipeWall2", Vector3(-9.82, 2.6, -1.2), Vector3(-9.82, 2.6, -8.8), 0.05, "metal")
	decal_floor(g, "grime", Vector3(-6.0, 0.0, -5.0), 3.2, 3.2, 0.0)
	decal_floor(g, "puddle", Vector3(-4.5, 0.0, -7.5), 1.6, 1.2, 1.0, {"orm": "puddle_orm", "modulate": Color(0.5, 0.45, 0.3)})
	decal_floor(g, "grime", Vector3(-8.0, 0.0, -3.0), 2.4, 2.4, 2.0)
	decal_wall(g, "scorch", Vector3(-6.0, 3.2, -1.17), Vector3(0, 0, -1), 1.6, 1.4)
	decal_wall(g, "hazard_stripes", Vector3(-6.0, 0.1, -1.16), Vector3(0, 0, -1), 3.0, 0.2)
	decal_wall(g, "chalk_tally", Vector3(-9.84, 1.7, -6.8), Vector3(1, 0, 0), 1.0, 0.25)
	for k in 3:
		decal_wall(g, "leak_streak", Vector3(-9.84, 2.0, -2.2 - k * 2.4), Vector3(1, 0, 0), 1.2, 2.8)
		decal_wall(g, "rust_drip", Vector3(-3.5 - k * 2.2, 2.2, -8.84), Vector3(0, 0, 1), 1.0, 1.8)


func _security() -> void:
	var g := _group("Security")
	prop(g, "metal_office_desk", Vector3(5.5, 0.0, -10.2), PI, {"collide": "world"})
	crt(g, "MonitorA", Vector3(4.85, 0.79, -10.45), 0.15, "crt_security.png", "aux", 0.4)
	crt(g, "MonitorB", Vector3(5.5, 0.79, -10.5), -0.05, "crt_security.png", "aux", 0.9)
	prop(g, "vintage_radio_transceiver", Vector3(6.35, 0.79, -10.45), -0.2, {"collide": "none"})
	audio_log(g, "tape_okafor", Vector3(7.0, 0.79, -9.95), -0.4)
	prop(g, "office_notepads", Vector3(4.4, 0.79, -10.0), 0.4, {"collide": "none", "pick": ["office_notepads_a4_stack", "office_notepads_a4_a", "office_notepads_sticky_stack"]})
	prop(g, "binder_notebook", Vector3(4.6, 0.0, -9.2), 0.8, {"collide": "none", "pick": ["binder_notebook"]})
	prop(g, "SchoolChair_01", Vector3(5.2, 0.29, -8.7), 0.0, {"rot": Vector3(0, 0.9, PI / 2), "collide": "props"})
	prop(g, "security_camera_01", Vector3(7.85, 2.75, -3.3), 0.0, {"collide": "none", "raw": true, "rot": Vector3(0, -2.4, 0)})
	prop(g, "wall_clock", Vector3(7.97, 2.3, -6.8), -PI / 2, {"collide": "none", "raw": true})
	readable(g, "doc_roster", Vector3(2.0, 1.45, -10.97), 0.0, "", Vector3(0.36, 0.46, 0.04))
	b.box(g, "RosterBoard", Vector3(0.4, 0.5, 0.02), Vector3(2.0, 1.45, -10.99), "metal", false)
	decal_wall(g, "papers", Vector3(2.0, 1.45, -10.98), Vector3(0, 0, 1), 0.55, 0.55, {"depth": 0.06})
	decal_floor(g, "papers", Vector3(4.6, 0.0, -8.6), 2.0, 2.0, 0.3)
	decal_floor(g, "papers", Vector3(3.0, 0.0, -6.0), 1.4, 1.4, 1.9)
	decal_floor(g, "grime", Vector3(4.5, 0.0, -6.5), 3.0, 3.0, 0.4)
	decal_wall(g, "scrawl_leave", Vector3(4.6, 1.8, -3.16), Vector3(0, 0, -1), 2.6, 1.3)
	decal_wall(g, "chalk_exp3", Vector3(7.84, 1.55, -9.6), Vector3(-1, 0, 0), 0.8, 0.4)
	for k in 3:
		decal_wall(g, "leak_streak", Vector3(2.8 + k * 2.0, 1.9, -10.84), Vector3(0, 0, 1), 1.1, 2.4)


func _storage() -> void:
	var g := _group("Storage")
	prop(g, "steel_frame_shelves_02", Vector3(-7.55, 0.0, -18.4), PI / 2, {"collide": "world"})
	prop(g, "worn_metal_rack", Vector3(-2.2, 0.0, -18.5), 0.0, {"collide": "world"})
	prop(g, "plastic_crate_01", Vector3(-2.2, 0.82, -18.5), 0.3, {"collide": "none"})
	prop(g, "plastic_crate_03", Vector3(-2.2, 0.08, -18.5), 0.0, {"collide": "none"})
	prop(g, "industrial_pastic_container", Vector3(-7.4, 0.0, -12.6), 0.3, {"pick": ["industrial_pastic_container", "industrial_pastic_container_lid_a"]})
	prop(g, "medical_box", Vector3(-6.5, 0.7, -12.8), 0.5, {"collide": "none", "pick": ["medical_box", "medical_box_lid", "medical_box_latch", "medical_box_handle"]})
	prop(g, "long_life_food", Vector3(-5.6, 0.0, -17.85), 0.2, {"collide": "none"})
	prop(g, "russian_food_cans_01", Vector3(-6.0, 0.0, -16.85), 0.6, {"collide": "none"})
	prop(g, "plastic_jerrycan", Vector3(-7.45, 0.0, -14.0), 1.2)
	prop(g, "cardboard_box_01", Vector3(-4.4, 0.0, -12.45), 0.1)
	prop(g, "cardboard_box_01", Vector3(-4.95, 0.0, -12.5), 1.3, {"rot": Vector3(0.0, 1.3, 0.12)})
	# camp of an earlier relay member: sleeping bag, torch, tins, the tape
	sleeping_bag(g, Vector3(-6.4, 0.0, -17.45), 0.0)
	prop(g, "signal_flashlight", Vector3(-5.0, 0.02, -17.5), 0.6, {"collide": "none", "rot": Vector3(PI / 2, 0.6, 0)})
	prop(g, "can_rusted", Vector3(-5.1, 0.0, -17.85), 0.0, {"collide": "none"})
	audio_log(g, "tape_mara", Vector3(-5.05, 0.0, -16.85), 0.3)
	decal_floor(g, "grime", Vector3(-6.2, 0.0, -17.4), 2.6, 1.6, 0.0)
	decal_wall(g, "chalk_exp1", Vector3(-7.84, 1.5, -13.2), Vector3(1, 0, 0), 0.9, 0.45)
	decal_wall(g, "chalk_code", Vector3(-6.4, 1.3, -18.84), Vector3(0, 0, 1), 0.8, 0.4, {"roll": 0.05})
	decal_wall(g, "chalk_tally", Vector3(-7.84, 1.0, -17.4), Vector3(1, 0, 0), 1.2, 0.3)
	for k in 3:
		decal_wall(g, "leak_streak", Vector3(-7.84, 1.9, -12.8 - k * 2.0), Vector3(1, 0, 0), 1.0, 2.2)
	decal_floor(g, "puddle", Vector3(-3.2, 0.0, -16.6), 1.3, 1.0, 0.7, {"orm": "puddle_orm"})
	sway_cable(g, "StorageCable", Vector3(-4.2, 2.98, -15.2), 0.6)


func _lab() -> void:
	var g := _group("Lab")
	# bench clutter, left mid-experiment
	prop(g, "chemistry_set", Vector3(-0.75, 0.785, -29.6), 0.1, {"collide": "none", "pick": ["chemistry_set_beaker_large", "chemistry_set_beaker_med", "chemistry_set_test_tube_a", "chemistry_set_test_tube_content_a", "chemistry_set_test_tube_content_b", "chemistry_set_clamp_stand", "chemistry_set_clamp", "chemistry_set_bottle_dark_a"]})
	prop(g, "industrial_microscope", Vector3(-5.3, 0.785, -25.9), PI / 2, {"collide": "none"})
	prop(g, "bunsen_burner", Vector3(-5.25, 0.785, -27.6), 0.0, {"collide": "none", "pick": ["bunsen_burner"]})
	prop(g, "retro_multimeter", Vector3(5.3, 0.785, -25.8), -PI / 2, {"collide": "none"})
	prop(g, "circuit_board", Vector3(5.25, 0.785, -27.2), 0.4, {"collide": "none"})
	prop(g, "vintage_spacecraft_instrument", Vector3(5.3, 0.785, -28.4), -PI / 2 - 0.2, {"collide": "none"})
	crt(g, "LabMonitor", Vector3(0.9, 0.785, -29.78), 0.0, "crt_lab.png", "lab", 0.85)
	prop(g, "industrial_storage_cart", Vector3(4.2, 0.0, -23.2), 0.0, {"collide": "world"})
	prop(g, "medical_box", Vector3(4.2, 1.38, -23.2), 0.3, {"collide": "none", "pick": ["medical_box", "medical_box_lid", "medical_box_latch", "medical_box_handle"]})
	prop(g, "metal_stool_01", Vector3(-1.6, 0.18, -28.2), 0.0, {"rot": Vector3(PI / 2 - 0.05, 0.7, 0)})
	prop(g, "metal_stool_01", Vector3(2.1, 0.0, -30.6), 1.0)
	prop(g, "old_gas_mask", Vector3(-2.5, 0.1, -26.0), 0.0, {"collide": "none", "rot": Vector3(-PI / 2, 0.6, 0)})
	prop(g, "old_bed_frame", Vector3(-4.75, 0.0, -32.6), PI / 2, {"collide": "world"})
	sleeping_bag(g, Vector3(-4.75, 0.42, -32.6), 0.05)
	audio_log(g, "tape_varga1", Vector3(5.25, 0.785, -29.1), -PI / 2)
	audio_log(g, "tape_varga2", Vector3(3.9, 0.0, -31.5), 0.6)
	readable(g, "doc_h7_sheet", Vector3(-5.2, 0.81, -26.75), PI / 2 + 0.2, "clipboard", Vector3(0.24, 0.05, 0.34))
	# wreckage of tank 2: glass, spilled fluid, scorch
	decal_floor(g, "puddle", Vector3(3.0, 0.0, -31.6), 2.6, 2.2, 0.4, {"orm": "puddle_orm", "modulate": Color(0.3, 0.8, 0.7), "emission": "puddle", "emission_energy": 0.4})
	for k in 7:
		var p := Vector3(2.0 + fmod(k * 0.73, 2.1), 0.002, -31.0 - fmod(k * 0.41, 1.4))
		var shard := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.12 + fmod(k * 0.07, 0.15), 0.01, 0.08 + fmod(k * 0.05, 0.12))
		shard.mesh = pm
		shard.material_override = b.mats["glass"]
		shard.position = p
		shard.rotation = Vector3(-PI / 2, k * 1.7, 0)
		shard.name = "Shard%d" % k
		g.add_child(shard)
	decal_wall(g, "scorch", Vector3(3.0, 2.6, -33.84), Vector3(0, 0, 1), 2.2, 2.2)
	decal_wall(g, "scrawl_first", Vector3(-3.3, 2.0, -33.84), Vector3(0, 0, 1), 3.0, 1.5)
	decal_wall(g, "chalk_lab", Vector3(5.84, 1.8, -31.5), Vector3(-1, 0, 0), 1.0, 0.5)
	decal_wall(g, "sign_caution", Vector3(-4.2, 2.2, -22.16), Vector3(0, 0, -1), 1.0, 0.5)
	decal_floor(g, "papers", Vector3(-1.5, 0.0, -27.0), 2.2, 2.2, 0.2)
	decal_floor(g, "papers", Vector3(1.8, 0.0, -25.4), 1.8, 1.8, 2.4)
	decal_floor(g, "papers", Vector3(0.5, 0.0, -31.2), 1.6, 1.6, 4.1)
	for k in 6:
		decal_wall(g, "leak_streak", Vector3(-5.84, 2.6, -23.0 - k * 1.9), Vector3(1, 0, 0), 1.1, 3.0)
		decal_wall(g, "leak_streak", Vector3(5.84, 2.8, -23.4 - k * 1.8), Vector3(-1, 0, 0), 1.0, 2.8)
	for k in 4:
		decal_floor(g, "grime", Vector3(-3.0 + k * 2.0, 0.0, -24.0 - (k % 2) * 4.0), 3.0, 3.0, k * 0.9)
	# ceiling: dangling cables where a panel came down, one flickering CRT
	b.box(g, "FallenCeilingPanel", Vector3(1.2, 0.03, 0.6), Vector3(-2.6, 0.02, -24.6), "lab_ceiling", false, 0.35)
	sway_cable(g, "LabCable1", Vector3(-2.6, 4.18, -24.6), 1.6)
	sway_cable(g, "LabCable2", Vector3(-2.2, 4.18, -24.8), 1.2)
	sway_cable(g, "LabCable3", Vector3(-3.0, 4.18, -24.3), 2.0)
	sparker(g, "LabSparks", Vector3(-2.6, 4.1, -24.6), 0.0, "lab")
	fan(g, "LabCeilingVent", Vector3(2.5, 4.15, -25.0), Vector3(0, -1, 0), 0.4, "lab", 0.0)
	# emergency red rotating lamp over the door (lab circuit)
	var pl: Node3D = b.light(g, "LabBeaconPower", Vector3(1.4, 3.4, -22.25), Color(1, 0.1, 0.04), 0.3, 1.0, "lab", 0.0, "lamp_red", false, false)
	var bea := spinner(pl, "LabBeacon", Vector3.ZERO, Vector3.UP, 3.0, "lab")
	b.cyl(pl, "BeaconLens", 0.06, 0.12, Vector3(0, 0.05, 0), "lamp_red")
	var bs := SpotLight3D.new()
	bs.light_color = Color(1.0, 0.1, 0.04)
	bs.light_energy = 4.0
	bs.spot_range = 10.0
	bs.spot_angle = 28.0
	bs.light_volumetric_fog_energy = 2.0
	bs.rotation.x = -0.35
	bea.add_child(bs)


func _lift() -> void:
	var g := _group("Lift")
	# the cage: corner posts, roof frame, barred sides and back, open front with a
	# hazard-painted gate rail. One person per trip.
	var x0 := -1.6
	var x1 := 1.6
	var z0 := 5.42
	var z1 := 7.78
	var top := 2.7
	for p in [Vector2(x0, z0), Vector2(x1, z0), Vector2(x0, z1), Vector2(x1, z1)]:
		b.box(g, "CagePost", Vector3(0.09, top, 0.09), Vector3(p.x, top / 2.0 + 0.25, p.y), "rusty", false)
	for z in [z0, z1]:
		b.box(g, "CageBeamX", Vector3(x1 - x0, 0.1, 0.1), Vector3(0, top + 0.25, z), "rusty", false)
	for x in [x0, x1]:
		b.box(g, "CageBeamZ", Vector3(0.1, 0.1, z1 - z0), Vector3(x, top + 0.25, (z0 + z1) / 2.0), "rusty", false)
		var n := int((z1 - z0) / 0.22)
		for k in n:
			b.box(g, "CageBarSide", Vector3(0.022, top, 0.022), Vector3(x, top / 2.0 + 0.25, z0 + 0.11 + k * 0.22), "rusty", false)
		b.box(g, "CageMidRail", Vector3(0.05, 0.05, z1 - z0), Vector3(x, 1.25, (z0 + z1) / 2.0), "rusty", false)
	for k in 14:
		b.box(g, "CageBarBack", Vector3(0.022, top, 0.022), Vector3(x0 + 0.11 + k * 0.22, top / 2.0 + 0.25, z1 - 0.04), "rusty", false)
	b.box(g, "CageRoof", Vector3(x1 - x0, 0.03, z1 - z0), Vector3(0, top + 0.31, (z0 + z1) / 2.0), "grate", false)
	b.box(g, "GateRailTop", Vector3(3.2, 0.06, 0.05), Vector3(0, 1.15, z0), "hazard", false)
	# the cage front stops the player and the camera: without it the spawn camera
	# sits inside the cage looking through the bars
	var wall := StaticBody3D.new()
	wall.name = "CageFrontCollision"
	wall.collision_layer = 1
	wall.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(x1 - x0 + 0.1, 3.0, 0.1)
	cs.shape = bx
	cs.position = Vector3(0, 1.5, z0 + 0.03)
	wall.add_child(cs)
	g.add_child(wall)
	b.box(g, "GateRailLow", Vector3(3.2, 0.05, 0.04), Vector3(0, 0.55, z0), "rusty", false)
	prop(g, "caged_hanging_light", Vector3(0.0, top + 0.2, 6.6), 0.0, {"collide": "none", "raw": true, "scale": 0.6})
	b.light(g, "CageLamp", Vector3(0.0, top - 0.3, 6.6), Color(1.0, 0.7, 0.45), 0.6, 4.0, "", 0.25, "lamp_warm", false, false)
	decal_wall(g, "stencil_lift", Vector3(0.0, 2.2, 7.84), Vector3(0, 0, -1), 1.4, 0.7, {"modulate": Color(0.85, 0.75, 0.4)})
	b.label(g, "ONE PERSON PER TRIP", Vector3(0.0, 2.75, z0 - 0.06), PI, 34, Color(0.9, 0.75, 0.3))



# ============================================================================ phase 4 areas
func _archive() -> void:
	var g := _group("Archive")
	# anteroom: rows of records, the roster wall, Mara's third tape
	prop(g, "steel_frame_shelves_02", Vector3(2.15, 0.0, -13.0), PI / 2, {"collide": "world"})
	prop(g, "worn_metal_rack", Vector3(5.55, 0.0, -14.9), -PI / 2, {"collide": "world"})
	prop(g, "binder_notebook", Vector3(2.2, 0.98, -13.1), 0.3, {"collide": "none", "pick": ["binder_notebook"]})
	prop(g, "office_notepads", Vector3(5.5, 0.82, -14.9), 0.6, {"collide": "none", "pick": ["office_notepads_a4_stack", "office_notepads_a4_a"]})
	prop(g, "cardboard_box_01", Vector3(2.4, 0.0, -15.4), 0.4)
	prop(g, "cardboard_box_01", Vector3(2.35, 0.36, -15.35), 1.1, {"collide": "none"})
	prop(g, "metal_office_desk", Vector3(3.8, 0.0, -12.55), 0.0, {"collide": "world"})
	audio_log(g, "tape_mara3", Vector3(3.4, 0.79, -12.5), 0.2)
	readable(g, "doc_relay_rosters", Vector3(4.25, 0.8, -12.55), 0.1, "clipboard", Vector3(0.24, 0.05, 0.34))
	decal_floor(g, "papers", Vector3(3.6, 0.0, -14.2), 2.4, 2.4, 0.7)
	decal_floor(g, "grime", Vector3(4.0, 0.0, -14.0), 3.0, 3.0, 1.1)
	decal_wall(g, "chalk_tally", Vector3(5.84, 1.7, -13.9), Vector3(-1, 0, 0), 1.4, 0.35)
	decal_wall(g, "scrawl_count", Vector3(3.0, 2.0, -15.84), Vector3(0, 0, 1), 1.3, 0.65)
	for k in 2:
		decal_wall(g, "leak_streak", Vector3(2.6 + k * 2.2, 1.9, -12.16), Vector3(0, 0, -1), 1.0, 2.2)
	# vault: the transmitter, cable up the shaft wall
	b.box(g, "TransmitterRack", Vector3(0.7, 1.5, 1.4), Vector3(8.55, 0.75, -19.2), "dark_metal", true)
	b.box(g, "TransmitterFace", Vector3(0.02, 0.9, 1.2), Vector3(8.19, 1.0, -19.2), "metal", false)
	prop(g, "vintage_radio_transceiver", Vector3(8.4, 1.5, -18.9), -PI / 2, {"collide": "none"})
	prop(g, "retro_multimeter", Vector3(8.35, 1.5, -19.6), -PI / 2, {"collide": "none"})
	pipe_run(g, "RelayCable", Vector3(8.8, 1.6, -19.2), Vector3(8.8, 3.2, -19.2), 0.06)
	pipe_run(g, "RelayCable2", Vector3(8.8, 3.0, -19.2), Vector3(8.8, 3.0, -16.4), 0.06)
	readable(g, "doc_relay_log", Vector3(7.6, 0.8, -20.9), 0.0, "clipboard", Vector3(0.24, 0.05, 0.34))
	prop(g, "metal_stool_01", Vector3(7.4, 0.0, -19.8), 0.6)
	prop(g, "steel_frame_shelves_02", Vector3(2.15, 0.0, -19.5), PI / 2, {"collide": "world"})
	prop(g, "wooden_military_crate", Vector3(3.6, 0.0, -21.0), 0.1, {"pick": ["wooden_military_crate", "wooden_military_crate_latch"]})
	decal_floor(g, "grime", Vector3(6.0, 0.0, -19.0), 3.4, 3.4, 0.4)
	decal_wall(g, "hazard_stripes", Vector3(8.84, 0.1, -19.2), Vector3(-1, 0, 0), 1.6, 0.2)
	decal_wall(g, "chalk_x", Vector3(4.0, 1.4, -21.34), Vector3(0, 0, 1), 0.7, 0.7)


func _camp() -> void:
	var g := _group("OldCamp")
	# the crawl: rubble, a cable, chalk arrows that glow a little (Mara's paint)
	decal_floor(g, "grime", Vector3(-14.0, 0.0, -5.5), 8.0, 1.4, 0.0)
	pipe_run(g, "CrawlPipe", Vector3(-10.2, 1.45, -5.0), Vector3(-17.8, 1.45, -5.0), 0.07)
	decal_wall(g, "chalk_tally", Vector3(-14.0, 0.8, -4.99), Vector3(0, 0, -1), 1.2, 0.3)
	# the camp that isn't ours
	sleeping_bag(g, Vector3(-19.4, 0.0, -3.0), PI / 2)
	sleeping_bag(g, Vector3(-23.6, 0.0, -2.9), PI / 2 + 0.2)
	old_crate(g, "CampCrateA", Vector3(-19.4, 0.0, -8.2), 0.0, "chalk_x")
	old_crate(g, "CampCrateB", Vector3(-24.1, 0.0, -8.3), 0.1, "chalk_tally")
	old_crate(g, "CampCrateC", Vector3(-24.2, 0.0, -5.2), PI / 2, "")
	prop(g, "signal_flashlight", Vector3(-19.0, 0.02, -3.6), 0.6, {"collide": "none", "rot": Vector3(PI / 2, 0.6, 0)})
	prop(g, "can_rusted", Vector3(-20.2, 0.0, -3.9), 0.0, {"collide": "none"})
	prop(g, "old_gas_mask", Vector3(-22.4, 0.06, -6.7), 0.0, {"collide": "none", "rot": Vector3(-PI / 2, 1.2, 0)})
	prop(g, "propane_tank", Vector3(-24.4, 0.0, -2.6), 0.0)
	audio_log(g, "tape_mara2", Vector3(-19.4, 0.48, -8.15), 0.0)
	audio_log(g, "tape_mara4", Vector3(-24.2, 0.48, -5.2), PI / 2)
	readable(g, "doc_camp_list", Vector3(-19.1, 0.05, -2.55), 0.2, "clipboard", Vector3(0.24, 0.05, 0.34))
	# the tally that's older than the station: the whole north wall
	for k in 5:
		decal_wall(g, "chalk_tally", Vector3(-24.4 + k * 1.3, 1.0 + (k % 2) * 0.55, -2.16), Vector3(0, 0, -1), 1.2, 0.3, {"modulate": Color(1, 1, 1, 0.8)})
	decal_wall(g, "scrawl_first", Vector3(-21.5, 2.0, -8.84), Vector3(0, 0, 1), 2.8, 1.4)
	decal_wall(g, "sign_caution", Vector3(-18.16, 1.9, -6.9), Vector3(1, 0, 0), 0.9, 0.45)
	for k in 3:
		decal_floor(g, "mark_arrow", Vector3(-19.3 - k * 1.5, 0.0, -5.4), 0.7, 0.7, PI / 2 + 0.1 * k, {"emission": "mark_arrow_glow", "emission_energy": 0.8, "modulate": Color(0.7, 1.0, 0.75)})
	decal_floor(g, "grime", Vector3(-21.5, 0.0, -5.5), 6.0, 6.0, 0.3)
	emitter(g, "CampWind", Vector3(-21.0, 2.0, -5.5), "res://audio/ambience/room_storage.wav", 4.0, -14.0)


func _phase4_extras() -> void:
	var g := _group("Phase4")
	# Security: duty terminal that prints the rotated lab code (needs power)
	crt(g, "DutyTerminal", Vector3(2.35, 0.79, -8.55), PI / 2, "crt_security.png", "aux", 0.2)
	b.box(g, "DutyTerminalDesk", Vector3(0.7, 0.04, 1.2), Vector3(2.2, 0.77, -8.5), "dark_metal", true)
	for x in [1.95, 2.45]:
		for z in [-9.0, -8.0]:
			b.box(g, "DutyLeg", Vector3(0.04, 0.77, 0.04), Vector3(x, 0.385, z), "dark_metal", false)
	b.inst(g, "res://scripts/interaction/readable.gd", "DutyTerminalScreen", Vector3(2.5, 1.0, -8.55), PI / 2, {"note_id": "doc_rotation", "verb": "Read", "box_size": Vector3(0.34, 0.3, 0.12), "required_circuit": "aux", "no_power_text": "The terminal is dead. No power"})
	# Lab 3 freezer unit (lights up blue when the last circuit feeds it)
	var fz := Node3D.new()
	fz.name = "LabFreezer"
	fz.set_script(load("res://scripts/world/freezer_unit.gd"))
	fz.position = Vector3(-5.25, 0.0, -24.0)
	fz.rotation.y = PI / 2
	g.add_child(fz)
	# lift line lamp by the cage (green when the lift + relay line is powered)
	var ll := Node3D.new()
	ll.name = "LiftLineLamp"
	ll.set_script(load("res://scripts/world/freezer_unit.gd"))
	ll.set("mode", "lift")
	ll.position = Vector3(2.0, 1.75, 5.45)
	g.add_child(ll)
	decal_wall(g, "sign_caution", Vector3(-9.84, 1.9, -6.6), Vector3(1, 0, 0), 0.7, 0.35)
	_security_fill()
	_storage_fill()


## Art fix: Security felt empty. Shelving, a bin, boxes, wall kit, a second chair.
func _security_fill() -> void:
	var g := _group("SecurityFill")
	prop(g, "steel_frame_shelves_02", Vector3(5.6, 0.0, -3.42), PI, {"collide": "world", "name": "SecShelf"})
	prop(g, "binder_notebook", Vector3(5.2, 1.0, -3.45), 0.1, {"collide": "none", "pick": ["binder_notebook"], "name": "SecBinders"})
	prop(g, "cardboard_box_01", Vector3(6.1, 0.42, -3.45), 0.2, {"collide": "none", "scale": 0.8, "name": "SecShelfBox"})
	prop(g, "office_notepads", Vector3(5.0, 1.42, -3.45), 0.5, {"collide": "none", "pick": ["office_notepads_a4_stack"], "name": "SecPads"})
	prop(g, "metal_trash_can", Vector3(6.75, 0.0, -9.35), 0.4)
	prop(g, "cardboard_box_01", Vector3(7.45, 0.0, -10.45), 0.2)
	prop(g, "cardboard_box_01", Vector3(7.4, 0.36, -10.4), 1.0, {"collide": "none"})
	prop(g, "cardboard_box_01", Vector3(6.8, 0.0, -10.55), 2.6)
	prop(g, "SchoolChair_01", Vector3(3.6, 0.0, -8.6), 2.2)
	prop(g, "portable_searchlight", Vector3(3.2, 0.0, -3.6), 2.4)
	prop(g, "fire_alarm", Vector3(1.75, 1.6, -4.4), PI / 2, {"collide": "none", "raw": true})
	prop(g, "power_box_01", Vector3(7.88, 1.4, -8.5), -PI / 2, {"collide": "none"})
	b.box(g, "KeyCabinet", Vector3(0.05, 0.5, 0.4), Vector3(7.93, 1.55, -4.6), "metal", false)
	for k in 6:
		b.box(g, "KeyHook%d" % k, Vector3(0.03, 0.006, 0.006), Vector3(7.89, 1.66 - (k / 3) * 0.16, -4.72 + (k % 3) * 0.12), "metal", false)
	decal_floor(g, "papers", Vector3(6.6, 0.0, -4.4), 1.5, 1.5, 2.1)
	decal_wall(g, "sign_caution", Vector3(2.4, 2.4, -10.84), Vector3(0, 0, 1), 0.9, 0.45)


## Art fix: Storage needed more stock. Shelving with crates, barrels, a hand truck,
## a wet-floor sign by the live puddle (the warning is real).
func _storage_fill() -> void:
	var g := _group("StorageFill")
	prop(g, "steel_frame_shelves_02", Vector3(-7.55, 0.0, -15.6), PI / 2, {"collide": "world", "name": "StoShelfW"})
	prop(g, "plastic_crate_01", Vector3(-7.5, 0.08, -15.3), 0.1, {"collide": "none"})
	prop(g, "plastic_crate_03", Vector3(-7.5, 0.83, -15.9), 0.0, {"collide": "none"})
	prop(g, "cardboard_box_01", Vector3(-7.5, 1.55, -15.5), 0.4, {"collide": "none", "scale": 0.85})
	prop(g, "old_military_crate", Vector3(-5.7, 0.0, -12.55), 0.05)
	prop(g, "old_military_crate", Vector3(-5.65, 0.42, -12.6), 0.25, {"collide": "none", "scale": 0.9})
	prop(g, "barrel_03", Vector3(-2.4, 0.0, -17.6), 0.6)
	prop(g, "hand_truck", Vector3(-3.6, 0.0, -18.55), 0.2)
	prop(g, "metal_jerrycan", Vector3(-6.9, 0.0, -14.0), 0.9)
	prop(g, "WetFloorSign_01", Vector3(-2.2, 0.0, -16.9), 0.6)
	prop(g, "power_box_01", Vector3(-3.25, 2.3, -18.88), 0.0, {"collide": "none"})
	pipe_run(g, "WireConduit", Vector3(-3.25, 2.6, -18.85), Vector3(-3.25, 2.96, -18.85), 0.03)
	pipe_run(g, "WireConduit2", Vector3(-3.25, 2.95, -18.85), Vector3(-3.25, 2.95, -16.6), 0.03)
	decal_floor(g, "grime", Vector3(-3.6, 0.0, -15.0), 2.4, 2.4, 1.4)
