extends TestCase
## The Keeper's state machine, unit by unit, in a small test arena with a baked navmesh.

var k: Keeper
var p: Player


func _arena() -> void:
	make_floor(60.0)
	# a wall to hide behind and a door between two halves
	make_wall(Vector3(6, 1.5, 0), Vector3(0.3, 3.0, 6.0))


func _reset(keeper_pos: Vector3, player_pos: Vector3, keeper_face: Vector3) -> void:
	k.set_state(Keeper.S.PATROL)
	k.awareness = 0.0
	k.seen_hiding = null
	k.global_position = keeper_pos
	k.velocity = Vector3.ZERO
	k.look_at_flat(keeper_face)
	p.global_position = player_pos
	p.velocity = Vector3.ZERO
	p.cam.global_position = player_pos + Vector3.UP * 1.55
	await t.physics(3)


func run() -> void:
	_arena()
	p = spawn_player(Vector3(0, 0.1, 8))
	await t.physics(5)
	NavBaker.bake(t.sandbox)
	k = Keeper.new()
	t.sandbox.add_child(k)
	k.global_position = Vector3(0, 0.1, -8)
	k.setup(p, [Vector3(-10, 0, -10), Vector3(10, 0, -10), Vector3(-10, 0, 10), Vector3(10, 0, 12)])
	await t.physics(10)

	# --- waking
	t.eq(k.state_name(), "dormant", "starts dormant")
	Events.noise.emit(p.global_position, 4.5, "step")
	await t.physics(2)
	t.eq(k.state_name(), "dormant", "a footstep doesn't wake it")
	GameState.grid.set_on("aux", true)
	t.eq(k.state_name(), "dormant", "power on: not instantly")
	for i in 420:
		await t.physics(1)
		if k.state != Keeper.S.DORMANT:
			break
	t.check(k.state != Keeper.S.DORMANT, "the power coming on wakes it a few seconds later (it hears the power)")

	# --- hearing
	p.flashlight.set_on(false)
	await _reset(Vector3(0, 0.1, -8), Vector3(-20, 0.1, 20), Vector3(0, 0, -20))
	Events.noise.emit(Vector3(2, 0, -5), 4.5, "step")
	await t.physics(2)
	t.eq(k.state_name(), "investigate", "walking within 4.5 m: it comes to look")
	t.check(k.agent.target_position.distance_to(Vector3(2, 0, -5)) < 0.5, "it heads to the noise")
	await _reset(Vector3(0, 0.1, -8), Vector3(-20, 0.1, 20), Vector3(0, 0, -20))
	Events.noise.emit(Vector3(0, 0, 4), 4.5, "step")
	await t.physics(2)
	t.eq(k.state_name(), "patrol", "a walk 12 m away isn't heard")
	Events.noise.emit(Vector3(0, 0, 4), 13.0, "run")
	await t.physics(2)
	t.eq(k.state_name(), "investigate", "running 12 m away is heard")

	# --- moving on the navmesh
	var d0 := k.global_position.distance_to(Vector3(0, 0, 4))
	await t.physics(90)
	t.check(k.global_position.distance_to(Vector3(0, 0, 4)) < d0 - 1.5, "it walks the navmesh toward the noise")

	# --- sight
	await _reset(Vector3(0, 0.1, -8), Vector3(0, 0.1, 7), Vector3(0, 0, 10))
	p.flashlight.set_on(true)
	t.check(k.can_see_player(), "flashlight on at 15 m in front of it: seen")
	p.flashlight.set_on(false)
	t.check(not k.can_see_player(), "flashlight off at 15 m: not seen")
	await _reset(Vector3(0, 0.1, -8), Vector3(0, 0.1, -3), Vector3(0, 0, 10))
	t.check(k.can_see_player(), "standing in the dark at 5 m: seen")
	p.toggle_crouch()
	await t.physics(20)
	t.check(not k.can_see_player(), "crouched in the dark at 5 m: not seen")
	p.toggle_crouch()
	await t.physics(20)
	await _reset(Vector3(0, 0.1, -8), Vector3(0, 0.1, -3), Vector3(0, 0, -20))
	t.check(not k.can_see_player(), "behind it (out of its view cone): not seen")
	await _reset(Vector3(3, 0.1, 0), Vector3(9, 0.1, 0), Vector3(20, 0, 0))
	p.flashlight.set_on(true)
	t.check(not k.can_see_player(), "wall between: not seen")
	p.flashlight.set_on(false)

	# --- noticing takes a moment at range, chase follows
	await _reset(Vector3(0, 0.1, -8), Vector3(0, 0.1, 4), Vector3(0, 0, 10))
	k._investigate(Vector3(0, 0, 0))     # it's coming this way, looking ahead
	p.flashlight.set_on(true)
	await t.physics(10)
	t.eq(k.state_name(), "investigate", "at 12 m it doesn't react instantly (fair warning)")
	for i in 120:
		await t.physics(1)
		if k.state == Keeper.S.CHASE:
			break
	t.eq(k.state_name(), "chase", "keeps looking -> it notices and chases")

	# --- repelled by the beam (costs battery)
	var before := p.flashlight.battery.charge
	await aim_at(p, k.global_position + Vector3.UP * 1.5)
	for i in 60:
		if i % 10 == 0:
			await aim_at(p, k.global_position + Vector3.UP * 1.5)
		else:
			await t.physics(1)
		if k.state == Keeper.S.REPELLED:
			break
	t.eq(k.state_name(), "repelled", "holding the flashlight on its face drives it back")
	t.near(before - p.flashlight.battery.charge, Keeper.REPEL_COST, 0.03, "it drinks 12% of the battery")
	for i in 120:
		await t.physics(1)
		if k.state == Keeper.S.RETREAT:
			break
	t.eq(k.state_name(), "retreat", "then it retreats")
	var dist_a := k.global_position.distance_to(p.global_position)
	await t.physics(90)
	t.check(k.global_position.distance_to(p.global_position) > dist_a, "it moves away from you")

	# --- losing track
	p.flashlight.set_on(false)
	await _reset(Vector3(0, 0.1, -8), Vector3(0, 0.1, -4), Vector3(0, 0, 10))
	k.awareness = 1.0
	k.last_seen = p.global_position
	k.set_state(Keeper.S.CHASE)
	p.global_position = Vector3(9, 0.1, 0)   # out of sight behind the wall
	await t.physics(int(Keeper.LOSE_AFTER * 60) + 30)
	t.eq(k.state_name(), "search", "out of sight for a few seconds: it loses track and searches")
	for i in int(Keeper.SEARCH_TIME * 60) + 60:
		await t.physics(1)
		if k.state == Keeper.S.PATROL:
			break
	t.eq(k.state_name(), "patrol", "then it goes back to patrolling")

	# --- light pools: white light keeps it out until it smothers the light
	var lamp := PoweredLight.new()
	var omni := OmniLight3D.new()
	omni.light_energy = 1.6
	omni.omni_range = 6.0
	omni.light_color = Color(1, 0.9, 0.7)
	lamp.add_child(omni)
	lamp.circuit = "aux"
	t.sandbox.add_child(lamp)
	lamp.global_position = Vector3(-12, 3.0, 8)
	await t.physics(2)
	t.check(lamp.covers(Vector3(-12, 0, 8)), "a powered white lamp makes a safe pool")
	await _reset(Vector3(-12, 0.1, -4), Vector3(-12, 0.1, 8), Vector3(-12, 0, 10))
	k.awareness = 1.0
	k.last_seen = p.global_position
	k.set_state(Keeper.S.CHASE)
	var waited := false
	for i in 400:
		await t.physics(1)
		if k.state == Keeper.S.WAIT_LIGHT:
			waited = true
			break
	t.check(waited, "it stops at the edge of the light")
	t.check(k.global_position.distance_to(p.global_position) > Keeper.CATCH_RANGE, "and doesn't reach you in the light")
	for i in 200:
		await t.physics(1)
		if lamp.is_suppressed():
			break
	t.check(lamp.is_suppressed(), "then it smothers the light")
	t.check(lamp.covers(Vector3(-12, 0, 8)), "the light stutters first (1.4 s warning, still safe)")
	await t.physics(100)
	t.check(not lamp.covers(Vector3(-12, 0, 8)), "after the warning the pool is gone")
	lamp.queue_free()
	await t.physics(2)

	# --- catching: first strike injures and it lets go; injured -> fatal grab
	p.flashlight.set_on(false)
	await _reset(Vector3(0, 0.1, 2), Vector3(0, 0.1, 3.2), Vector3(0, 0, 10))
	k.awareness = 1.0
	k.last_seen = p.global_position
	k.set_state(Keeper.S.CHASE)
	var caught := [null]
	k.caught_player.connect(func(f): caught[0] = f, CONNECT_ONE_SHOT)
	for i in 120:
		await t.physics(1)
		if caught[0] != null:
			break
	t.eq(caught[0], false, "healthy: the first catch is a strike, not a kill")
	t.check(p.vitals.state() == "injured" and not p.dead, "you're injured, still alive (%d hp)" % int(p.vitals.health))
	t.eq(k.state_name(), "retreat", "it lets go and backs off")
	await _reset(Vector3(0, 0.1, 2), Vector3(0, 0.1, 3.2), Vector3(0, 0, 10))
	k.awareness = 1.0
	k.last_seen = p.global_position
	k.set_state(Keeper.S.CHASE)
	caught[0] = null
	k.caught_player.connect(func(f): caught[0] = f, CONNECT_ONE_SHOT)
	for i in 120:
		await t.physics(1)
		if caught[0] != null:
			break
	t.eq(caught[0], true, "injured: the next catch is fatal")
	t.check(p.dead and p.grabbed, "player grabbed and dead")
	t.eq(k.state_name(), "grab", "keeper holds the grab")
