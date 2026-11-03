class_name Quality
extends RefCounted
## Phase 6: the graphics presets in one table, so Low / Medium / High / Phone really
## scale every cost the station has: shadow maps, soft-shadow filtering, MSAA, the
## screen-space and volumetric effects, how far small props and lights are drawn,
## shadow fade distance, mesh LOD aggressiveness and the occlusion culling budget.
## Applied by Settings (viewport + RenderingServer), WorldEnv (environment) and
## Level (per-node draw distances).

const LOW := 0
const MEDIUM := 1
const HIGH := 2
const PHONE := 3

const P := {
	LOW: {
		"msaa": Viewport.MSAA_DISABLED, "fxaa": true, "dir_atlas": 1024, "pos_atlas": 1024,
		"soft_filter": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, "ssao": false, "ssil": false,
		"vol_fog": false, "glow": true, "small_prop_range": 14.0, "mid_prop_range": 26.0,
		"light_range": 16.0, "shadow_range": 9.0, "lod_threshold": 4.0, "max_shadow_lights": 6,
		"ambient_mult": 1.3, "exposure": 1.1,
	},
	MEDIUM: {
		"msaa": Viewport.MSAA_DISABLED, "fxaa": true, "dir_atlas": 2048, "pos_atlas": 2048,
		"soft_filter": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "ssao": true, "ssil": false,
		"vol_fog": false, "glow": true, "small_prop_range": 20.0, "mid_prop_range": 36.0,
		"light_range": 24.0, "shadow_range": 14.0, "lod_threshold": 2.0, "max_shadow_lights": 10,
	},
	HIGH: {
		"msaa": Viewport.MSAA_2X, "fxaa": true, "dir_atlas": 4096, "pos_atlas": 4096,
		"soft_filter": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, "ssao": true, "ssil": true,
		"vol_fog": true, "glow": true, "small_prop_range": 34.0, "mid_prop_range": 0.0,
		"light_range": 40.0, "shadow_range": 24.0, "lod_threshold": 1.0, "max_shadow_lights": 99,
	},
	# Phone: no SSAO / SSIL / volumetric fog, small shadow maps, short draw distances,
	# shadows only from the torch and the nearest few lamps. Auto-picked on Android.
	PHONE: {
		"msaa": Viewport.MSAA_DISABLED, "fxaa": false, "dir_atlas": 1024, "pos_atlas": 1024,
		"soft_filter": RenderingServer.SHADOW_QUALITY_HARD, "ssao": false, "ssil": false,
		"vol_fog": false, "glow": false, "small_prop_range": 12.0, "mid_prop_range": 22.0,
		"light_range": 18.0, "shadow_range": 7.0, "lod_threshold": 6.0, "max_shadow_lights": 3,
		"ambient_mult": 1.8, "exposure": 1.25,
	},
}


static func is_phone_platform() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile")


static func get_preset(q: int) -> Dictionary:
	return P.get(clampi(q, 0, 3), P[MEDIUM])


## Viewport + global renderer state.
static func apply_viewport(vp: Viewport, q: int) -> void:
	if vp == null:
		return
	var p := get_preset(q)
	vp.msaa_3d = p.msaa
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if p.fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.positional_shadow_atlas_size = p.pos_atlas
	vp.mesh_lod_threshold = p.lod_threshold
	RenderingServer.directional_shadow_atlas_set_size(p.dir_atlas, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(p.soft_filter)
	RenderingServer.positional_soft_shadow_filter_set_quality(p.soft_filter)


static func apply_environment(env: Environment, q: int) -> void:
	var p := get_preset(q)
	var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	env.ssao_enabled = p.ssao and not compat
	env.ssil_enabled = p.ssil and not compat
	env.volumetric_fog_enabled = p.vol_fog and not compat
	env.glow_enabled = p.glow
	# Without volumetric fog (Low / Phone / GLES3) there is no ambient light injected into the
	# murk, and phone screens are dimmer than monitors: the v1.0 Phone preset rendered ~85 %
	# of the screen near black. Same depth fog as High, and lift ambient + exposure instead.
	env.fog_density = 0.035 if env.volumetric_fog_enabled else 0.038
	if not env.has_meta("base_ambient"):
		env.set_meta("base_ambient", env.ambient_light_energy)
		env.set_meta("base_exposure", env.tonemap_exposure)
	env.ambient_light_energy = float(env.get_meta("base_ambient")) * float(p.get("ambient_mult", 1.0))
	env.tonemap_exposure = float(env.get_meta("base_exposure")) * float(p.get("exposure", 1.0))


## Per-node draw distances for a level. Walls, floors and anything big always draw;
## small props fade out past the preset range (with hysteresis so nothing flickers),
## medium props past a longer one, lamps fade out and drop their shadows early.
## The level is static, so the classification is done once and cached in metadata.
static func apply_level(level: Node, q: int, viewer: Node3D = null) -> void:
	var p := get_preset(q)
	var shadow_lights: Array = []
	for n in _walk(level):
		if n is Light3D:
			var l := n as Light3D
			if not l.has_meta("q_shadow"):
				l.set_meta("q_shadow", l.shadow_enabled)
			if l is OmniLight3D or l is SpotLight3D:
				if l.is_in_group("no_fade") or l.get_parent() is Camera3D:
					continue
				l.distance_fade_enabled = true
				l.distance_fade_begin = p.light_range
				l.distance_fade_length = 4.0
				l.distance_fade_shadow = p.shadow_range
				if l.get_meta("q_shadow"):
					shadow_lights.append(l)
		elif n is GeometryInstance3D and not (n is GPUParticles3D or n is CPUParticles3D):
			var g := n as GeometryInstance3D
			if g.is_in_group("always_draw"):
				continue
			if not g.has_meta("q_size"):
				var ab := g.global_transform * g.get_aabb()
				g.set_meta("q_size", ab.size[ab.get_longest_axis_index()])
			var size: float = g.get_meta("q_size")
			var r := 0.0
			if size < 1.2:
				r = p.small_prop_range
			elif size < 3.0:
				r = p.mid_prop_range
			g.visibility_range_end = r
			g.visibility_range_end_margin = 2.0 if r > 0.0 else 0.0
			g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	# shadow budget: lamps sorted by how many rooms they serve (brightest + widest
	# first) keep their shadows; the rest light without casting
	shadow_lights.sort_custom(func(a, b): return _light_weight(a) > _light_weight(b))
	for i in shadow_lights.size():
		(shadow_lights[i] as Light3D).shadow_enabled = i < p.max_shadow_lights


static func _light_weight(l: Light3D) -> float:
	var r := 0.0
	if l is OmniLight3D:
		r = (l as OmniLight3D).omni_range
	elif l is SpotLight3D:
		r = (l as SpotLight3D).spot_range
	return l.light_energy * r


## The level's static nodes (characters, the Keeper and anything they carry are skipped:
## they always draw, and the torch keeps its shadow).
static func _walk(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is CharacterBody3D or c.is_in_group("always_draw"):
			continue
		out.append(c)
		out.append_array(_walk(c))
	return out


## Occluders for the static walls and floors, made once from their box colliders, so
## the renderer skips everything behind the station's walls (an indoor map with ~1100
## mesh instances draws a fraction of them from any one spot).
static func build_occluders(level: Node3D) -> int:
	if level.get_node_or_null("Occluders"):
		return 0
	var root := Node3D.new()
	root.name = "Occluders"
	level.add_child(root)
	var count := 0
	for n in _walk(level):
		if not (n is CollisionShape3D):
			continue
		var cs := n as CollisionShape3D
		var body := cs.get_parent()
		if not (body is StaticBody3D) or cs.disabled or not (cs.shape is BoxShape3D):
			continue
		# doors and anything that moves are AnimatableBody3D / have scripts: skip
		if body.get_script() != null or body is AnimatableBody3D:
			continue
		# only colliders that are also a visible, opaque box (a wall or slab the
		# player sees), never invisible blockers or glass
		var mi := body.get_node_or_null("Mesh") as MeshInstance3D
		if mi == null or not (mi.mesh is BoxMesh) or not mi.visible:
			continue
		var mat := mi.material_override as BaseMaterial3D
		if mat and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var s: Vector3 = (cs.shape as BoxShape3D).size
		if not ((mi.mesh as BoxMesh).size).is_equal_approx(s):
			continue
		var sorted := [s.x, s.y, s.z]
		sorted.sort()
		# a wall or slab: two big sides (>= 1.5 m) and solid enough to be opaque
		if sorted[1] < 1.5 or sorted[2] < 2.0:
			continue
		var oi := OccluderInstance3D.new()
		var bo := BoxOccluder3D.new()
		# a hair smaller than the collider so it never pokes through the visible mesh
		bo.size = Vector3(maxf(s.x - 0.04, 0.02), maxf(s.y - 0.04, 0.02), maxf(s.z - 0.04, 0.02))
		oi.occluder = bo
		root.add_child(oi)
		oi.global_transform = cs.global_transform
		count += 1
	return count
