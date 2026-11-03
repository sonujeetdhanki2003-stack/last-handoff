class_name GfxAssets
extends RefCounted
## v1.1 graphics pass: meshes modelled + baked in Blender (tools/gfx_blender/build_props.py).
## Each prop ships as assets/props_v11/<name>.glb with <name>_bake.png, a baked
## ambient-occlusion x grime multiplier on the mesh's second UV set. `material()` layers that
## map over the game's existing triplanar material as a multiply detail on UV2, so the
## colour, wear and metal still come from the same textures and the bake adds the contact
## shadows, cavity dirt and drips. Missing files fall back to null (callers keep their boxes).

const DIR := "res://assets/props_v11/"
static var _meshes := {}
static var _bakes := {}


## `-- --nogfx11` (Harness) turns the whole v1.1 graphics pass off, for before/after captures.
static func enabled() -> bool:
	return not Harness.has("nogfx11")


static func mesh(n: String) -> Mesh:
	if not enabled():
		return null
	if _meshes.has(n):
		return _meshes[n]
	var m: Mesh = null
	var p := n if n.begins_with("res://") else DIR + n + ".glb"
	if ResourceLoader.exists(p):
		var ps := load(p) as PackedScene
		if ps:
			var inst := ps.instantiate()
			for c in inst.find_children("*", "MeshInstance3D", true, false):
				m = (c as MeshInstance3D).mesh
				break
			inst.free()
	_meshes[n] = m
	return m


static func bake(n: String) -> Texture2D:
	if not _bakes.has(n):
		var p := DIR + n + "_bake.png"
		_bakes[n] = load(p) if ResourceLoader.exists(p) else null
	return _bakes[n]


## `base` (usually an ArtMats.local / scene material) + the prop's baked multiply map on UV2.
static func material(base: Material, n: String) -> Material:
	var t := bake(n)
	if base == null or t == null or not (base is BaseMaterial3D):
		return base
	var m := (base as BaseMaterial3D).duplicate() as BaseMaterial3D
	m.detail_enabled = true
	m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.detail_albedo = t
	m.detail_mask = null
	return m


## A MeshInstance3D of a v1.1 prop; null when the asset is missing (the caller keeps its box).
static func instance(n: String, base: Material) -> MeshInstance3D:
	var me := mesh(n)
	if me == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = me
	mi.material_override = material(base, n)
	return mi


## Shadows stay as cheap as v1.0's: the detailed mesh is drawn but casts no shadow, and an
## invisible box of the old size casts it instead (omni lamps render each caster six times).
static func shadow_proxy(detailed: GeometryInstance3D, parent: Node3D, size: Vector3, pos: Vector3) -> MeshInstance3D:
	detailed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mi := MeshInstance3D.new()
	mi.name = "_genShadowProxy"
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	parent.add_child(mi)
	return mi
