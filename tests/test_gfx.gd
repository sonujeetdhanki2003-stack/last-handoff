extends TestCase
## v1.1 graphics pass (tools/gfx_blender/): Blender-made props, the Keeper's sculpt bake and the
## baked room AO are wired in, and none of it changes a collider, size or gameplay node.

const PROPS := ["door_panel", "door_jamb", "door_header", "locker_body", "locker_door", "lamp_fixture",
	"vent_grate", "pipe_flange", "pipe_hanger"]
const TRI_BUDGET := 9000


func _has_uv2(m: Mesh) -> bool:
	if m == null or m.get_surface_count() == 0:
		return false
	var a := (m as ArrayMesh).surface_get_arrays(0) if m is ArrayMesh else []
	return a.size() > Mesh.ARRAY_TEX_UV2 and a[Mesh.ARRAY_TEX_UV2] != null and (a[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).size() > 0


func run() -> void:
	# --- every prop: a mesh with a lightmap UV2, its baked map, a sane triangle count
	for n in PROPS:
		var m := GfxAssets.mesh(n)
		t.check(m != null, "prop %s loads" % n)
		if m == null:
			continue
		t.check(_has_uv2(m), "%s has the bake UV2" % n)
		t.check(GfxAssets.bake(n) != null, "%s has its baked AO/grime map" % n)
		var tris := 0
		for s in m.get_surface_count():
			var idx: PackedInt32Array = (m as ArrayMesh).surface_get_arrays(s)[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3
		t.check(tris > 50 and tris < TRI_BUDGET, "%s is %d tris (budget %d)" % [n, tris, TRI_BUDGET])
	var dm := GfxAssets.mesh("door_panel").get_aabb()
	t.check(absf(dm.size.x - 1.6) < 0.08 and absf(dm.size.y - 2.4) < 0.06 and dm.position.y > -0.01, "door panel is authored at 1.6 x 2.4, origin on the floor")
	var lm := GfxAssets.mesh("locker_body").get_aabb()
	t.check(absf(lm.size.x - 0.62) < 0.05 and absf(lm.size.y - 1.95) < 0.03 and absf(lm.size.z - 0.57) < 0.05, "locker body is 0.62 x 1.95 x 0.55")

	# --- a door: new meshes, same collider, still opens
	var d: Door = load("res://scripts/interaction/door.gd").new()
	d.width = 1.3
	d.height = 1.6
	t.sandbox.add_child(d)
	await t.physics(2)
	var pm := d.get_node("_genPanel/Mesh") as MeshInstance3D
	t.check(not (pm.mesh is BoxMesh), "door panel uses the Blender mesh")
	t.check(pm.scale.is_equal_approx(Vector3(1.3 / 1.6, 1.6 / 2.4, 1.0)), "door panel scales to the door's size")
	var cs: CollisionShape3D = null
	for c in d.get_node("_genPanel").get_children():
		if c is CollisionShape3D:
			cs = c
	t.check(cs != null and (cs.shape as BoxShape3D).size.is_equal_approx(Vector3(1.3, 1.6, 0.14)), "door collider unchanged")
	t.check(not ((d.get_node("_genFrameL") as MeshInstance3D).mesh is BoxMesh), "door frame uses the Blender jamb")
	var dsp := d.get_node_or_null("_genPanel/_genShadowProxy") as MeshInstance3D
	t.check(pm.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and dsp != null
		and dsp.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		and (dsp.mesh as BoxMesh).size.is_equal_approx(Vector3(1.3, 1.6, 0.12)), "door shadow comes from a door-sized box (same shadow cost as v1.0)")
	d.open()
	await t.physics(90)
	t.check(d.is_open(), "the door still opens")
	d.queue_free()

	# --- a locker: new meshes, same collider
	var hs = load("res://scripts/interaction/hiding_spot.gd").new()
	hs.kind = "locker"
	t.sandbox.add_child(hs)
	await t.physics(2)
	var meshes: Array = hs.find_children("*", "MeshInstance3D", true, false)
	var names := meshes.map(func(x): return String(x.name))
	t.check("locker_body" in names and "locker_door" in names, "locker uses the Blender body and door")
	var proxies := meshes.filter(func(x): return String(x.name).begins_with("_genShadowProxy"))
	var detailed_cast := meshes.filter(func(x): return String(x.name).begins_with("locker_") and x.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	t.check(proxies.size() == 2 and detailed_cast.is_empty(), "locker shadows come from two plain boxes (body + door)")
	t.check(proxies.any(func(x): return x.get_parent() != hs), "the locker door's shadow box swings with the door")
	var lcs: CollisionShape3D = null
	for c in hs.get_children():
		if c is CollisionShape3D:
			lcs = c
	t.check(lcs != null and (lcs.shape as BoxShape3D).size.is_equal_approx(Vector3(0.62, 1.95, 0.55)), "locker collider unchanged")
	hs.queue_free()

	# --- the station
	GameState.new_expedition(5)
	var g: Node = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(g)
	await t.physics(4)
	var level: Node3D = g.level
	var gfx := level.get_node_or_null("GfxV11")
	t.check(gfx != null, "the v1.1 pass ran on the level")
	var vent := gfx.get_node_or_null("CorridorVent") as Node3D if gfx else null
	t.check(vent != null and vent.global_position.distance_to(GfxUpgrade.VENT_POS) < 0.05, "the ceiling vent sits over the Keeper's vent exit")
	var fl := gfx.get_node_or_null("PipeFlanges") as MultiMeshInstance3D if gfx else null
	t.check(fl != null and fl.multimesh.instance_count >= 9, "the long pipes got flanges (%d)" % (fl.multimesh.instance_count if fl else 0))
	var fixtures := 0
	var bare := 0
	for pl in level.find_children("*", "PoweredLight", true, false):
		if pl.get_node_or_null("Housing"):
			if pl.get_node_or_null("FixtureV11"):
				fixtures += 1
			else:
				bare += 1
	t.check(fixtures > 10 and bare == 0, "every batten lamp got the Blender fixture (%d)" % fixtures)
	var map: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/props_v11/level_ao.json"))
	var baked := 0
	var size_ok := true
	for r in map:
		var mi := level.get_node_or_null(NodePath(r["path"])) as MeshInstance3D
		if mi and not (mi.mesh is BoxMesh) and _has_uv2(mi.mesh):
			baked += 1
			var want := Vector3(r["size"][0], r["size"][1], r["size"][2])
			if not mi.mesh.get_aabb().size.is_equal_approx(want):
				size_ok = false
	t.check(map.size() > 50 and baked == map.size(), "every wall/floor/ceiling box got its baked-AO mesh (%d/%d)" % [baked, map.size()])
	t.check(size_ok, "baked boxes keep their exact sizes")
	var occ: Node = level.get_node_or_null("Occluders")
	t.check(occ != null and occ.get_child_count() > 60, "occluders still built from the walls (%d)" % (occ.get_child_count() if occ else 0))
	var fm := (level.find_child("Floor", true, false) as Node3D)
	var fmat := (fm.get_node("Mesh") as MeshInstance3D).material_override as ShaderMaterial if fm else null
	t.check(fmat != null and fmat.get_shader_parameter("baked_ao") != null and float(fmat.get_shader_parameter("baked_ao_strength")) > 0.5, "floor material samples the AO atlas")

	# --- the Keeper: sculpt bake + Blender helmet, same rig
	var p := spawn_player(Vector3(0, 0.1, 6))
	await t.physics(2)
	var k := Keeper.new()
	t.sandbox.add_child(k)
	k.setup(p, [Vector3(-10, 0, -10), Vector3(10, 0, -10)])
	k.think = false
	await t.physics(3)
	var sk := k.find_child("GeneralSkeleton", true, false) as Skeleton3D
	t.check(sk != null and sk.get_bone_count() == 65, "the Keeper keeps its 65-bone rig")
	var body := k.find_child("Body", true, false) as MeshInstance3D
	var sm := body.material_override as StandardMaterial3D if body else null
	t.check(sm != null and sm.normal_texture != null and sm.normal_texture.resource_path.ends_with("_v11.png"), "skin uses the Blender-baked normal map")
	t.check(sm != null and sm.ao_enabled and sm.ao_texture != null, "skin uses the baked AO")
	t.check(k.find_child("HelmetV11", true, false) != null, "the Keeper wears the Blender helmet")
	k.queue_free()
