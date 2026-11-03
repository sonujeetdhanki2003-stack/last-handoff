class_name KeeperPoser
extends SkeletonModifier3D
## Procedural layer over the Keeper's animation clips: the hunch, the craned neck
## and tilted head, twitches, the searching sniff, reaching arms for the lunge and
## the grab (fingers curl), arms thrown up against the light, the low crawl, and
## the raised hips for its longer legs. Runs after the AnimationPlayer each frame.

var hunch := 0.7
var search := 0.0
var reach := 0.0        ## arms forward (chase/lunge)
var grab := 0.0         ## fingers curl, arms in
var shield := 0.0       ## forearms over the face (repelled by light)
var crawl := 0.0        ## low prowl: torso near horizontal, arms down to the floor
var hips_lift := 0.11
var t := 0.0
var _ids := {}
var _twitch := Vector3.ZERO
var _twitch_t := 0.0
var _rng := RandomNumberGenerator.new()


func _bone(n: String) -> int:
	if not _ids.has(n):
		_ids[n] = get_skeleton().find_bone(n)
	return _ids[n]


## Rotate a bone by a rotation given in skeleton (model) space, about its own origin.
func _rot_model(n: String, q: Quaternion) -> void:
	var sk := get_skeleton()
	var i := _bone(n)
	if i < 0:
		return
	var par := sk.get_bone_parent(i)
	var pq := sk.get_bone_global_pose(par).basis.get_rotation_quaternion() if par >= 0 else Quaternion.IDENTITY
	var lq := sk.get_bone_pose_rotation(i)
	sk.set_bone_pose_rotation(i, (pq.inverse() * q * pq * lq).normalized())


## Turn a bone so its length axis points (partly, by k) along dir (skeleton space).
func _aim(n: String, dir: Vector3, k: float) -> void:
	if k <= 0.001:
		return
	var sk := get_skeleton()
	var i := _bone(n)
	if i < 0:
		return
	var cur := sk.get_bone_global_pose(i).basis.y.normalized()
	var want := dir.normalized()
	if cur.dot(want) > 0.9999:
		return
	var q := Quaternion(cur, want)
	_rot_model(n, Quaternion.IDENTITY.slerp(q, clampf(k, 0.0, 1.0)))


func _process_modification_with_delta(delta: float) -> void:
	_step(delta)


func _step(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	t += delta
	_twitch_t -= delta
	if _twitch_t <= 0.0:
		_twitch_t = _rng.randf_range(0.6, 2.4)
		_twitch = Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.4, 0.4))
	var X := Vector3.RIGHT
	var Y := Vector3.UP
	var Z := Vector3.BACK      # the model faces +Z
	# hips up for the longer legs; dropped low when crawling
	var hi := _bone("Hips")
	if hi >= 0:
		sk.set_bone_pose_position(hi, sk.get_bone_pose_position(hi) + Vector3(0, hips_lift - crawl * 0.55, 0))
	# hunch / crawl: bend the spine forward (+Z)
	var bend := hunch * 0.28 + crawl * 0.42
	_rot_model("Hips", Quaternion(X, crawl * 0.75))
	for n in ["Spine", "Chest", "UpperChest"]:
		_rot_model(n, Quaternion(X, bend))
	if crawl > 0.01:
		for s in ["Left", "Right"]:
			_rot_model(s + "UpperLeg", Quaternion(X, -crawl * 1.3))
			_rot_model(s + "LowerLeg", Quaternion(X, crawl * 1.6))
	# the neck juts forward, the head tilts back up to look, cocked to one side
	_rot_model("Neck", Quaternion(X, 0.35 * hunch + crawl * 0.2))
	var tilt := 0.32 + _twitch.z * 0.4
	var look_up := -(0.55 * hunch + 0.9 * bend + crawl * 0.7)
	var sweep := sin(t * 0.9) * 0.75 * search + _twitch.y * 0.25
	var sniff := sin(t * 11.0) * 0.06 * search
	_rot_model("Head", Quaternion(Y, sweep) * Quaternion(Z, tilt) * Quaternion(X, look_up + sniff + _twitch.x * 0.15))
	# arms: reach forward (lunge / grab), shield the face, or hang to the floor
	var fwd_dir := Vector3(0, -0.15 - crawl * 0.9, 1.0)
	for s in ["Left", "Right"]:
		var sx := 1.0 if s == "Left" else -1.0
		var sway := sin(t * 1.3 + sx) * 0.05
		_rot_model(s + "Shoulder", Quaternion(X, 0.15 * hunch + reach * 0.2))
		var r := maxf(reach, crawl * 0.9)
		if r > 0.0:
			var spread := Vector3(sx * (0.35 - grab * 0.25), 0.05 * sin(t * 6.0 + sx), 0)
			_aim(s + "UpperArm", fwd_dir + spread, r)
			_aim(s + "LowerArm", fwd_dir + spread * 0.5 + Vector3(0, 0.15 * (1.0 - crawl), 0), r)
		if shield > 0.0:
			_aim(s + "UpperArm", Vector3(sx * 0.6, 0.2, 0.8), shield)
			_aim(s + "LowerArm", Vector3(-sx * 0.8, 0.55, 0.35), shield)
		_rot_model(s + "LowerArm", Quaternion(X, sway))
		# fingers: splay when reaching, curl when grabbing
		var curl := grab * 1.1 - reach * 0.15 + 0.2 + _twitch.x * 0.1
		for f in ["Index", "Middle", "Ring", "Little"]:
			for seg in ["Proximal", "Intermediate", "Distal"]:
				var bn: String = s + f + seg
				var i := _bone(bn)
				if i >= 0:
					var lq := sk.get_bone_pose_rotation(i)
					sk.set_bone_pose_rotation(i, lq * Quaternion(Vector3.RIGHT, curl * 0.55))
