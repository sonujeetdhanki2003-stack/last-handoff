class_name KeeperBody
extends RefCounted
## The Keeper's own body, built on the explorer rig so every animation still
## drives it: the skeleton is stretched (arms x1.5, fingers x2.2, neck x2.4,
## legs x1.12), then a gaunt skinned body is generated around the bones: rope-thin
## limbs, a ribbed narrow chest, a long faceless skull with the expedition's old
## helmet fused onto it, and the rags of an orange coverall hanging off it.

const STRETCH := {
	"LeftLowerArm": 1.5, "LeftHand": 1.5, "RightLowerArm": 1.5, "RightHand": 1.5,
	"LeftUpperArm": 1.25, "RightUpperArm": 1.25,
	"Neck": 1.3, "Head": 2.4,
	"LeftLowerLeg": 1.14, "LeftFoot": 1.12, "RightLowerLeg": 1.14, "RightFoot": 1.12,
	"Spine": 1.08, "Chest": 1.1, "UpperChest": 1.1,
}
const FINGER_STRETCH := 2.3
const LEG_LIFT := 0.11       ## hips raised so the longer legs still reach the floor


## Stretch the skeleton rests. Returns the skeleton.
static func stretch(sk: Skeleton3D) -> void:
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		var k: float = STRETCH.get(n, 1.0)
		if n.contains("Intermediate") or n.contains("Distal") or n.contains("_04_leaf") or n.contains("ThumbProximal"):
			k = FINGER_STRETCH
		if k != 1.0:
			var r := sk.get_bone_rest(i)
			r.origin *= k
			sk.set_bone_rest(i, r)
			sk.set_bone_pose_position(i, r.origin)
	sk.reset_bone_poses()


# ------------------------------------------------------------------ mesh
static var _st: SurfaceTool
static var _sk: Skeleton3D
static var _bind := {}       ## bone index -> bind slot


static func _slot(bone: int) -> int:
	return _bind.get(bone, 0)


static func _g(name: String) -> Vector3:
	return _sk.get_bone_global_rest(_sk.find_bone(name)).origin


static func _vert(p: Vector3, n: Vector3, uv: Vector2, bones: Array, weights: Array) -> void:
	var b := PackedInt32Array([0, 0, 0, 0])
	var w := PackedFloat32Array([0, 0, 0, 0])
	var tot := 0.0
	for i in mini(4, bones.size()):
		b[i] = _slot(bones[i])
		w[i] = weights[i]
		tot += weights[i]
	for i in 4:
		w[i] = w[i] / maxf(tot, 0.0001)
	_st.set_normal(n)
	_st.set_uv(uv)
	_st.set_bones(b)
	_st.set_weights(w)
	_st.add_vertex(p)


## A tube from a to b. radius(t) -> Vector2(rx, rz) cross-section radii.
## Rings near the start blend toward `parent_bone` so joints bend smoothly.
static func _tube(a: Vector3, b: Vector3, bone: int, parent_bone: int, r0: Vector2, r1: Vector2, rings := 8, sides := 10, bulge := 0.0, up_hint := Vector3.FORWARD, child_bone := -1) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.001:
		return
	var y := d / L
	var x := up_hint.cross(y)
	if x.length() < 0.01:
		x = Vector3.RIGHT.cross(y)
	x = x.normalized()
	var z := y.cross(x).normalized()
	var start := _st_count
	for ri in rings + 1:
		var t := float(ri) / rings
		var r := r0.lerp(r1, t)
		var bump := 1.0 + bulge * sin(t * PI) + 0.12 * exp(-pow((t - 0.08) / 0.07, 2.0)) + 0.1 * exp(-pow((t - 0.95) / 0.06, 2.0))
		var c := a + d * t
		var bones := [bone]
		var ws := [1.0]
		if parent_bone >= 0 and t < 0.22:
			bones.append(parent_bone)
			ws = [1.0, 0.5 * (1.0 - t / 0.22)]
		elif child_bone >= 0 and t > 0.85:
			bones.append(child_bone)
			ws = [1.0, 0.45 * (t - 0.85) / 0.15]
		for si in sides:
			var ang := TAU * si / sides
			var off := x * cos(ang) * r.x * bump + z * sin(ang) * r.y * bump
			_vert(c + off, off.normalized(), Vector2(float(si) / sides, t * L * 2.0), bones, ws)
	for ri in rings:
		for si in sides:
			var i0 := start + ri * sides + si
			var i1 := start + ri * sides + (si + 1) % sides
			var i2 := i0 + sides
			var i3 := i1 + sides
			_idx.append_array([i0, i2, i1, i1, i2, i3])
	_st_count += (rings + 1) * sides
	# caps
	for end in [0, 1]:
		var cpos := a if end == 0 else b
		var ci := _st_count
		_vert(cpos + (-y if end == 0 else y) * minf(r0.x, r1.x) * 0.5, -y if end == 0 else y, Vector2(0.5, 0.5), [bone], [1.0])
		_st_count += 1
		var ring0 := start + (0 if end == 0 else rings * sides)
		for si in sides:
			var i0 := ring0 + si
			var i1 := ring0 + (si + 1) % sides
			if end == 0:
				_idx.append_array([ci, i0, i1])
			else:
				_idx.append_array([ci, i1, i0])


static var _st_count := 0
static var _idx := PackedInt32Array()


## An ellipsoid blob weighted to one bone (skull, ribcage, joints).
static func _blob(c: Vector3, r: Vector3, bone: int, rot := Basis(), rings := 10, sides := 14, squash_top := 1.0) -> void:
	var start := _st_count
	for ri in rings + 1:
		var v := float(ri) / rings
		var phi := PI * v
		for si in sides + 1:
			var th := TAU * float(si) / sides
			var n := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var k := squash_top if n.y > 0.0 else 1.0
			var p := Vector3(n.x * r.x, n.y * r.y * k, n.z * r.z)
			_vert(c + rot * p, (rot * Vector3(n.x / r.x, n.y / r.y, n.z / r.z)).normalized(), Vector2(float(si) / sides, v), [bone], [1.0])
	for ri in rings:
		for si in sides:
			var i0 := start + ri * (sides + 1) + si
			var i1 := i0 + 1
			var i2 := i0 + sides + 1
			var i3 := i2 + 1
			_idx.append_array([i0, i1, i2, i1, i3, i2])
	_st_count += (rings + 1) * (sides + 1)


## A hanging strip of rag: from p (top) down `len`, swaying cloth, weighted to bone.
static func _rag(p: Vector3, out_dir: Vector3, w: float, len: float, bone: int, bone2 := -1) -> void:
	var start := _st_count
	var segs := 5
	var side := out_dir.cross(Vector3.UP).normalized()
	for i in segs + 1:
		var t := float(i) / segs
		var c := p + Vector3.DOWN * len * t + out_dir * (0.02 + 0.05 * t * t)
		var ww := w * (1.0 - 0.55 * t)
		var bones := [bone]
		var ws := [1.0]
		if bone2 >= 0:
			bones.append(bone2)
			ws = [1.0 - 0.5 * t, 0.5 * t]
		for s in [-1.0, 1.0]:
			var jag := 0.0 if i < segs else (0.03 if s > 0 else -0.02)
			_vert(c + side * ww * 0.5 * s + Vector3.DOWN * jag, out_dir, Vector2(0.5 + 0.5 * s, t), bones, ws)
	for i in segs:
		var a := start + i * 2
		_idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	_st_count += (segs + 1) * 2


static func build(sk: Skeleton3D, skin_mat: Material, rag_mat: Material) -> Array:
	_sk = sk
	_bind.clear()
	var skin := Skin.new()
	for i in sk.get_bone_count():
		_bind[i] = skin.get_bind_count()
		skin.add_bind(i, sk.get_bone_global_rest(i).affine_inverse())
	# ---------- body
	_st = SurfaceTool.new()
	_st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_st_count = 0
	_idx = PackedInt32Array()
	var B := func(n: String) -> int: return sk.find_bone(n)
	# spine column: narrow, ribbed
	_blob(_g("Hips") + Vector3(0, -0.02, 0), Vector3(0.14, 0.09, 0.1), B.call("Hips"))   # pelvis
	_tube(_g("Hips") + Vector3(0, -0.06, 0), _g("Spine"), B.call("Hips"), -1, Vector2(0.11, 0.085), Vector2(0.095, 0.075), 4, 12)
	_tube(_g("Spine"), _g("Chest"), B.call("Spine"), B.call("Hips"), Vector2(0.09, 0.07), Vector2(0.105, 0.08), 4, 12)
	_tube(_g("Chest"), _g("UpperChest"), B.call("Chest"), B.call("Spine"), Vector2(0.125, 0.09), Vector2(0.15, 0.1), 5, 14, 0.08)
	_tube(_g("UpperChest"), _g("Neck"), B.call("UpperChest"), B.call("Chest"), Vector2(0.155, 0.1), Vector2(0.07, 0.06), 5, 14)
	for k in 4:   # ribs showing through
		var y := lerpf(_g("Chest").y, _g("Neck").y - 0.08, k / 3.5)
		_blob(Vector3(0, y, 0.035), Vector3(0.13 - k * 0.006, 0.018, 0.085), B.call("UpperChest") if k > 1 else B.call("Chest"))
	_tube(_g("Neck"), _g("Head"), B.call("Neck"), B.call("UpperChest"), Vector2(0.042, 0.046), Vector2(0.034, 0.038), 5, 10, 0.0, Vector3.FORWARD, B.call("Head"))
	# skull: long, faceless, tilted back
	var hd := _g("Head")
	_blob(hd + Vector3(0, 0.12, 0.03), Vector3(0.075, 0.17, 0.085), B.call("Head"), Basis(Vector3.RIGHT, -0.35))
	_blob(hd + Vector3(0, 0.03, 0.08), Vector3(0.05, 0.07, 0.05), B.call("Head"))   # jaw mass, no mouth
	# arms
	for s in ["Left", "Right"]:
		_tube(_g(s + "Shoulder"), _g(s + "UpperArm"), B.call(s + "Shoulder"), B.call("UpperChest"), Vector2(0.045, 0.04), Vector2(0.05, 0.045), 3, 8)
		_blob(_g(s + "UpperArm"), Vector3(0.055, 0.055, 0.055), B.call(s + "UpperArm"))
		_tube(_g(s + "UpperArm"), _g(s + "LowerArm"), B.call(s + "UpperArm"), B.call(s + "Shoulder"), Vector2(0.058, 0.054), Vector2(0.036, 0.034), 7, 9, 0.2, Vector3.FORWARD, B.call(s + "LowerArm"))
		_blob(_g(s + "LowerArm"), Vector3(0.04, 0.04, 0.04), B.call(s + "LowerArm"))
		_tube(_g(s + "LowerArm"), _g(s + "Hand"), B.call(s + "LowerArm"), B.call(s + "UpperArm"), Vector2(0.04, 0.035), Vector2(0.024, 0.02), 8, 9, 0.18, Vector3.FORWARD, B.call(s + "Hand"))
		_blob(_g(s + "Hand") + (_g(s + s.left(0) + "MiddleProximal") - _g(s + "Hand")) * 0.45, Vector3(0.05, 0.016, 0.042), B.call(s + "Hand"))
		for f in ["Index", "Middle", "Ring", "Little", "Thumb"]:
			var chain: Array = [f + "Proximal", f + "Intermediate", f + "Distal"] if f != "Thumb" else ["ThumbMetacarpal", "ThumbProximal", "ThumbDistal"]
			var leaf: String = {"Index": "index_04_leaf_", "Middle": "middle_04_leaf_", "Ring": "ring_04_leaf_", "Little": "pinky_04_leaf_", "Thumb": "thumb_04_leaf_"}[f] + ("l" if s == "Left" else "r")
			var pts: Array = [_g(s + "Hand").lerp(_g(s + chain[0]), 0.6)]
			for c in chain:
				pts.append(_g(s + c))
			pts.append(_g(leaf))
			var bones: Array = [B.call(s + "Hand")]
			for c in chain:
				bones.append(B.call(s + c))
			for j in range(1, pts.size() - 1):
				var r0 := 0.0115 - j * 0.0018
				_tube(pts[j], pts[j + 1], bones[j], bones[j - 1], Vector2(r0, r0), Vector2(r0 * 0.8, r0 * 0.8), 3, 6)
	# legs
	for s in ["Left", "Right"]:
		_tube(_g(s + "UpperLeg"), _g(s + "LowerLeg"), B.call(s + "UpperLeg"), B.call("Hips"), Vector2(0.1, 0.095), Vector2(0.058, 0.056), 7, 10, 0.14, Vector3.FORWARD, B.call(s + "LowerLeg"))
		_blob(_g(s + "LowerLeg"), Vector3(0.05, 0.055, 0.05), B.call(s + "LowerLeg"))
		_tube(_g(s + "LowerLeg"), _g(s + "Foot"), B.call(s + "LowerLeg"), B.call(s + "UpperLeg"), Vector2(0.058, 0.056), Vector2(0.036, 0.036), 7, 10, 0.2, Vector3.FORWARD, B.call(s + "Foot"))
		_tube(_g(s + "Foot"), _g(s + "Toes"), B.call(s + "Foot"), B.call(s + "LowerLeg"), Vector2(0.032, 0.026), Vector2(0.03, 0.016), 3, 8, 0.0, Vector3.UP)
		_tube(_g(s + "Toes"), _g("ball_leaf_" + ("l" if s == "Left" else "r")), B.call(s + "Toes"), B.call(s + "Foot"), Vector2(0.03, 0.014), Vector2(0.014, 0.008), 3, 8, 0.0, Vector3.UP)
	for i in _idx:
		_st.add_index(i)
	_st.generate_tangents()
	var body := _st.commit()
	body.surface_set_material(0, skin_mat)
	# ---------- rags: the coverall it was wearing, in strips
	_st = SurfaceTool.new()
	_st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_st_count = 0
	_idx = PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var ucy := _g("UpperChest").y + 0.12
	for k in 16:
		var a := TAU * k / 16.0 + rng.randf_range(-0.12, 0.12)
		var out := Vector3(sin(a), 0, cos(a))
		var top := Vector3(out.x * 0.15, ucy + rng.randf_range(-0.03, 0.03), out.z * 0.11)
		_rag(top, out, rng.randf_range(0.06, 0.1), rng.randf_range(0.35, 0.7), B.call("UpperChest"), B.call("Chest"))
	for s in ["Left", "Right"]:
		var ua := _g(s + "UpperArm")
		var la := _g(s + "LowerArm")
		for k in 3:
			var p := ua.lerp(la, 0.2 + k * 0.25) + Vector3(0, 0.035, 0)
			_rag(p, Vector3(0, 0, -1 if k % 2 == 0 else 1), 0.05, rng.randf_range(0.12, 0.22), B.call(s + "UpperArm"))
	var hy := _g("Hips").y
	for k in 10:
		var a := TAU * k / 10.0
		var out := Vector3(sin(a), 0, cos(a))
		_rag(Vector3(out.x * 0.12, hy + 0.02, out.z * 0.09), out, rng.randf_range(0.07, 0.11), rng.randf_range(0.2, 0.42), B.call("Hips"))
	for i in _idx:
		_st.add_index(i)
	var rags := _st.commit()
	rags.surface_set_material(0, rag_mat)
	_sk = null
	return [body, rags, skin]
