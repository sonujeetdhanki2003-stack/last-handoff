extends Node
## Generates the greybox facility, the player scene and the game scene as real,
## editor-editable .tscn files.  Run:
##   godot --headless --path . res://tools/build_scenes.tscn
## Re-running overwrites scenes/levels/facility_greybox.tscn, scenes/player.tscn
## and scenes/game.tscn. Phase 3 can replace the greybox with art and keep the
## same node names / interactable scripts.

const TEX := "res://assets/textures/"
var mats := {}
var level: Node3D


func _ready() -> void:
	_make_materials()
	ResourceSaver.save(UIKit.make_theme(), "res://ui/theme.tres")
	_build_player()
	_build_level()
	_build_game()
	print("BUILD OK")
	get_tree().quit(0)


# ----------------------------------------------------------------------------- materials
func _tex_mat(id: String, scale: float, tint := Color.WHITE, metal_tex := false, rough_mul := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("%s%s/%s_1K-JPG_Color.jpg" % [TEX, id, id])
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load("%s%s/%s_1K-JPG_NormalGL.jpg" % [TEX, id, id])
	m.roughness_texture = load("%s%s/%s_1K-JPG_Roughness.jpg" % [TEX, id, id])
	m.roughness = rough_mul
	if metal_tex and ResourceLoader.exists("%s%s/%s_1K-JPG_Metalness.jpg" % [TEX, id, id]):
		m.metallic_texture = load("%s%s/%s_1K-JPG_Metalness.jpg" % [TEX, id, id])
		m.metallic = 1.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _flat(c: Color, metal := 0.0, rough := 0.7, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	return m


func _save_mat(n: String, m: Material) -> Material:
	var p := "res://assets/materials/%s.tres" % n
	ResourceSaver.save(m, p)
	var r := load(p)
	mats[n] = r
	return r


func _surf(n: String, id: String, scale: float, params := {}) -> Material:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/facility_surface.gdshader")
	var base := "res://assets/textures/ph/%s_" % id
	m.set_shader_parameter("albedo_tex", load(base + "diff.jpg"))
	m.set_shader_parameter("normal_tex", load(base + "nor.jpg"))
	m.set_shader_parameter("rough_tex", load(base + "rough.jpg"))
	if ResourceLoader.exists(base + "ao.jpg"):
		m.set_shader_parameter("ao_tex", load(base + "ao.jpg"))
	m.set_shader_parameter("grime_tex", load("res://assets/textures/grime_tile.png"))
	m.set_shader_parameter("scale", scale)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return _save_mat(n, m)


## Poly Haven texture set on a StandardMaterial3D (world triplanar) for props
## built from primitives (shelves, crates, frames).
func _ph_mat(n: String, id: String, scale: float, tint := Color.WHITE, metal := 0.0, rough := 1.0) -> Material:
	var m := StandardMaterial3D.new()
	var base := "res://assets/textures/ph/%s_" % id
	m.albedo_texture = load(base + "diff.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(base + "nor.jpg")
	m.roughness_texture = load(base + "rough.jpg")
	m.roughness = rough
	m.metallic = metal
	if ResourceLoader.exists(base + "ao.jpg"):
		m.ao_enabled = true
		m.ao_texture = load(base + "ao.jpg")
		m.ao_light_affect = 0.3
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return _save_mat(n, m)


func _make_materials() -> void:
	# --- architecture (facility_surface shader: triplanar PBR + procedural wear)
	_surf("concrete_floor", "concrete_floor_damaged_01", 0.38, {"tint": Color(0.72, 0.7, 0.66), "wet": 0.55, "dirt_strength": 0.5})
	_surf("storage_floor", "damaged_concrete_floor", 0.4, {"tint": Color(0.7, 0.68, 0.64), "wet": 0.3, "dirt_strength": 0.55})
	_surf("concrete_wall", "dirty_concrete", 0.3, {"tint": Color(0.78, 0.76, 0.72), "streak_strength": 0.5, "dirt_strength": 0.6})
	_surf("shaft_wall", "cracked_concrete_wall", 0.22, {"tint": Color(0.72, 0.72, 0.7), "streak_strength": 0.65, "dirt_height": 1.1, "dirt_strength": 0.65})
	_surf("ceiling", "concrete_wall_008", 0.3, {"tint": Color(0.45, 0.45, 0.44), "dirt_strength": 0.0, "streak_strength": 0.2, "mottle_strength": 0.5})
	_surf("metal_floor", "metal_plate", 0.55, {"tint": Color(0.62, 0.6, 0.57), "metallic": 0.55, "rough_mul": 0.9, "dirt_strength": 0.45, "wet": 0.35})
	# institutional two-tone paint: dark green below the rail, nicotine cream above
	_surf("painted_metal", "painted_concrete", 0.35, {"paint_mix": 0.85, "band_y": 1.15, "lower_color": Color(0.17, 0.26, 0.22), "upper_color": Color(0.5, 0.48, 0.4), "streak_strength": 0.55, "dirt_strength": 0.6})
	_surf("office_wall", "painted_concrete_02", 0.35, {"paint_mix": 0.7, "band_y": 1.0, "lower_color": Color(0.2, 0.23, 0.27), "upper_color": Color(0.52, 0.52, 0.48), "streak_strength": 0.45})
	_surf("office_floor", "worn_tile_floor", 0.45, {"tint": Color(0.62, 0.6, 0.56), "dirt_strength": 0.5, "wet": 0.2})
	_surf("lab_tiles", "long_white_tiles", 0.42, {"tint": Color(0.78, 0.78, 0.72), "streak_strength": 0.75, "dirt_strength": 0.6, "dirt_height": 0.9, "mottle_strength": 0.45})
	_surf("lab_floor", "worn_tile_floor", 0.5, {"tint": Color(0.7, 0.72, 0.7), "wet": 0.6, "dirt_strength": 0.45})
	_surf("lab_ceiling", "metal_plate_02", 0.4, {"tint": Color(0.4, 0.42, 0.42), "metallic": 0.4, "dirt_strength": 0.0, "streak_strength": 0.3})
	# --- props built from primitives
	_ph_mat("metal", "rusty_painted_metal", 0.9, Color(0.62, 0.66, 0.62), 0.5, 1.0)
	_ph_mat("rusty", "rusty_metal_02", 0.7, Color(0.8, 0.78, 0.75), 0.6, 1.0)
	_ph_mat("green_metal", "green_metal_rust", 0.8, Color(0.75, 0.8, 0.75), 0.55, 1.0)
	_ph_mat("grate", "metal_grate_rusty", 0.6, Color(0.7, 0.7, 0.68), 0.6, 1.0)
	_ph_mat("wood_crate", "worn_planks", 0.9, Color(0.75, 0.68, 0.6), 0.0, 1.0)
	_save_mat("dark_metal", _flat(Color(0.075, 0.08, 0.085), 0.7, 0.5))
	_save_mat("hazard", _flat(Color(0.75, 0.52, 0.09), 0.1, 0.65))
	_save_mat("lamp_warm", _flat(Color(1.0, 0.86, 0.62), 0.0, 0.5, 5.0))
	_save_mat("lamp_cold", _flat(Color(0.75, 0.88, 1.0), 0.0, 0.5, 5.0))
	_save_mat("lamp_red", _flat(Color(1.0, 0.08, 0.04), 0.0, 0.5, 4.0))
	_save_mat("screen_green", _flat(Color(0.3, 1.0, 0.6), 0.0, 0.3, 1.6))
	_save_mat("tank_glow", _flat(Color(0.2, 0.9, 0.8), 0.0, 0.1, 1.2))
	_save_mat("pipe", _flat(Color(0.22, 0.23, 0.23), 0.8, 0.45))
	_save_mat("rubber", _flat(Color(0.05, 0.05, 0.05), 0.0, 0.9))
	_save_mat("cable", _flat(Color(0.03, 0.03, 0.03), 0.0, 0.6))
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.42, 0.13, 0.07)
	cloth.roughness = 0.95
	cloth.normal_enabled = true
	cloth.normal_texture = load("res://assets/textures/ph/rubber_tiles_nor.jpg")
	cloth.normal_scale = 0.3
	cloth.uv1_scale = Vector3(4, 4, 4)
	_save_mat("sleeping_bag", cloth)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.55, 0.75, 0.72, 0.18)
	glass.roughness = 0.08
	glass.metallic = 0.2
	glass.metallic_specular = 0.9
	_save_mat("glass", glass)


# ----------------------------------------------------------------------------- helpers
func _own(n: Node, owner_: Node) -> void:
	if n != owner_:
		n.owner = owner_
	if n.scene_file_path != "" and n != owner_:
		return  # instanced scene: keep its internals out of our file
	for c in n.get_children():
		_own(c, owner_)


func box(parent: Node3D, n: String, size: Vector3, center: Vector3, mat: String, collide := true, rot_y := 0.0) -> Node3D:
	var host: Node3D
	if collide:
		host = StaticBody3D.new()
		host.collision_layer = 1
		host.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		host.add_child(cs)
	else:
		host = Node3D.new()
	host.name = n
	host.position = center
	host.rotation.y = rot_y
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mats[mat]
	host.add_child(mi)
	parent.add_child(host)
	return host


func cyl(parent: Node3D, n: String, r: float, h: float, center: Vector3, mat: String, rot := Vector3.ZERO, collide := false) -> Node3D:
	var host: Node3D = StaticBody3D.new() if collide else Node3D.new()
	host.name = n
	host.position = center
	host.rotation = rot
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	mi.mesh = cm
	mi.material_override = mats[mat]
	host.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var s := CylinderShape3D.new()
		s.radius = r
		s.height = h
		cs.shape = s
		host.add_child(cs)
	parent.add_child(host)
	return host


## Wall along X (z fixed) or Z (x fixed) from a to b with door openings.
## openings: Array of [center_along_axis, width, height]
func wall(parent: Node3D, n: String, axis: String, fixed: float, a: float, b: float, h: float, openings: Array = [], mat := "concrete_wall", t := 0.3, base := 0.0) -> void:
	var cuts := openings.duplicate()
	cuts.sort_custom(func(x, y): return x[0] < y[0])
	var cur := a
	var idx := 0
	for o in cuts:
		var o0: float = o[0] - o[1] / 2.0
		var o1: float = o[0] + o[1] / 2.0
		if o0 > cur:
			_wall_seg(parent, "%s_%d" % [n, idx], axis, fixed, cur, o0, base, h, mat, t)
			idx += 1
		# lintel above the opening
		_wall_seg(parent, "%s_%d" % [n, idx], axis, fixed, o0, o1, base + o[2], h, mat, t)
		idx += 1
		cur = o1
	if cur < b:
		_wall_seg(parent, "%s_%d" % [n, idx], axis, fixed, cur, b, base, h, mat, t)


func _wall_seg(parent: Node3D, n: String, axis: String, fixed: float, a: float, b: float, y0: float, y1: float, mat: String, t: float) -> void:
	var len := b - a
	if len <= 0.001 or y1 - y0 <= 0.001:
		return
	var mid := (a + b) / 2.0
	var cy := (y0 + y1) / 2.0
	if axis == "x":
		box(parent, n, Vector3(len, y1 - y0, t), Vector3(mid, cy, fixed), mat)
	else:
		box(parent, n, Vector3(t, y1 - y0, len), Vector3(fixed, cy, mid), mat)


func slab(parent: Node3D, n: String, x0: float, x1: float, z0: float, z1: float, y: float, mat: String, t := 0.2) -> void:
	box(parent, n, Vector3(x1 - x0, t, z1 - z0), Vector3((x0 + x1) / 2.0, y - t / 2.0 if y <= 0.01 else y + t / 2.0, (z0 + z1) / 2.0), mat)


func room(parent: Node3D, n: String, x0: float, x1: float, z0: float, z1: float, h: float, floor_mat := "concrete_floor", ceil_mat := "concrete_wall") -> Node3D:
	var r := Node3D.new()
	r.name = n
	parent.add_child(r)
	slab(r, "Floor", x0, x1, z0, z1, 0.0, floor_mat)
	if h > 0.0:
		slab(r, "Ceiling", x0, x1, z0, z1, h, ceil_mat)
	return r


func light(parent: Node3D, n: String, pos: Vector3, color: Color, energy: float, rng: float, circuit := "", flicker := 0.0, lamp_mat := "lamp_warm", shadow := true, fixture := true) -> Node3D:
	var pl := Node3D.new()
	pl.name = n
	pl.position = pos
	pl.set_script(load("res://scripts/world/powered_light.gd"))
	pl.set("circuit", circuit)
	pl.set("flicker", flicker)
	pl.set("power_on_delay", 0.25 if circuit != "" else 0.0)
	parent.add_child(pl)
	var o := OmniLight3D.new()
	o.name = "Omni"
	o.light_color = color
	o.light_energy = energy
	o.omni_range = rng
	o.omni_attenuation = 1.3
	o.shadow_enabled = shadow
	o.position.y = -0.25
	pl.add_child(o)
	if fixture:
		# twin-tube fluorescent batten on short hanger rods
		var m: StandardMaterial3D = (mats[lamp_mat] as StandardMaterial3D).duplicate()
		for k in 2:
			var tube := MeshInstance3D.new()
			tube.name = "Fixture" if k == 0 else "Fixture2"
			var tm := CylinderMesh.new()
			tm.top_radius = 0.022
			tm.bottom_radius = 0.022
			tm.height = 1.15
			tm.radial_segments = 10
			tube.mesh = tm
			tube.rotation.z = PI / 2
			tube.position = Vector3(0, -0.02, -0.055 + k * 0.11)
			tube.material_override = m
			tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pl.add_child(tube)
		var hous := MeshInstance3D.new()
		hous.name = "Housing"
		var hb := BoxMesh.new()
		hb.size = Vector3(1.25, 0.07, 0.24)
		hous.mesh = hb
		hous.position.y = 0.04
		hous.material_override = mats["metal"]
		pl.add_child(hous)
		for x in [-0.45, 0.45]:
			var rod := MeshInstance3D.new()
			var rm := CylinderMesh.new()
			rm.top_radius = 0.006
			rm.bottom_radius = 0.006
			rm.height = 0.3
			rod.mesh = rm
			rod.position = Vector3(x, 0.22, 0)
			rod.material_override = mats["dark_metal"]
			pl.add_child(rod)
	return pl


func label(parent: Node3D, text: String, pos: Vector3, rot_y: float, size := 64, col := Color(0.85, 0.85, 0.8)) -> void:
	var l := Label3D.new()
	l.name = "Sign_" + text.left(12).replace(" ", "_").replace("\n", "_").validate_node_name()
	l.text = text
	l.font = load("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = col
	l.outline_size = 0
	l.position = pos
	l.rotation.y = rot_y
	l.shaded = true
	l.double_sided = false  # never readable (mirrored) from behind
	parent.add_child(l)


func inst(parent: Node3D, script_path: String, n: String, pos: Vector3, rot_y := 0.0, props := {}) -> Node3D:
	var cls: Script = load(script_path)
	var node: Node3D = cls.new()
	node.name = n
	node.position = pos
	node.rotation.y = rot_y
	for k in props:
		node.set(k, props[k])
	parent.add_child(node)
	return node


func pickup(parent: Node3D, item: String, pos: Vector3, n := "", qty := 1, rot_y := 0.0) -> Node3D:
	var nn := n if n != "" else "Pickup_" + item
	return inst(parent, "res://scripts/interaction/pickup.gd", nn, pos, rot_y, {"item_id": item, "quantity": qty, "persist_id": "pickup_" + nn.to_lower()})


func crate(parent: Node3D, n: String, pos: Vector3, s := 0.6, rot := 0.0) -> void:
	var c := box(parent, n, Vector3(s, s, s), pos + Vector3(0, s / 2.0, 0), "wood_crate", true, rot)
	# corner battens + metal bands so it reads as a real shipping crate
	for k in 4:
		var x := (s / 2.0 - 0.025) * (1 if k % 2 == 0 else -1)
		var z := (s / 2.0 - 0.025) * (1 if k < 2 else -1)
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.06, s + 0.004, 0.06)
		post.mesh = pm
		post.position = Vector3(x, 0, z)
		post.material_override = mats["wood_crate"]
		c.add_child(post)
	for y in [-0.3, 0.3]:
		var band := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(s + 0.012, 0.035, s + 0.012)
		band.mesh = bm
		band.material_override = mats["rusty"]
		band.position.y = s * y
		c.add_child(band)


func shelf(parent: Node3D, n: String, pos: Vector3, rot_y := 0.0, w := 1.6) -> void:
	var s := Node3D.new()
	s.name = n
	s.position = pos
	s.rotation.y = rot_y
	parent.add_child(s)
	# every board and post collides on its own, so items on the boards stay
	# reachable (a single box collider would swallow them)
	for i in 4:
		box(s, "Board%d" % i, Vector3(w, 0.04, 0.45), Vector3(0, 0.15 + i * 0.6, 0), "metal", true)
	var k := 0
	for x in [-w / 2.0 + 0.03, w / 2.0 - 0.03]:
		for z in [-0.2, 0.2]:
			box(s, "Post%d" % k, Vector3(0.04, 2.0, 0.04), Vector3(x, 1.0, z), "dark_metal", true)
			k += 1
	box(s, "Back", Vector3(w, 1.9, 0.02), Vector3(0, 1.0, -0.22), "dark_metal", true)


func desk(parent: Node3D, n: String, pos: Vector3, rot_y := 0.0, w := 1.6, cabinet := false) -> void:
	var d := Node3D.new()
	d.name = n
	d.position = pos
	d.rotation.y = rot_y
	parent.add_child(d)
	box(d, "Top", Vector3(w, 0.05, 0.75), Vector3(0, 0.76, 0), "metal", true)
	if cabinet:
		box(d, "Cabinet", Vector3(w - 0.1, 0.66, 0.66), Vector3(0, 0.4, 0), "green_metal", true)
		box(d, "Kick", Vector3(w - 0.14, 0.07, 0.6), Vector3(0, 0.035, 0.02), "dark_metal", false)
		for k in int(w / 0.55):
			var x := -w / 2.0 + 0.32 + k * 0.55
			box(d, "Handle%d" % k, Vector3(0.14, 0.02, 0.02), Vector3(x, 0.66, 0.34), "dark_metal", false)
	else:
		for x in [-w / 2.0 + 0.05, w / 2.0 - 0.05]:
			box(d, "Leg", Vector3(0.05, 0.74, 0.7), Vector3(x, 0.37, 0), "dark_metal", true)


# ----------------------------------------------------------------------------- player
func _build_player() -> void:
	var p := CharacterBody3D.new()
	p.name = "Player"
	p.set_script(load("res://scripts/player/player.gd"))
	p.collision_layer = 2
	p.collision_mask = 1 | 8  # world + props layer (props do not block camera or aim)
	p.floor_snap_length = 0.3
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	p.add_child(cs)

	# Quaternius Universal Base Character (retargeted to Godot's humanoid profile on
	# import) driven by the Universal Animation Library clips (also retargeted).
	var model: Node3D = load("res://assets/characters/explorer/Explorer.gltf").instantiate()
	model.name = "Model"
	model.rotation.y = PI
	p.add_child(model)
	var src: Node = load("res://assets/characters/mannequin/AnimationLibrary_Godot_Standard.gltf").instantiate()
	var lib: AnimationLibrary = (src.get_node("AnimationPlayer") as AnimationPlayer).get_animation_library(&"")
	ResourceSaver.save(lib, "res://assets/characters/ual_animations.res")
	src.free()
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	model.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library(&"", load("res://assets/characters/ual_animations.res"))

	var at := AnimationTree.new()
	at.name = "AnimationTree"
	at.set_script(load("res://scripts/player/player_animator.gd"))
	p.add_child(at)
	at.root_node = NodePath("../Model")
	at.anim_player = NodePath("../Model/AnimationPlayer")

	var rig := Node3D.new()
	rig.name = "CameraRig"
	rig.set_script(load("res://scripts/player/camera_rig.gd"))
	p.add_child(rig)
	rig.set("target_path", NodePath(".."))
	var yaw := Node3D.new()
	yaw.name = "Yaw"
	rig.add_child(yaw)
	var pitch := Node3D.new()
	pitch.name = "Pitch"
	yaw.add_child(pitch)
	var arm := SpringArm3D.new()
	arm.name = "SpringArm3D"
	arm.spring_length = 2.8
	arm.margin = 0.12
	arm.collision_mask = 1
	var sph := SphereShape3D.new()
	sph.radius = 0.22
	arm.shape = sph
	pitch.add_child(arm)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	cam.near = 0.05
	cam.far = 120.0
	arm.add_child(cam)

	var fl := Node3D.new()
	fl.name = "Flashlight"
	fl.set_script(load("res://scripts/player/flashlight.gd"))
	p.add_child(fl)
	var spot := SpotLight3D.new()
	spot.name = "SpotLight3D"
	spot.light_color = Color(1.0, 0.95, 0.85)
	spot.light_energy = 9.0
	spot.spot_range = 24.0
	spot.spot_angle = 26.0
	spot.spot_angle_attenuation = 0.9
	spot.spot_attenuation = 0.85
	spot.shadow_enabled = true
	spot.shadow_blur = 1.5
	spot.light_cull_mask = 0xFFFFF & ~2
	spot.light_volumetric_fog_energy = 1.5
	fl.add_child(spot)
	# a faint fill so the area right around the beam is not pitch black
	var fill := OmniLight3D.new()
	fill.name = "BounceFill"
	fill.light_color = Color(1.0, 0.95, 0.85)
	fill.light_energy = 0.35
	fill.omni_range = 2.2
	fill.light_cull_mask = 2  # only the character: keeps them readable without a hotspot on walls
	spot.add_child(fill)

	var steps := AudioStreamPlayer3D.new()
	steps.name = "Footsteps"
	steps.bus = &"SFX"
	if ResourceLoader.exists("res://audio/sfx/footstep.wav"):
		steps.stream = load("res://audio/sfx/footstep.wav")
	p.add_child(steps)

	_own(p, p)
	ap.owner = p
	var ps := PackedScene.new()
	var err := ps.pack(p)
	assert(err == OK)
	ResourceSaver.save(ps, "res://scenes/player.tscn")
	p.free()


# ----------------------------------------------------------------------------- level
func _build_level() -> void:
	level = Node3D.new()
	level.name = "FacilityGreybox"
	level.set_script(load("res://scripts/world/level.gd"))

	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	env.set_script(load("res://scripts/world/world_env.gd"))
	level.add_child(env)

	var geo := Node3D.new()
	geo.name = "Geometry"
	level.add_child(geo)
	var lights := Node3D.new()
	lights.name = "Lights"
	level.add_child(lights)
	var inter := Node3D.new()
	inter.name = "Interactables"
	level.add_child(inter)
	var props := Node3D.new()
	props.name = "Props"
	level.add_child(props)

	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = Vector3(0.6, 0.05, 4.4)
	level.add_child(spawn)

	var WH := 4.4  # wall height for rooms
	var DW := 1.8  # door opening width
	var DH := 2.6  # door opening height

	# --- Entrance shaft (x -4..4, z 0..8), open to the dark above
	var shaft := room(geo, "EntranceShaft", -4, 4, 0, 8, 0.0, "metal_floor")
	wall(shaft, "WallBack", "x", 8.0, -4.15, 4.15, 16.0, [], "shaft_wall")
	wall(shaft, "WallW", "z", -4.0, 0, 8, 16.0, [], "shaft_wall")
	wall(shaft, "WallE", "z", 4.0, 0, 8, 16.0, [], "shaft_wall")
	wall(shaft, "WallFront", "x", 0.0, -4.15, 4.15, 16.0, [[0.0, DW, DH]], "shaft_wall")
	slab(shaft, "Cap", -4.2, 4.2, -0.2, 8.2, 16.0, "dark_metal")
	# lift cage
	box(shaft, "LiftPlatform", Vector3(3.2, 0.25, 2.4), Vector3(0, 0.125, 6.6), "metal_floor")
	for x in [-1.6, 1.6]:
		box(shaft, "LiftRail", Vector3(0.18, 16.0, 0.18), Vector3(x, 8.0, 7.85), "dark_metal", true)
	box(shaft, "LiftCounterweight", Vector3(1.2, 1.4, 0.3), Vector3(-2.6, 9.0, 7.6), "dark_metal", false)
	for i in 6:
		cyl(shaft, "Cable%d" % i, 0.025, 16.0, Vector3(-0.6 + i * 0.24, 8.2, 7.7), "pipe")
	label(shaft, "HALDEN DEEP RESEARCH STATION\nLEVEL B2", Vector3(0, 3.4, 0.17), 0.0, 64)
	label(shaft, "GENERATOR  /  SECURITY  /  LAB 3", Vector3(0, 2.9, 0.17), 0.0, 36, Color(0.9, 0.7, 0.3))
	box(shaft, "HazardStrip", Vector3(1.9, 0.01, 0.3), Vector3(0, 0.005, 0.35), "hazard", false)

	# --- Corridor (x -1.6..1.6, z -22..0)
	var cor := room(geo, "Corridor", -1.6, 1.6, -22, 0, 3.2, "concrete_floor", "ceiling")
	wall(cor, "WallW", "z", -1.6, -22, 0, WH, [[-5.0, DW, DH], [-15.0, DW, DH]], "painted_metal")
	wall(cor, "WallE", "z", 1.6, -22, 0, WH, [[-7.0, DW, DH], [-14.0, DW, DH]], "painted_metal")
	# pipes and cable tray along the ceiling
	for i in 3:
		cyl(cor, "Pipe%d" % i, 0.07 + i * 0.02, 22.0, Vector3(1.15 - i * 0.22, 2.95 - i * 0.03, -11.0), "pipe", Vector3(PI / 2, 0, 0))
	box(cor, "CableTray", Vector3(0.4, 0.06, 22.0), Vector3(-1.15, 2.9, -11.0), "dark_metal", false)
	for z in [-3.0, -9.5, -12.5, -19.5]:
		box(cor, "Rib", Vector3(3.2, 0.25, 0.25), Vector3(0, 3.07, z), "dark_metal", false)
	label(cor, "<  GENERATOR", Vector3(-1.44, 2.7, -3.2), PI / 2, 44, Color(0.9, 0.7, 0.3))
	label(cor, "SECURITY  >", Vector3(1.44, 2.7, -5.6), -PI / 2, 44, Color(0.9, 0.7, 0.3))
	label(cor, "<  STORAGE", Vector3(-1.44, 2.7, -13.2), PI / 2, 44, Color(0.9, 0.7, 0.3))
	label(cor, "LAB 3  -  AUTHORISED ONLY", Vector3(0, 2.95, -21.83), 0, 40, Color(0.95, 0.3, 0.25))
	for z in [-5.0, -7.0, -15.0, -21.6]:
		pass

	# --- Generator room (x -10..-1.6, z -9..-1)
	var gen := room(geo, "GeneratorRoom", -10, -1.6, -9, -1, 3.4, "concrete_floor", "ceiling")
	wall(gen, "WallN", "x", -1.0, -10.15, -1.6, WH)
	wall(gen, "WallS", "x", -9.0, -10.15, -1.6, WH)
	wall(gen, "WallW", "z", -10.0, -9, -1, WH, [[-5.5, 1.3, 1.6]])
	shelf(gen, "Shelf", Vector3(-8.9, 0, -8.55), 0.0)
	crate(gen, "Crate1", Vector3(-9.2, 0, -1.7))
	crate(gen, "Crate2", Vector3(-8.5, 0, -1.6), 0.5, 0.3)
	cyl(gen, "Exhaust", 0.12, 3.0, Vector3(-6.0, 3.0, -5.5), "pipe", Vector3(0, 0, PI / 2))

	# --- Security office (x 1.6..8, z -11..-3)
	var sec := room(geo, "SecurityOffice", 1.6, 8, -11, -3, 3.0, "office_floor", "ceiling")
	wall(sec, "WallN", "x", -3.0, 1.6, 8.15, WH, [], "office_wall")
	wall(sec, "WallS", "x", -11.0, 1.6, 8.15, WH, [], "office_wall")
	wall(sec, "WallE", "z", 8.0, -11, -3, WH, [], "office_wall")
	# desk: the visual is a Poly Haven metal office desk (see _dress_security); this
	# invisible top keeps the memo resting where the playthrough expects it.
	box(sec, "DeskTop", Vector3(2.0, 0.04, 0.9), Vector3(5.5, 0.77, -10.2), "dark_metal", true).get_node("Mesh").visible = false
	shelf(sec, "Lockers", Vector3(7.6, 0, -5.2), -PI / 2, 2.0)

	# --- Storage (x -8..-1.6, z -19..-12)
	var sto := room(geo, "Storage", -8, -1.6, -19, -12, 3.0, "storage_floor", "ceiling")
	wall(sto, "WallN", "x", -12.0, -8.15, -1.6, WH)
	wall(sto, "WallS", "x", -19.0, -8.15, -1.6, WH)
	wall(sto, "WallW", "z", -8.0, -19, -12, WH)
	shelf(sto, "ShelfA", Vector3(-5.0, 0, -18.55), 0.0, 2.4)
	shelf(sto, "ShelfB", Vector3(-7.55, 0, -15.5), PI / 2, 2.4)
	crate(sto, "CrateA", Vector3(-3.0, 0, -13.0))
	crate(sto, "CrateB", Vector3(-3.2, 0.6, -13.0), 0.5, 0.4)
	crate(sto, "CrateC", Vector3(-6.5, 0, -12.8), 0.7, 0.2)

	# --- Lab 3 (x -6..6, z -34..-22)
	var lab := room(geo, "Lab3", -6, 6, -34, -22, 4.2, "lab_floor", "lab_ceiling")
	wall(lab, "WallS", "x", -22.0, -6.15, 6.15, WH, [[0.0, DW, DH]], "lab_tiles")
	wall(lab, "WallN", "x", -34.0, -6.15, 6.15, WH, [], "lab_tiles")
	wall(lab, "WallW", "z", -6.0, -34, -22, WH, [], "lab_tiles")
	wall(lab, "WallE", "z", 6.0, -34, -22, WH, [], "lab_tiles")
	desk(lab, "CentreBench", Vector3(0, 0, -29.5), 0.0, 2.6, true)
	desk(lab, "BenchW", Vector3(-5.3, 0, -27.0), PI / 2, 3.0, true)
	desk(lab, "BenchE", Vector3(5.3, 0, -27.0), -PI / 2, 3.0, true)
	for i in 3:
		var x := -3.0 + i * 3.0
		if i == 2:  # the breached tank: shattered glass stub, drained
			cyl(lab, "Tank%d" % i, 0.55, 0.75, Vector3(x, 0.55, -32.8), "glass", Vector3.ZERO, true)
			cyl(lab, "TankFluid%d" % i, 0.5, 0.12, Vector3(x, 0.26, -32.8), "tank_glow")
			for k in 3:
				cyl(lab, "TankRod%d" % k, 0.02, 2.6, Vector3(x + cos(k * 2.1) * 0.56, 1.3, -32.8 + sin(k * 2.1) * 0.56), "dark_metal")
		else:
			cyl(lab, "Tank%d" % i, 0.55, 2.6, Vector3(x, 1.3, -32.8), "glass", Vector3.ZERO, true)
			cyl(lab, "TankFluid%d" % i, 0.5, 1.9 - i * 0.5, Vector3(x, 0.95 - i * 0.25, -32.8), "tank_glow")
		cyl(lab, "TankBase%d" % i, 0.62, 0.2, Vector3(x, 0.1, -32.8), "dark_metal")
		cyl(lab, "TankCap%d" % i, 0.62, 0.2, Vector3(x, 2.7, -32.8), "dark_metal")
	label(lab, "LAB 3  -  CONTAINMENT RESEARCH", Vector3(0, 3.3, -33.83), 0, 56)

	# ----------------------------------------------------------------- lights
	light(lights, "ShaftTopLight", Vector3(0, 9.0, 4.0), Color(0.55, 0.65, 0.85), 1.6, 12.0, "", 0.0, "lamp_cold", false, false)
	light(lights, "ShaftLiftLamp", Vector3(1.9, 2.5, 7.6), Color(1.0, 0.25, 0.1), 0.8, 4.0, "", 0.3, "lamp_red", false)
	for i in 5:
		light(lights, "CorridorLamp%d" % i, Vector3(0, 3.1, -2.0 - i * 4.5), Color(1.0, 0.85, 0.62), 1.6, 6.0, "corridor_lights", 0.15 if i == 3 else 0.0)
	for i in 3:
		light(lights, "EmergencyLamp%d" % i, Vector3(1.3, 2.6, -3.5 - i * 7.0), Color(1.0, 0.1, 0.05), 0.9, 5.0, "aux", 0.0, "lamp_red", false)
	light(lights, "GeneratorRoomLamp", Vector3(-5.8, 3.3, -5.0), Color(1.0, 0.82, 0.55), 2.2, 9.0, "aux", 0.05)
	light(lights, "SecurityLamp", Vector3(4.8, 2.9, -7.0), Color(0.9, 0.95, 1.0), 1.6, 8.0, "aux", 0.0, "lamp_cold")
	light(lights, "StorageLamp", Vector3(-4.8, 2.9, -15.5), Color(1.0, 0.8, 0.55), 1.0, 6.0, "aux", 0.6)
	for i in 2:
		light(lights, "LabLamp%d" % i, Vector3(-2.5 + i * 5.0, 4.1, -28.0), Color(0.75, 0.88, 1.0), 1.3, 10.0, "lab", 0.08 if i == 1 else 0.0, "lamp_cold")
	light(lights, "LabTankGlow", Vector3(0, 1.4, -32.0), Color(0.2, 0.9, 0.8), 0.8, 6.0, "", 0.0, "tank_glow", false, false)

	# ----------------------------------------------------------------- interactables
	var d_shaft := inst(inter, "res://scripts/interaction/door.gd", "DoorShaft", Vector3(0, 0, 0), 0.0, {"door_label": "B2 ACCESS", "persist_id": "door_shaft"})
	inst(inter, "res://scripts/interaction/door.gd", "DoorGenerator", Vector3(-1.6, 0, -5.0), PI / 2, {"door_label": "GENERATOR", "persist_id": "door_generator"})
	inst(inter, "res://scripts/interaction/door.gd", "DoorSecurity", Vector3(1.6, 0, -7.0), -PI / 2, {"door_label": "SECURITY", "required_circuit": "aux", "persist_id": "door_security"})
	inst(inter, "res://scripts/interaction/door.gd", "DoorStorage", Vector3(-1.6, 0, -15.0), PI / 2, {"door_label": "STORAGE", "key_item": "keycard_blue", "persist_id": "door_storage"})
	var d_lab := inst(inter, "res://scripts/interaction/door.gd", "DoorLab", Vector3(0, 0, -22.0), 0.0, {"door_label": "LAB 3", "required_circuit": "lab", "needs_code": true, "persist_id": "door_lab"})
	inst(inter, "res://scripts/interaction/keypad.gd", "LabKeypad", Vector3(1.25, 1.3, -21.8), 0.0, {"door_path": NodePath("../DoorLab"), "required_circuit": "lab", "persist_id": "keypad_lab", "no_power_text": "Keypad dead. Lab circuit has no power"})
	inst(inter, "res://scripts/interaction/generator.gd", "Generator", Vector3(-6.0, 0, -5.0), PI / 2, {"persist_id": "generator_aux"})
	inst(inter, "res://scripts/interaction/lever.gd", "LightsBreaker", Vector3(-9.83, 1.4, -3.0), PI / 2, {"circuit_id": "corridor_lights", "label_text": "CORRIDOR LIGHTS", "persist_id": "lever_lights"})
	inst(inter, "res://scripts/interaction/fuse_panel.gd", "FusePanel", Vector3(1.43, 1.35, -17.0), -PI / 2, {"persist_id": "fuse_panel"})
	inst(inter, "res://scripts/interaction/lever.gd", "MasterSwitch", Vector3(1.43, 1.4, -18.3), -PI / 2, {"circuit_id": "lab", "label_text": "LAB 3 MASTER", "requires_flag": "fuse_panel_complete", "requires_flag_text": "Dead. The fuse panel next to it is empty", "one_way": true, "persist_id": "lever_master"})
	inst(inter, "res://scripts/interaction/charging_dock.gd", "ChargingDock", Vector3(7.83, 1.2, -8.5), -PI / 2, {"persist_id": ""})
	var lift := inst(inter, "res://scripts/interaction/lift.gd", "LiftPanel", Vector3(2.0, 1.2, 5.45), PI, {})
	_lift_panel_visual(lift)

	inst(inter, "res://scripts/world/trigger_flag.gd", "LabEntryTrigger", Vector3(0, 0, -24.0), 0.0, {"flag": "lab_entered", "size": Vector3(4.0, 2.5, 2.0)})

	# handoff crate from the previous expedition
	crate(props, "HandoffCrate", Vector3(-2.2, 0, 3.2), 0.62, 0.2)
	label(props, "EXP-0", Vector3(-2.2, 0.36, 3.52), 0.2, 30, Color(0.95, 0.6, 0.35))
	pickup(inter, "keycard_blue", Vector3(-2.4, 0.63, 3.0), "Keycard")
	pickup(inter, "battery", Vector3(-1.98, 0.63, 3.42), "BatteryCrate")
	pickup(inter, "note_handoff", Vector3(-2.05, 0.63, 3.05), "HandoffNote")
	# fuses
	pickup(inter, "fuse", Vector3(-8.7, 0.77, -8.55), "FuseGenerator")
	pickup(inter, "fuse", Vector3(-4.6, 1.37, -18.55), "FuseStorage")
	pickup(inter, "fuse", Vector3(7.55, 0.77, -4.8), "FuseSecurity")
	# batteries + documents
	pickup(inter, "battery", Vector3(-3.0, 1.23, -13.0), "BatteryStorage")
	pickup(inter, "note_code", Vector3(6.1, 0.8, -10.15), "SecurityMemo")
	pickup(inter, "research_drive", Vector3(0.2, 0.8, -29.5), "ResearchDrive")

	_build_phase4(geo, lights, inter, props)

	# Phase 3 art pass: props, decals, story, audio logs, animation, ambience
	load("res://tools/dress.gd").new(self).run(level)

	_own(level, level)
	var ps := PackedScene.new()
	var err := ps.pack(level)
	assert(err == OK)
	ResourceSaver.save(ps, "res://scenes/levels/facility_greybox.tscn")
	level.free()


# ----------------------------------------------------------------------------- phase 4
## Areas that open later (archive, generator crawlspace + the old camp), hiding spots,
## hazards, the three decision points, the transmitter, new items.
func _build_phase4(geo: Node3D, lights: Node3D, inter: Node3D, _props: Node3D) -> void:
	var WH := 4.4
	# --- Archive: anteroom (x 1.6..6, z -16..-12) + vault (x 1.6..9, z -21.5..-16)
	var ante := room(geo, "ArchiveAnte", 1.6, 6.0, -16, -12, 3.0, "office_floor", "ceiling")
	wall(ante, "WallN", "x", -12.0, 1.6, 6.15, WH, [], "office_wall")
	wall(ante, "WallE", "z", 6.0, -16, -12, WH, [], "office_wall")
	wall(ante, "WallS", "x", -16.0, 1.6, 9.15, WH, [[4.0, 1.8, 2.6]], "office_wall")
	var vault := room(geo, "ArchiveVault", 1.6, 9.0, -21.5, -16, 3.2, "office_floor", "ceiling")
	wall(vault, "WallS", "x", -21.5, 1.6, 9.15, WH, [], "office_wall")
	wall(vault, "WallE", "z", 9.0, -21.5, -16, WH, [], "office_wall")
	label(ante, "ARCHIVE  /  RELAY RECORDS", Vector3(3.8, 2.75, -12.17), PI, 40, Color(0.9, 0.7, 0.3))
	label(geo, "ARCHIVE  >", Vector3(1.44, 2.7, -12.4), -PI / 2, 44, Color(0.9, 0.7, 0.3))
	label(vault, "VAULT  -  RELAY TRANSMITTER", Vector3(4.0, 2.85, -15.83), 0.0, 34, Color(0.95, 0.3, 0.25))

	# --- Crawlspace (x -18..-10, z -6.15..-4.85), 1.6 m of headroom: crouch through
	var crawl := room(geo, "Crawlspace", -18, -10, -6.15, -4.85, 1.8, "concrete_floor", "ceiling")
	wall(crawl, "WallN", "x", -4.85, -18.0, -10.0, 1.8)
	wall(crawl, "WallS", "x", -6.15, -18.0, -10.0, 1.8)
	# --- The old camp (x -25..-18, z -9..-2)
	var camp := room(geo, "OldCamp", -25, -18, -9, -2, 2.8, "concrete_floor", "ceiling")
	wall(camp, "WallE", "z", -18.0, -9, -2, 3.2, [[-5.5, 1.3, 1.6]])
	wall(camp, "WallW", "z", -25.0, -9, -2, 3.2)
	wall(camp, "WallN", "x", -2.0, -25.15, -17.85, 3.2)
	wall(camp, "WallS", "x", -9.0, -25.15, -17.85, 3.2)

	# --- lights for the new areas (white light keeps the Keeper back; red doesn't)
	light(lights, "ArchiveLamp", Vector3(3.8, 2.9, -14.0), Color(1.0, 0.86, 0.66), 1.1, 6.0, "lab", 0.25)
	light(lights, "VaultLamp", Vector3(5.5, 3.1, -18.8), Color(1.0, 0.15, 0.06), 0.9, 6.0, "lab", 0.0, "lamp_red", false)
	light(lights, "CampGlow", Vector3(-21.0, 2.6, -3.2), Color(1.0, 0.2, 0.08), 0.35, 5.0, "", 0.2, "lamp_red", false)

	# --- doors
	inst(inter, "res://scripts/interaction/door.gd", "DoorArchive", Vector3(1.6, 0, -14.0), -PI / 2, {"door_label": "ARCHIVE", "key_item": "keycard_red", "required_circuit": "lab", "persist_id": "door_archive"})
	inst(inter, "res://scripts/interaction/door.gd", "DoorVault", Vector3(4.0, 0, -16.0), 0.0, {"door_label": "VAULT", "needs_code": true, "required_circuit": "lab", "persist_id": "door_vault"})
	inst(inter, "res://scripts/interaction/door.gd", "CrawlGrate", Vector3(-10.0, 0, -5.5), PI / 2, {"door_label": "VENT", "key_item": "crowbar", "width": 1.3, "height": 1.6, "persist_id": "door_crawl"})

	# --- decisions
	inst(inter, "res://scripts/interaction/decision_point.gd", "VaultControl", Vector3(5.25, 1.35, -15.78), 0.0, {"decision_id": "archive", "visual": "vault_panel", "required_circuit": "lab", "persist_id": ""})
	inst(inter, "res://scripts/interaction/decision_point.gd", "PowerJunction", Vector3(-21.0, 1.3, -2.25), PI, {"decision_id": "power_route", "visual": "junction"})
	inst(inter, "res://scripts/interaction/decision_point.gd", "VargaTerminal", Vector3(5.35, 1.0, -24.9), -PI / 2, {"decision_id": "drive", "visual": "terminal", "requires_item": "research_drive", "requires_item_text": "Varga's terminal wants her drive"})
	inst(inter, "res://scripts/interaction/transmitter.gd", "Transmitter", Vector3(8.45, 0.75, -19.2), -PI / 2, {})

	# --- hiding spots
	inst(inter, "res://scripts/interaction/hiding_spot.gd", "LockerSecurityA", Vector3(7.62, 0.0, -6.55), -PI / 2, {"kind": "locker"})
	inst(inter, "res://scripts/interaction/hiding_spot.gd", "LockerSecurityB", Vector3(7.62, 0.0, -7.2), -PI / 2, {"kind": "locker"})
	inst(inter, "res://scripts/interaction/hiding_spot.gd", "LockerStorage", Vector3(-2.0, 0.0, -12.38), PI, {"kind": "locker"})
	inst(inter, "res://scripts/interaction/hiding_spot.gd", "LockerArchive", Vector3(5.62, 0.0, -13.0), -PI / 2, {"kind": "locker"})
	inst(inter, "res://scripts/interaction/hiding_spot.gd", "LockerGenerator", Vector3(-9.62, 0.0, -3.9), PI / 2, {"kind": "locker"})
	inst(inter, "res://scripts/interaction/hiding_spot.gd", "UnderCot", Vector3(-4.75, 0.0, -32.6), PI / 2, {"kind": "cot", "view_offset": Vector3(0.0, 0.22, 0.3), "exit_offset": Vector3(0.0, 0.05, 1.0), "solid": false})

	# --- hazards
	var steam := Node3D.new()
	steam.name = "SteamMain"
	steam.set_script(load("res://scripts/hazards/steam_burst.gd"))
	steam.position = Vector3(1.45, 1.6, -10.6)
	steam.rotation.y = -PI / 2
	steam.set("size", Vector3(1.5, 2.2, 3.0))
	inter.add_child(steam)
	var wire := Node3D.new()
	wire.name = "LiveWire"
	wire.set_script(load("res://scripts/hazards/live_wire.gd"))
	wire.position = Vector3(-3.2, 0.0, -16.6)
	inter.add_child(wire)
	cyl(inter, "LiveWireCable", 0.02, 2.95, Vector3(-3.25, 1.5, -16.55), "pipe", Vector3(0.05, 0, 0.08))
	var gas := Node3D.new()
	gas.name = "GasPocket"
	gas.set_script(load("res://scripts/hazards/gas_pocket.gd"))
	gas.position = Vector3(-22.6, 1.2, -6.0)
	gas.set("size", Vector3(4.6, 2.4, 6.6))
	inter.add_child(gas)

	# --- items
	pickup(inter, "keycard_red", Vector3(-5.3, 0.8, -26.25), "RedKeycard")
	pickup(inter, "crowbar", Vector3(-1.9, 0.05, -24.3), "Crowbar")
	pickup(inter, "medkit", Vector3(4.6, 0.82, -10.35), "MedkitSecurity")
	pickup(inter, "medkit", Vector3(5.3, 0.8, -27.9), "MedkitLab")
	pickup(inter, "medkit", Vector3(-19.6, 0.05, -8.2), "MedkitCamp")
	pickup(inter, "battery", Vector3(3.2, 0.82, -15.4), "BatteryArchive")


func _lift_panel_visual(lift: Node3D) -> void:
	var b := MeshInstance3D.new()
	b.name = "Mesh"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.45, 0.12)
	b.mesh = bm
	b.material_override = mats["painted_metal"]
	lift.add_child(b)
	var btn := MeshInstance3D.new()
	btn.name = "Button"
	var sm := CylinderMesh.new()
	sm.top_radius = 0.05
	sm.bottom_radius = 0.05
	sm.height = 0.03
	btn.mesh = sm
	btn.rotation.x = PI / 2
	btn.position = Vector3(0, 0.05, 0.07)
	btn.material_override = mats["lamp_red"]
	lift.add_child(btn)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.34, 0.5, 0.3)
	cs.shape = bs
	lift.add_child(cs)
	label(lift, "LIFT", Vector3(0, 0.3, 0.065), 0.0, 30)


# ----------------------------------------------------------------------------- game
func _build_game() -> void:
	var g := Node3D.new()
	g.name = "Game"
	g.set_script(load("res://scripts/world/game.gd"))
	var lvl: Node3D = load("res://scenes/levels/facility_greybox.tscn").instantiate()
	lvl.name = "Level"
	g.add_child(lvl)
	var pl: Node3D = load("res://scenes/player.tscn").instantiate()
	pl.name = "Player"
	g.add_child(pl)
	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	hud.name = "HUD"
	g.add_child(hud)
	var pause: Node = load("res://scenes/ui/pause_menu.tscn").instantiate()
	pause.name = "PauseMenu"
	g.add_child(pause)
	_own(g, g)
	var ps := PackedScene.new()
	ps.pack(g)
	ResourceSaver.save(ps, "res://scenes/game.tscn")
	g.free()
