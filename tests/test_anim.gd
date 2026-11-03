extends TestCase
## v1.1: the Keeper's Blender-keyframed clips (tools/keeper_anim/, assets/characters/keeper/keeper_anims.res).
##   * every clip exists, keys every core bone (no missing tracks) and maps onto the Keeper's skeleton
##   * gameplay-timed clips match the code: scream = LUNGE_TELEGRAPH, lunge = LUNGE_TIME, stagger = LUNGE_RECOVER
##   * no clip leaves the body in the sculpt's T-pose, and the standing clips keep the feet on the floor
##   * each AI state asks the AnimationTree for its clip, locomotion playback follows the real speed
##   * the live tree really plays (bones move off the rest pose), the strike one-shot fires on a hit

const CORE := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm",
	"LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftIndexProximal", "RightIndexProximal"]

var k: Keeper
var p: Player
var sk: Skeleton3D


func _arm_dev(bone: String) -> float:
	## angle (deg) between a bone's posed and rest direction, in skeleton space
	var i := sk.find_bone(bone)
	var a := sk.get_bone_global_pose(i).basis.y.normalized()
	var r := sk.get_bone_global_rest(i).basis.y.normalized()
	return rad_to_deg(a.angle_to(r))


func _foot_y(bone: String) -> float:
	return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone))).origin.y - k.global_position.y


func _pick(st: int, v: float, phase_t := 0.0) -> Array:
	k.set_state(st)
	k.state_t = phase_t
	k.velocity = Vector3(0, 0, -v)
	return k._pick_clip(v)


func run() -> void:
	make_floor(40.0)
	p = spawn_player(Vector3(0, 0.1, 6))
	await t.physics(3)
	k = Keeper.new()
	t.sandbox.add_child(k)
	k.setup(p, [Vector3(-10, 0, -10), Vector3(10, 0, -10)])
	k.think = false
	await t.physics(5)
	sk = k.find_child("GeneralSkeleton", true, false) as Skeleton3D
	t.check(sk != null and k.tree != null, "the Keeper has its skeleton and an AnimationTree")
	var ap := k._anim
	var lib: AnimationLibrary = load(Keeper.CLIP_LIBRARY)
	t.check(lib != null, "the Blender clip library loads")

	# --- every clip, every core bone
	for c in Keeper.CLIPS:
		t.check(ap.has_animation(c), "clip %s is in the library" % c)
		if not ap.has_animation(c):
			continue
		var a := ap.get_animation(c)
		var have := {}
		var unresolved := 0
		for i in a.get_track_count():
			var path := String(a.track_get_path(i))
			var bone := path.get_slice(":", 1)
			have[bone] = true
			if sk.find_bone(bone) < 0:
				unresolved += 1
		var missing := []
		for b in CORE:
			if not have.has(b):
				missing.append(b)
		t.check(missing.is_empty(), "%s keys every core bone %s" % [c, "" if missing.is_empty() else str(missing)])
		t.eq(unresolved, 0, "%s: every track maps onto the Keeper's skeleton" % c)
		t.check(a.length > 0.2, "%s has length (%.2f s)" % [c, a.length])
	for c in ["kp_idle", "kp_stalk", "kp_run", "kp_crawl", "kp_search"]:
		t.eq(ap.get_animation(c).loop_mode, Animation.LOOP_LINEAR, "%s loops" % c)
	for c in ["kp_scream", "kp_lunge", "kp_stagger", "kp_grab", "kp_vent_drop", "kp_recoil"]:
		t.eq(ap.get_animation(c).loop_mode, Animation.LOOP_NONE, "%s plays once" % c)

	# --- gameplay timing is the code's, and the clips match it exactly
	t.check(absf(ap.get_animation("kp_scream").length - Keeper.LUNGE_TELEGRAPH) < 0.002, "scream clip lasts exactly the %.1f s telegraph" % Keeper.LUNGE_TELEGRAPH)
	t.check(absf(ap.get_animation("kp_lunge").length - Keeper.LUNGE_TIME) < 0.002, "lunge clip lasts the %.1f s lunge" % Keeper.LUNGE_TIME)
	t.check(absf(ap.get_animation("kp_stagger").length - Keeper.LUNGE_RECOVER) < 0.002, "stagger clip lasts the %.1f s recovery" % Keeper.LUNGE_RECOVER)
	t.eq(Keeper.LUNGE_TELEGRAPH, 0.5, "telegraph is still 0.5 s")
	t.eq(Keeper.LUNGE_TIME, 0.3, "lunge is still 0.3 s")
	t.eq(Keeper.LUNGE_RECOVER, 1.0, "stagger is still 1.0 s")
	t.eq(Keeper.SPEED[Keeper.S.CHASE], 3.4, "chase top speed unchanged")
	t.eq(Keeper.CHASE_START_SPEED, 2.3, "chase start speed unchanged")

	# --- no T-pose: every clip, sampled at its start, middle and end, has the arms down/out of rest
	var standing := ["kp_idle", "kp_idle_head", "kp_stalk", "kp_run", "kp_scream", "kp_grab", "kp_recoil"]
	for c in Keeper.CLIPS:
		var worst := 999.0
		var low := 99.0
		var high := -99.0
		for f in [0.0, 0.5, 1.0]:
			k.pose_clip(c, ap.get_animation(c).length * f * 0.999)
			await t.physics(2)
			worst = minf(worst, maxf(_arm_dev("LeftUpperArm"), _arm_dev("RightUpperArm")))
			var fy := minf(_foot_y("LeftFoot"), _foot_y("RightFoot"))
			low = minf(low, fy)
			high = maxf(high, fy)
		t.check(worst > 25.0, "%s: no T-pose (an upper arm at least %.0f deg off the rest pose)" % [c, worst])
		if c in standing:
			t.check(low > -0.06 and low < 0.25, "%s: feet stay on the floor (lowest ankle %.2f m)" % [c, low])
	k.tree.active = true

	# --- each AI state asks for its clip; locomotion follows the real speed
	k.set_physics_process(false)
	t.eq(_pick(Keeper.S.PATROL, 1.25)[0], "kp_stalk", "patrol walking: stalk")
	t.check(absf(_pick(Keeper.S.PATROL, 1.25)[1] - 1.0) < 0.01, "stalk plays at 1.0x at its 1.25 m/s")
	t.eq(_pick(Keeper.S.PATROL, 0.0)[0], "kp_idle", "patrol standing: idle")
	t.eq(_pick(Keeper.S.INVESTIGATE, 2.0)[0], "kp_stalk", "investigate: stalk")
	t.check(absf(_pick(Keeper.S.INVESTIGATE, 2.0)[1] - 1.6) < 0.01, "stalk speeds up with the 2.0 m/s investigate pace")
	t.eq(_pick(Keeper.S.SEARCH, 1.6)[0], "kp_crawl", "search moving: crawl")
	t.check(absf(_pick(Keeper.S.SEARCH, 1.6)[1] - 1.6 / 1.2) < 0.01, "crawl playback follows its speed")
	t.eq(_pick(Keeper.S.SEARCH, 0.0)[0], "kp_search", "search standing: sniffing")
	t.eq(_pick(Keeper.S.RETREAT, 3.2)[0], "kp_crawl", "retreat: scuttles off on all fours")
	t.eq(_pick(Keeper.S.REPELLED, 0.0)[0], "kp_recoil", "repelled: recoil from the light")
	t.eq(_pick(Keeper.S.GRAB, 0.0)[0], "kp_grab", "grab: grab")
	t.eq(_pick(Keeper.S.DORMANT, 0.0)[0], "kp_search", "dormant: curled, sniffing")
	k.set_state(Keeper.S.PATROL)
	k.set_state(Keeper.S.CHASE)
	t.eq(k._pick_clip(0.0)[0], "kp_scream", "a fresh chase opens with the scream (wind-up)")
	k._windup = 0.0
	t.eq(k._pick_clip(3.0)[0], "kp_run", "chase at speed: run")
	t.check(absf(k._pick_clip(3.4)[1] - 1.0) < 0.01 and absf(k._pick_clip(2.3)[1] - 2.3 / 3.4) < 0.01, "run playback scales from the 2.3 m/s start to 3.4 m/s")
	t.eq(_pick(Keeper.S.LUNGE, 0.0, 0.1)[0], "kp_scream", "lunge telegraph: scream")
	t.eq(_pick(Keeper.S.LUNGE, 7.0, 0.6)[0], "kp_lunge", "lunge: lunge")
	t.eq(_pick(Keeper.S.LUNGE, 0.0, 1.2)[0], "kp_stagger", "after the lunge: stagger")
	k.set_physics_process(true)

	# --- the live tree plays the state's clip, cross-faded, with real bone motion
	k.global_position = Vector3(0, 0.0, -4)
	k.set_state(Keeper.S.PATROL)
	await t.physics(30)
	k.set_state(Keeper.S.REPELLED)
	await t.physics(20)
	t.eq(String(k.tree.get("parameters/state/current_state")), "kp_recoil", "the tree is on the recoil clip")
	t.check(_arm_dev("LeftUpperArm") > 25.0, "live pose is off the T-pose (%.0f deg)" % _arm_dev("LeftUpperArm"))
	# hold clips (vent drop) play out, but a chase cuts in
	k.set_state(Keeper.S.PATROL)
	k.hold_clip("kp_vent_drop", 1.2, 0.0)
	await t.physics(10)
	t.eq(k.clip, "kp_vent_drop", "the vent drop plays out while it is not hunting")
	await t.physics(70)
	t.check(k.clip != "kp_vent_drop", "and then hands back to the state's clip (%s)" % k.clip)
	# strike: the upper-body grab one-shot fires on a non-fatal hit
	p.vitals.health = 100.0
	k._catch(false)
	await t.physics(2)
	t.check(bool(k.tree.get("parameters/strike/active")), "a strike plays the grab one-shot over the legs")
	t.check(not p.dead, "and is still not fatal at full health")
	p.vitals.health = 100.0

	# --- the real lunge: scream for the whole telegraph, then the lunge clip
	k.set_state(Keeper.S.PATROL)
	k.global_position = Vector3(0, 0.1, 4.4)
	p.global_position = Vector3(0, 0.1, 6.0)
	p.velocity = Vector3.ZERO
	k.look_at_flat(p.global_position)
	k.think = true
	k.awareness = 1.0
	k.last_seen = p.global_position
	k.set_state(Keeper.S.CHASE)
	k._windup = 0.0
	var seen := {}
	var first_lunge_clip := -1.0
	var tt := 0.0
	for i in 60:
		await t.physics(1)
		tt += 1.0 / 60.0
		if k.state == Keeper.S.LUNGE:
			seen[k.lunge_phase() + ":" + k.clip] = true
			if k.clip == "kp_lunge" and first_lunge_clip < 0.0:
				first_lunge_clip = k.state_t
	t.check(seen.has("telegraph:kp_scream"), "telegraph shows the scream")
	t.check(seen.has("lunge:kp_lunge"), "the dash shows the lunge")
	t.check(first_lunge_clip >= Keeper.LUNGE_TELEGRAPH - 0.001 and first_lunge_clip < Keeper.LUNGE_TELEGRAPH + 0.04, "the lunge clip starts as the telegraph ends (%.3f s)" % first_lunge_clip)
	k.think = false
