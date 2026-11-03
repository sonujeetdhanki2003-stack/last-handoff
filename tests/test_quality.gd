extends TestCase
## Phase 6 graphics presets really scale: each step up costs more in every knob, the
## level gets occluders for its walls, small props and lamps get draw distances per
## preset, and the shadow budget follows the preset.

func run() -> void:
	var L := Quality.get_preset(Quality.LOW)
	var M := Quality.get_preset(Quality.MEDIUM)
	var H := Quality.get_preset(Quality.HIGH)
	t.check(L.pos_atlas < M.pos_atlas and M.pos_atlas < H.pos_atlas, "shadow maps grow Low < Medium < High")
	t.check(L.small_prop_range < M.small_prop_range and M.small_prop_range < H.small_prop_range, "prop draw distance grows")
	t.check(L.light_range < M.light_range and M.light_range < H.light_range, "lamp draw distance grows")
	t.check(L.lod_threshold > M.lod_threshold and M.lod_threshold > H.lod_threshold, "mesh LOD gets less aggressive")
	t.check(L.max_shadow_lights < M.max_shadow_lights and M.max_shadow_lights < H.max_shadow_lights, "more lamps cast shadows")
	t.check(not L.ssao and M.ssao and H.ssao and H.ssil and H.vol_fog and not M.vol_fog, "effects: Low none, Medium SSAO, High SSAO + SSIL + volumetric fog")
	t.check(H.msaa > M.msaa, "High adds MSAA")
	t.check(bool(ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling")), "occlusion culling is on")

	GameState.new_expedition(5)
	var g: Node = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(g)
	await t.physics(4)
	var level: Node = g.level
	var occ: Node = level.get_node_or_null("Occluders")
	t.check(occ != null and occ.get_child_count() > 60, "the station's walls and slabs got occluders (%d)" % (occ.get_child_count() if occ else 0))
	var small: GeometryInstance3D = null
	var big: GeometryInstance3D = null
	for n in level.find_children("*", "GeometryInstance3D", true, false):
		if n.has_meta("q_size"):
			if small == null and float(n.get_meta("q_size")) < 0.6:
				small = n
			if big == null and float(n.get_meta("q_size")) > 6.0:
				big = n
	t.check(small != null and big != null, "props and walls were classified")
	var lamp: OmniLight3D = null
	for n in level.find_children("*", "OmniLight3D", true, false):
		if n.distance_fade_enabled:
			lamp = n
			break
	for q in [Quality.LOW, Quality.MEDIUM, Quality.HIGH]:
		Settings.set_value("video", "quality", q, false)
		await t.physics(1)
		var P := Quality.get_preset(q)
		t.near(small.visibility_range_end, P.small_prop_range, 0.01, "%s: a small prop draws to %.0f m" % [Settings.QUALITY_NAMES[q], P.small_prop_range])
		t.eq(big.visibility_range_end, 0.0, "%s: walls always draw" % Settings.QUALITY_NAMES[q])
		t.near(lamp.distance_fade_begin, P.light_range, 0.01, "%s: lamps fade from %.0f m" % [Settings.QUALITY_NAMES[q], P.light_range])
		var shadowed := level.find_children("*", "Light3D", true, false).filter(func(l): return l.shadow_enabled and not (l.get_parent() is Camera3D)).size()
		var could := level.find_children("*", "Light3D", true, false).filter(func(l): return l.has_meta("q_shadow") and l.get_meta("q_shadow")).size()
		t.eq(shadowed, mini(could, P.max_shadow_lights), "%s: %d lamps cast shadows" % [Settings.QUALITY_NAMES[q], mini(could, P.max_shadow_lights)])
		t.near(g.get_viewport().mesh_lod_threshold, P.lod_threshold, 0.01, "%s: mesh LOD threshold %.0f" % [Settings.QUALITY_NAMES[q], P.lod_threshold])
	t.check(not is_instance_valid(g.player) or g.player.find_children("*", "GeometryInstance3D", true, false).all(func(m): return m.visibility_range_end == 0.0), "the player is never range-culled")
	Settings.set_value("video", "quality", 2, false)
	g.queue_free()
	await t.physics(3)
