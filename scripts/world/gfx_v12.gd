class_name GfxV12
extends RefCounted
## v1.2: the lift and shaft remodel (Blender, tools/gfx_blender/build_lift_v12.py), applied to
## the built level at load like the v1.1 pass: visual only. Every box it replaces keeps its
## collider (the guide rails), or never had one (the old cage bars, cables, counterweight);
## the lift's moving parts are parented to the "Lift" group so the cold-open still carries them.

const DIR := "res://assets/props_v12/"
const CAGE_ORIGIN := Vector3(0.0, 0.25, 6.6)    ## platform top centre
## Old v1.0 boxes the Blender cage replaces (the hazard top rail, the lamp and the signs stay).
const CAGE_OLD := ["CagePost", "CageBeamX", "CageBeamZ", "CageBarSide", "CageBarBack", "CageMidRail", "CageRoof", "GateRailLow"]
const BUNTON_Y := [3.4, 7.4, 11.4]
static var _cache := {}
static var added: Array = []   ## names of what was placed (tests)


static func enabled() -> bool:
	return GfxAssets.enabled() and not Harness.has("nogfx12")


static func mesh(n: String) -> Mesh:
	if _cache.has(n):
		return _cache[n]
	var m: Mesh = null
	var p := DIR + n + ".glb"
	if ResourceLoader.exists(p):
		var inst := (load(p) as PackedScene).instantiate()
		for c in inst.find_children("*", "MeshInstance3D", true, false):
			m = (c as MeshInstance3D).mesh
			break
		inst.free()
	_cache[n] = m
	return m


static func material(base_name: String, n: String, tint := Color.WHITE) -> Material:
	var base := ArtMats.local(base_name, tint)
	var p := DIR + n + "_bake.png"
	if not (base is BaseMaterial3D) or not ResourceLoader.exists(p):
		return base
	var m := base as BaseMaterial3D
	m.detail_enabled = true
	m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.detail_albedo = load(p)
	return m


static func place(parent: Node3D, n: String, base_name: String, xf: Transform3D, shadow := false, tint := Color.WHITE, fade := 0.0) -> MeshInstance3D:
	if n in Harness.get_arg("v12skip", "").split(","):   # perf A/B: -- --v12skip=lift_cage,winch
		return null
	var me := mesh(n)
	if me == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "v12_" + n
	mi.mesh = me
	mi.material_override = material(base_name, n, tint)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if fade > 0.0:
		mi.visibility_range_end = fade
		mi.visibility_range_end_margin = 2.0
	parent.add_child(mi)
	mi.transform = xf
	added.append(n)
	return mi


static func _multi(parent: Node3D, n: String, base_name: String, xfs: Array[Transform3D]) -> MultiMeshInstance3D:
	if n in Harness.get_arg("v12skip", "").split(","):
		return null
	var me := mesh(n)
	if me == null:
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = me
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "v12_" + n
	mmi.multimesh = mm
	mmi.material_override = material(base_name, n)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 40.0
	mmi.visibility_range_end_margin = 2.0
	parent.add_child(mmi)
	added.append(n)
	return mmi


static func _hide_box(n: Node) -> void:
	var mi := (n as Node3D).get_node_or_null("Mesh") as MeshInstance3D if n is Node3D else null
	if mi == null and n is MeshInstance3D:
		mi = n
	if mi:
		mi.visible = false


## The two guide rails are 0.18 x 16 x 0.18 boxes (the second one got an automatic name).
static func _is_rail(c: Node) -> bool:
	var mi := c.get_node_or_null("Mesh") as MeshInstance3D
	return mi != null and mi.mesh is BoxMesh and ((mi.mesh as BoxMesh).size - Vector3(0.18, 16.0, 0.18)).length() < 0.01


static func level(lvl: Node3D) -> void:
	added.clear()
	if not enabled():
		return
	var root := Node3D.new()
	root.name = "GfxV12"
	lvl.add_child(root)
	var shaft := lvl.get_node_or_null("Geometry/EntranceShaft") as Node3D
	var lift := lvl.find_child("Lift", true, false) as Node3D   # Dressing/Lift (tools/dress.gd)
	# --- the lift car (rides with the cold-open: child of the Lift group)
	if lift and mesh("lift_cage"):
		# every old cage box (posts, beams, bars, rails, roof; duplicates got automatic names),
		# except the hazard-striped top gate rail, which stays
		var hz: Material = load("res://assets/materials/hazard.tres") if ResourceLoader.exists("res://assets/materials/hazard.tres") else null
		for c in lift.get_children():
			var mi := c.get_node_or_null("Mesh") as MeshInstance3D
			if mi and mi.mesh is BoxMesh and (hz == null or mi.material_override != hz) and not String(c.name).begins_with("GateRailTop"):
				mi.visible = false
		var cage := place(lift, "lift_cage", "dark_metal", Transform3D(Basis(), CAGE_ORIGIN - lift.global_position), false, Color(1.7, 1.6, 1.45))
		if cage and not ("cage_shadow" in Harness.get_arg("v12skip", "").split(",")):
			# its shadow: one cheap slab for the solid lower panels' back wall and one for the roof
			GfxAssets.shadow_proxy(cage, cage, Vector3(3.15, 0.95, 0.05), Vector3(0.0, 0.475, 1.15))
			GfxAssets.shadow_proxy(cage, cage, Vector3(3.2, 0.12, 2.36), Vector3(0.0, 2.72, 0.0))
	if shaft == null:
		return
	# --- guide rails (keep their colliders), cables, counterweight
	for c in shaft.get_children():
		var nm := String(c.name)
		if _is_rail(c):
			_hide_box(c)
			place(shaft, "lift_rail", "dark_metal", Transform3D(Basis(), Vector3((c as Node3D).position.x, 0.0, (c as Node3D).position.z)))
		elif nm.begins_with("Cable"):
			_hide_box(c)
		elif nm == "LiftCounterweight":
			_hide_box(c)
			place(shaft, "lift_counterweight", "dark_metal", Transform3D(Basis(), (c as Node3D).position))
	var has_cables := false
	for c in shaft.get_children():
		if String(c.name).begins_with("Cable"):
			has_cables = true
	if has_cables:
		place(shaft, "lift_cables", "cable" if ResourceLoader.exists("res://assets/materials/cable.tres") else "dark_metal",
			Transform3D(Basis(), Vector3(0.0, 8.2, 7.7)), false, Color.WHITE, 30.0)
	# --- shaft steelwork: corner H-columns and ring beams (buntons) on three walls, each set one
	#     MultiMesh (one draw call per set, no shadow), so the remodel stays cheap on phones
	var cols: Array[Transform3D] = []
	for p in [Vector2(-3.74, 0.26), Vector2(3.74, 0.26), Vector2(-3.74, 7.74), Vector2(3.74, 7.74)]:
		cols.append(Transform3D(Basis(), Vector3(p.x, 0.0, p.y)))
	_multi(root, "shaft_column", "rusty", cols)
	var bunts: Array[Transform3D] = []
	for y in BUNTON_Y:
		bunts.append(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(-3.76, y, 4.0)))
		bunts.append(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(3.76, y, 4.0)))
		bunts.append(Transform3D(Basis(), Vector3(0.0, y, 7.76)))
	_multi(root, "shaft_bunton", "rusty", bunts)
	# --- the call box
	var panel := lvl.get_node_or_null("Interactables/LiftPanel") as Node3D
	if panel and mesh("lift_callbox"):
		var old := panel.get_node_or_null("Mesh") as MeshInstance3D
		if old:
			old.visible = false
		place(panel, "lift_callbox", "painted_metal", Transform3D(), false, Color(0.9, 0.75, 0.35))
	# --- the winch room's records: one baked mesh per shelf unit
	for sn in [["RecordShelfA", 1.0], ["RecordShelfB", 1.6 / 2.2]]:
		var sh := lvl.find_child(sn[0], true, false) as Node3D
		if sh and mesh("records_fill"):
			var xf := sh.global_transform
			xf.basis = xf.basis * Basis.from_scale(Vector3(sn[1], 1.0, 1.0))
			place(root, "records_fill", "wood_crate", xf, false, Color(1.05, 0.92, 0.72), 22.0)
	# --- the winch room's hoist (its collider is a plain box from the level build)
	var wm := lvl.find_child("WinchBase", true, false) as Node3D
	if wm:
		var vis := wm.get_node_or_null("Mesh") as MeshInstance3D
		if vis:
			vis.visible = false
		place(root, "winch", "green_metal", Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(wm.global_position.x, 0.0, wm.global_position.z)), false, Color(1.7, 1.65, 1.35))
		GfxAssets.shadow_proxy(root.get_child(root.get_child_count() - 1), root, Vector3(1.2, 1.3, 2.3), Vector3(wm.global_position.x, 0.65, wm.global_position.z))
