extends TestCase
## Hiding spots: the locker and under the cot; what the Keeper can and can't do about them.

var k: Keeper
var p: Player


func run() -> void:
	make_floor(60.0)
	p = spawn_player(Vector3(0, 0.1, 6))
	await t.physics(5)
	var locker := HidingSpot.new()
	locker.kind = "locker"
	locker.name = "TestLocker"
	t.sandbox.add_child(locker)
	locker.global_position = Vector3(0, 0, 0)
	var cot := HidingSpot.new()
	cot.kind = "cot"
	cot.view_offset = Vector3(0, 0.22, 0.3)
	cot.exit_offset = Vector3(0, 0.05, 1.0)
	t.sandbox.add_child(cot)
	cot.global_position = Vector3(8, 0, 0)
	await t.physics(3)
	NavBaker.bake(t.sandbox)
	k = Keeper.new()
	t.sandbox.add_child(k)
	k.global_position = Vector3(0, 0.1, -12)
	k.setup(p, [Vector3(-10, 0, -12), Vector3(10, 0, -12)])
	k.wake()
	await t.physics(5)

	# --- climbing in and out
	p.global_position = locker.outside_point()
	await aim_at(p, locker.global_position + Vector3.UP * 1.1)
	t.check(p.find_target() == locker, "aiming at the locker targets it")
	t.eq(locker.get_prompt(p), "Hide in the locker", "prompt says hide")
	p._begin_interact()
	await t.physics(3)
	t.check(p.is_hidden(), "player is hidden")
	t.check(p.collider.disabled and not p.model.visible, "body tucked away (no collision, not drawn)")
	t.check(locker.view.current, "camera looks out through the locker slits")
	t.check(not p.flashlight.on, "flashlight goes off when you hide")
	t.check(not locker.can_interact(p), "an occupied locker can't be entered again")
	var noises: Array = []
	Events.noise.connect(func(_pos, r, s): noises.append(s))
	Input.action_press("move_forward")
	await t.physics(30)
	Input.action_release("move_forward")
	t.check(p.global_position.distance_to(locker.outside_point()) < 1.0 and p.velocity.length() < 0.01, "can't walk while hidden")
	# the Keeper walks right past
	k.global_position = Vector3(0, 0.1, 1.6)
	k.look_at_flat(Vector3(0, 0, 0))
	await t.physics(3)
	t.check(not k.can_see_player(), "the Keeper can't see you in the locker, even right in front of it")
	# leave with Interact
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	p._unhandled_input(ev)
	await t.physics(3)
	t.check(not p.is_hidden(), "Interact again: out of the locker")
	t.check(p.global_position.distance_to(locker.outside_point()) < 0.3, "you step out in front of it")
	t.check(p.model.visible and not p.collider.disabled and p.cam.camera.current, "body and camera back")

	# --- unseen: it loses you
	await t.physics(10)
	k.global_position = Vector3(0, 0.1, -12)
	k.velocity = Vector3.ZERO
	k.set_state(Keeper.S.PATROL)
	p.global_position = locker.outside_point()
	p.velocity = Vector3.ZERO
	await t.physics(3)
	# it was chasing but lost sight, then you hid
	k.last_seen = p.global_position
	k.awareness = 1.0
	k.set_state(Keeper.S.CHASE)
	k.global_position = Vector3(-9, 0.1, -12)
	k.look_at_flat(Vector3(-20, 0, -12))  # facing away: can't see you go in
	await t.physics(2)
	locker.interact(p)
	await t.physics(2)
	t.check(k.seen_hiding == null, "it didn't see you go in")
	var survived := true
	for i in 60 * 14:
		await t.physics(1)
		if p.dead:
			survived = false
			break
		if k.state == Keeper.S.PATROL and i > 60:
			break
	t.check(survived and k.state_name() in ["patrol", "search"], "it searches, then gives up (you live)")
	locker.leave(p)
	await t.physics(5)

	# --- seen going in (from close range): it tears the door open and drags you out.
	# Phase 6: at full health that is a strike you survive; injured, it is the end.
	for injured in [false, true]:
		p.dead = false
		p.grabbed = false
		p.vitals.health = 40.0 if injured else 100.0
		p.set_control(true)
		k.set_state(Keeper.S.PATROL)
		await t.physics(2)
		p.global_position = locker.outside_point()
		var kp := p.global_position + (Vector3(0.5, 0.1, 6.5) - p.global_position).normalized() * (Keeper.SEEN_HIDING_RANGE - 1.0)
		k.global_position = Vector3(kp.x, 0.1, kp.z)
		k.velocity = Vector3.ZERO
		k.look_at_flat(p.global_position)
		await t.physics(3)
		k.awareness = 1.0
		k.last_seen = p.global_position
		k.set_state(Keeper.S.CHASE)
		await t.physics(2)
		locker.interact(p)
		await t.physics(2)
		t.check(k.seen_hiding == locker, "it watched you go in from %.0f m (%s)" % [Keeper.SEEN_HIDING_RANGE - 1.0, "injured" if injured else "healthy"])
		var struck := [false]
		var cb := func(_f: bool): struck[0] = true
		k.caught_player.connect(cb)
		for i in 60 * 8:
			await t.physics(1)
			if p.dead or struck[0]:
				break
		k.caught_player.disconnect(cb)
		await t.physics(2)
		t.check(not p.is_hidden() and locker.occupant == null, "it pulls you out of the locker (%s)" % ("injured" if injured else "healthy"))
		if injured:
			for i in 60 * 6:
				if p.dead:
					break
				await t.physics(1)
			t.check(p.dead, "injured: pulled out = the end")
		else:
			t.check(struck[0] and not p.dead and p.vitals.health < 100.0, "healthy: pulled out and struck, but alive")
	# seen from farther than SEEN_HIDING_RANGE: the locker holds
	p.dead = false
	p.grabbed = false
	p.vitals = Vitals.new()
	p.set_control(true)
	k.set_state(Keeper.S.PATROL)
	await t.physics(2)
	p.global_position = locker.outside_point()
	var far := p.global_position + (Vector3(0.5, 0.1, 6.5) - p.global_position).normalized() * (Keeper.SEEN_HIDING_RANGE + 0.8)
	k.global_position = Vector3(far.x, 0.1, far.z)
	k.look_at_flat(p.global_position)
	await t.physics(3)
	k.set_state(Keeper.S.CHASE)
	await t.physics(2)
	locker.interact(p)
	await t.physics(2)
	t.check(k.seen_hiding == null, "from %.1f m it can't tell which locker you used" % (Keeper.SEEN_HIDING_RANGE + 0.8))
	locker.leave(p)
	await t.physics(5)

	# --- under the cot
	p.dead = false
	p.grabbed = false
	p.vitals = Vitals.new()
	p.set_control(true)
	k.set_state(Keeper.S.PATROL)
	k.global_position = Vector3(20, 0.1, -12)
	p.global_position = cot.outside_point()
	await t.physics(3)
	t.eq(cot.get_prompt(p), "Hide under the cot", "the cot is a hiding spot too")
	cot.interact(p)
	await t.physics(2)
	t.check(p.is_hidden() and cot.view.current, "under the cot, low camera")
	t.check(cot.view.global_position.y < 0.5, "camera at floor level")
	cot.leave(p)
	await t.physics(2)
	t.check(not p.is_hidden(), "out from under the cot")
