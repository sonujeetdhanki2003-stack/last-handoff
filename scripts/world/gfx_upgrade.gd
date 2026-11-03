class_name GfxUpgrade
extends RefCounted
## v1.1 graphics pass, applied to the built level at load (visual only: no collider, node
## name, size or position that gameplay reads is changed). Blender-made meshes come from
## GfxAssets (tools/gfx_blender/). Anything missing is skipped, so the level still works.

const VENT_POS := Vector3(0.0, 3.2, -19.6)   ## the corridor ceiling vent the Keeper drops from


static func level(lvl: Node3D) -> void:
	var root := Node3D.new()
	root.name = "GfxV11"
	lvl.add_child(root)
	_pipes(lvl, root)
	_vent(lvl, root)
	_leaks(root)
	if not Harness.has("noao"):
		_room_ao(lvl)


## Baked room AO (tools/gfx_blender/export_level.gd -> bake_level_ao.py): every wall, floor and
## ceiling box gets the same box mesh with a lightmap UV2; the shared surface materials sample
## the atlas there. Same size, so the occluders, colliders and triplanar textures are unchanged.
## (Per surface type: how strong the darkening is, and v1.1's extra wetness.)
const AO_STRENGTH := 1.0
const WET := {"concrete_floor": [0.75, 0.0], "storage_floor": [0.5, 0.0], "metal_floor": [0.5, 0.0], "lab_floor": [0.7, 0.0],
	"office_floor": [0.35, 0.0], "concrete_wall": [-1.0, 0.55], "shaft_wall": [-1.0, 0.7], "painted_metal": [-1.0, 0.45],
	"lab_tiles": [-1.0, 0.4], "office_wall": [-1.0, 0.25]}
static func _room_ao(lvl: Node3D) -> void:
	var p := "res://assets/props_v11/level_ao.glb"
	if not GfxAssets.enabled() or not ResourceLoader.exists(p) or not ResourceLoader.exists("res://assets/props_v11/level_ao.json"):
		return
	var tex: Texture2D = load("res://assets/props_v11/level_ao.png")
	var map: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/props_v11/level_ao.json"))
	var inst := (load(p) as PackedScene).instantiate()
	var meshes := {}
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		meshes[String(c.name)] = (c as MeshInstance3D).mesh
	inst.free()
	var done := {}
	for i in map.size():
		var mi := lvl.get_node_or_null(NodePath(map[i]["path"])) as MeshInstance3D
		var m: Mesh = meshes.get("R%d" % i)
		if mi == null or m == null or not (mi.mesh is BoxMesh):
			continue
		if not ((mi.mesh as BoxMesh).size).is_equal_approx(Vector3(map[i]["size"][0], map[i]["size"][1], map[i]["size"][2])):
			continue
		mi.mesh = m
		var sm := mi.material_override as ShaderMaterial
		if sm and not done.has(sm):
			done[sm] = true
			sm.set_shader_parameter("baked_ao", tex)
			var k := sm.resource_path.get_file().get_basename()
			# ceilings sit right over the pipes, ribs and cable trays: a lighter touch there
			sm.set_shader_parameter("baked_ao_strength", AO_STRENGTH * (0.45 if k.contains("ceiling") else 1.0))
			if WET.has(k):
				if WET[k][0] >= 0.0:
					sm.set_shader_parameter("wet", WET[k][0])
				sm.set_shader_parameter("wall_wet", WET[k][1])


## Flanged joints every ~2.6 m and ceiling hangers on the long service pipes.
static func _pipes(lvl: Node3D, root: Node3D) -> void:
	var fl := GfxAssets.mesh("pipe_flange")
	var hg := GfxAssets.mesh("pipe_hanger")
	if fl == null or hg == null:
		return
	var base: Material = load("res://assets/materials/pipe.tres") if ResourceLoader.exists("res://assets/materials/pipe.tres") else null
	var dark: Material = load("res://assets/materials/dark_metal.tres") if ResourceLoader.exists("res://assets/materials/dark_metal.tres") else null
	var fl_mat := GfxAssets.material(base, "pipe_flange")
	var hg_mat := GfxAssets.material(dark, "pipe_hanger")
	var xf_f: Array[Transform3D] = []
	var xf_h: Array[Transform3D] = []
	for n in lvl.find_children("*", "Node3D", true, false):
		var nm := String(n.name)
		if not (nm.begins_with("Pipe") or nm == "Exhaust"):
			continue
		var mi := (n as Node3D).get_node_or_null("Mesh") as MeshInstance3D
		if mi == null or not (mi.mesh is CylinderMesh):
			continue
		var cm := mi.mesh as CylinderMesh
		if cm.height < 2.0 or cm.top_radius < 0.05:
			continue
		var gx := (n as Node3D).global_transform
		var axis := gx.basis.y.normalized()
		var r := cm.top_radius
		var count := int(floor(cm.height / 2.6))
		for i in count + 1:
			var along := -cm.height * 0.5 + 0.35 + i * (cm.height - 0.7) / maxf(count, 1)
			var p := gx.origin + axis * along
			# flange: unit-radius ring, axis along local Y -> along the pipe
			var b := Basis(gx.basis.x.normalized(), axis, gx.basis.z.normalized()).scaled(Vector3(r, r, r))
			xf_f.append(Transform3D(b, p))
			# hanger: halfway between flanges, clamp around the pipe, rod straight up
			if i < count and absf(axis.y) < 0.3:
				var ph := p + axis * (cm.height - 0.7) / maxf(count, 1) * 0.5
				var side := axis.cross(Vector3.UP).normalized()
				var hb := Basis(side, Vector3.UP, axis).scaled(Vector3(r, r, r) * 0.95)
				xf_h.append(Transform3D(hb, ph))
	_multi(root, "PipeFlanges", fl, fl_mat, xf_f)
	_multi(root, "PipeHangers", hg, hg_mat, xf_h)


static func _multi(root: Node3D, n: String, mesh: Mesh, mat: Material, xfs: Array[Transform3D]) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 26.0
	mmi.visibility_range_end_margin = 2.0
	root.add_child(mmi)


## The ceiling vent the Keeper pours out of: a louvred grate with a bent, forced-open blade.
static func _vent(lvl: Node3D, root: Node3D) -> void:
	var base: Material = load("res://assets/materials/grate.tres") if ResourceLoader.exists("res://assets/materials/grate.tres") else null
	var mi := GfxAssets.instance("vent_grate", base)
	if mi == null:
		return
	mi.name = "CorridorVent"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = VENT_POS - Vector3(0, 0.002, 0)
	root.add_child(mi)
	# the ceiling rib that sat over the vent moves one bay back (purely visual)
	for n in lvl.find_children("Rib*", "Node3D", true, false):
		var r := n as Node3D
		if absf(r.global_position.z - (-19.5)) < 0.05 and absf(r.global_position.x) < 0.1:
			r.global_position.z = -18.5


## Grime and leaks where the new geometry says water would go: the vent drips onto a puddle
## below it (a fair tell for where the Keeper comes down), rust runs from the pipe joints
## down the corridor walls, and oily streaks sit under the lockers.
const DEC := "res://assets/decals/%s.png"
static func _leaks(root: Node3D) -> void:
	_dfloor(root, "puddle", Vector3(0.1, 0.0, -19.7), 1.6, 1.3, 0.4, Color(0.75, 0.78, 0.8))
	_dfloor(root, "puddle", Vector3(-0.6, 0.0, -11.5), 1.1, 2.2, 1.2, Color(0.75, 0.78, 0.8))
	_dceil(root, "rust_drip", VENT_POS + Vector3(0.0, -0.01, 0.0), 1.2, 1.2)
	for z in [-3.1, -8.3, -13.5, -16.1, -20.9]:
		_dwall(root, "leak_streak", Vector3(1.6 - 0.15, 2.0, z), Vector3(-1, 0, 0), 0.6, 2.0)
	_dfloor(root, "grime", Vector3(7.05, 0.0, -6.9), 1.2, 1.9, 0.0, Color(0.8, 0.75, 0.7))


static func _decal(tex: String, mod: Color) -> Decal:
	var d := Decal.new()
	d.texture_albedo = load(DEC % tex)
	d.modulate = mod
	d.upper_fade = 0.05
	d.lower_fade = 0.05
	d.normal_fade = 0.35
	d.cull_mask = 0xFFFFF & ~2
	d.distance_fade_enabled = true
	d.distance_fade_begin = 20.0
	d.distance_fade_length = 5.0
	return d


static func _dfloor(root: Node3D, tex: String, c: Vector3, w: float, l: float, yaw: float, mod := Color.WHITE) -> void:
	if not ResourceLoader.exists(DEC % tex):
		return
	var d := _decal(tex, mod)
	d.name = "V11_" + tex
	d.size = Vector3(w, 0.4, l)
	d.position = c
	d.rotation.y = yaw
	var orm := "res://assets/decals/puddle_orm.png"
	if tex == "puddle" and ResourceLoader.exists(orm):
		d.texture_orm = load(orm)
	root.add_child(d)


static func _dceil(root: Node3D, tex: String, c: Vector3, w: float, l: float) -> void:
	if not ResourceLoader.exists(DEC % tex):
		return
	var d := _decal(tex, Color(0.8, 0.75, 0.7))
	d.name = "V11_" + tex
	d.size = Vector3(w, 0.3, l)
	d.transform = Transform3D(Basis(Vector3.RIGHT, PI), c)
	root.add_child(d)


static func _dwall(root: Node3D, tex: String, c: Vector3, n: Vector3, w: float, h: float) -> void:
	if not ResourceLoader.exists(DEC % tex):
		return
	var d := _decal(tex, Color(0.9, 0.85, 0.8))
	d.name = "V11_" + tex
	d.size = Vector3(w, 0.3, h)
	var y := n.normalized()
	var z := Vector3.DOWN
	d.transform = Transform3D(Basis(y.cross(z), y, z), c)
	root.add_child(d)


## Replace a powered light's primitive batten (box housing + rods) with the Blender fixture.
static func fixture(pl: Node3D) -> void:
	var hous := pl.get_node_or_null("Housing") as MeshInstance3D
	if hous == null or not (hous.mesh is BoxMesh) or pl.get_node_or_null("FixtureV11"):
		return
	var base: Material = hous.material_override
	var mi := GfxAssets.instance("lamp_fixture", base)
	if mi == null:
		return
	mi.name = "FixtureV11"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pl.add_child(mi)
	hous.visible = false
	for c in pl.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is CylinderMesh:
			var cm := (c as MeshInstance3D).mesh as CylinderMesh
			if is_equal_approx(cm.height, 0.3):   # the old hanger rods
				(c as MeshInstance3D).visible = false
