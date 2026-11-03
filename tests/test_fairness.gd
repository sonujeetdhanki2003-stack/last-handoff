extends TestCase
## Phase 6 fairness rules, each checked in an open arena against the real Keeper:
##   * it never strikes from a run: in reach it stops, rears up and screams first
##   * a player who keeps sprinting away escapes the lunge; one who stands still doesn't
##   * light in its face while it rears up repels it fast (the parry)
##   * a fresh chase starts slow and builds up
##   * a miss leaves it staggering before it comes again

var k: Keeper
var p: Player


func _reset(kpos: Vector3, ppos: Vector3) -> void:
	p.dead = false
	p.grabbed = false
	p.vitals.health = 100.0
	p.vitals.stamina = 1.0
	p.vitals.exhausted = false
	p.set_control(true)
	p.flashlight.set_on(false)
	k.set_state(Keeper.S.PATROL)
	k.awareness = 0.0
	k.repel_cooldown = 0.0
	k.global_position = kpos
	k.velocity = Vector3.ZERO
	p.global_position = ppos
	p.velocity = Vector3.ZERO
	k.look_at_flat(ppos)
	await t.physics(3)


func run() -> void:
	make_floor(80.0)
	p = spawn_player(Vector3(0, 0.1, 0))
	await t.physics(5)
	NavBaker.bake(t.sandbox)
	k = Keeper.new()
	t.sandbox.add_child(k)
	k.setup(p, [Vector3(-20, 0, -20), Vector3(20, 0, -20)])
	await t.physics(10)
	k.wake()
	var strikes := [0]
	k.caught_player.connect(func(_f): strikes[0] += 1)

	# --- in reach it telegraphs before it strikes
	await _reset(Vector3(0, 0.1, -1.6), Vector3(0, 0.1, 0))
	k.last_seen = p.global_position
	k.set_state(Keeper.S.CHASE)
	await t.physics(2)
	t.eq(k.state_name(), "lunge", "within %.1f m it goes into the lunge" % Keeper.LUNGE_RANGE)
	t.eq(k.lunge_phase(), "telegraph", "it starts by rearing up (the telegraph)")
	var first_hit := -1.0
	var tt := 0.0
	for i in 120:
		await t.physics(1)
		tt += 1.0 / 60.0
		if strikes[0] > 0:
			first_hit = tt
			break
	t.check(first_hit >= Keeper.LUNGE_TELEGRAPH - 0.05, "a player who stands still is struck, but only after the %.1f s telegraph (%.2f s)" % [Keeper.LUNGE_TELEGRAPH, first_hit])
	t.check(not p.dead, "at full health the strike is not fatal")

	# --- sprinting away during the telegraph escapes the lunge
	await t.physics(30)
	strikes[0] = 0
	await _reset(Vector3(0, 0.1, -1.7), Vector3(0, 0.1, 0))
	p.cam.set_view(0.0, -10.0)   # facing -Z... turn to run toward +Z
	p.cam.set_view(180.0, -10.0)
	k.last_seen = p.global_position
	k.set_state(Keeper.S.CHASE)
	await t.physics(1)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var saw_recover := false
	for i in 90:
		await t.physics(1)
		if k.lunge_phase() == "recover":
			saw_recover = true
	Input.action_release("move_forward")
	Input.action_release("sprint")
	t.eq(strikes[0], 0, "sprinting away when it screams: the lunge misses")
	t.check(saw_recover, "a missed lunge leaves it staggering")

	# --- the parry: torch in its face while it rears up
	strikes[0] = 0
	await _reset(Vector3(0, 0.1, -2.0), Vector3(0, 0.1, 0))
	await aim_at(p, k.global_position + Vector3.UP * 1.5)
	k.global_position = Vector3(0, 0.1, -2.0)
	k.look_at_flat(p.global_position)
	p.flashlight.set_on(true)
	k.last_seen = p.global_position
	k.beam_t = 0.0
	k.set_state(Keeper.S.CHASE)
	k._windup = 0.0
	var repelled_at := -1.0
	tt = 0.0
	for i in 60:
		_aim_now(k.global_position + Vector3.UP * 1.5)
		await t.physics(1)
		tt += 1.0 / 60.0
		if k.state == Keeper.S.REPELLED:
			repelled_at = tt
			break
	t.check(repelled_at > 0.0 and repelled_at < Keeper.LUNGE_TELEGRAPH, "light in its face during the telegraph repels it before it lunges (%.2f s)" % repelled_at)
	t.eq(strikes[0], 0, "no strike after a parry")
	p.flashlight.set_on(false)

	# --- a fresh chase builds up speed (torch on so it keeps you in sight, pointed away)
	await t.physics(90)
	await _reset(Vector3(0, 0.1, -12), Vector3(0, 0.1, 6))
	p.cam.set_view(180.0, -10.0)
	p.flashlight.set_on(true)
	k.last_seen = p.global_position
	k.set_state(Keeper.S.CHASE)
	var early := 0.0
	var late := 0.0
	for i in 60 * 4:
		await t.physics(1)
		var v := Vector2(k.velocity.x, k.velocity.z).length()
		if i > 50 and i < 70:
			early = maxf(early, v)
		if i > 205 and k.state == Keeper.S.CHASE:
			late = maxf(late, v)
	t.check(early < Keeper.SPEED[Keeper.S.CHASE] * 0.85, "the first burst is slower (%.2f m/s at ~1 s)" % early)
	t.check(late > Keeper.SPEED[Keeper.S.CHASE] * 0.9, "then it reaches full chase speed (%.2f m/s)" % late)
	t.check(Keeper.SPEED[Keeper.S.CHASE] < p.run_speed, "you can still outrun it at full speed (%.1f < %.1f)" % [Keeper.SPEED[Keeper.S.CHASE], p.run_speed])
	k.queue_free()


## Point the camera (and so the torch) straight at a world point, this frame.
func _aim_now(target: Vector3) -> void:
	var cam_pos := p.cam.camera.global_position
	var d := target - cam_pos
	p.cam.set_view(rad_to_deg(atan2(-d.x, -d.z)), rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))
