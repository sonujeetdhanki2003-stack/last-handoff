extends TestCase

func run() -> void:
	make_floor()
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await t.physics(4)
	# a pickup 1.4 m in front at waist height, a wall-mounted lever off to the side
	var item := Pickup.new()
	item.item_id = "fuse"
	t.sandbox.add_child(item)
	item.global_position = Vector3(0, 0.9, -1.4)
	var far_item := Pickup.new()
	far_item.item_id = "battery"
	t.sandbox.add_child(far_item)
	far_item.global_position = Vector3(0, 0.9, -6.0)
	await t.physics(3)

	await aim_at(p, item.global_position + Vector3(0, 0.05, 0))
	t.eq(p.find_target(), item, "camera ray finds the pickup in reach")
	await t.physics(2)
	t.eq(p.current_target, item, "player tracks it as the current target (drives the HUD prompt)")
	t.eq(item.get_prompt(p), "Take Ceramic Fuse", "prompt text")
	t.check(p.try_interact(), "interact succeeds")
	t.eq(GameState.inventory.count("fuse"), 1, "fuse in inventory")

	await aim_at(p, far_item.global_position)
	await t.physics(2)
	t.check(p.find_target() != far_item, "items beyond reach (6 m) are not targetable")

	# Walls block interaction through them
	var wall := make_wall(Vector3(0, 1, -1.0), Vector3(3, 2, 0.2))
	var behind := Pickup.new()
	behind.item_id = "battery"
	t.sandbox.add_child(behind)
	behind.global_position = Vector3(0, 0.9, -1.6)
	await t.physics(3)
	await aim_at(p, behind.global_position)
	t.check(p.find_target() != behind, "cannot interact through a wall")
	wall.queue_free()
	behind.queue_free()
	await t.physics(3)

	# Hold interactions: progress, cancel on release, complete after hold_time
	var gen := Generator.new()
	t.sandbox.add_child(gen)
	gen.global_position = Vector3(1.6, 0, -1.2)
	await t.physics(3)
	await aim_at(p, gen.global_position + Vector3(0, 0.7, 0))
	t.eq(p.find_target(), gen, "generator targeted")
	var progress := []
	p.hold_progress.connect(func(f): progress.append(f))
	Input.action_press("interact")
	p._begin_interact()
	for i in 30:
		await t.physics(1)
	t.check(not gen.running, "generator not started after 0.5 s of a 2 s hold")
	Input.action_release("interact")
	await t.physics(2)
	t.check(progress.has(-1.0), "releasing cancels the hold (HUD bar hidden)")
	t.check(p._holding_target == null, "hold state cleared")
	progress.clear()
	Input.action_press("interact")
	p._begin_interact()
	for i in 140:
		await t.physics(1)
		if gen.running:
			break
	Input.action_release("interact")
	t.check(gen.running, "holding for the full time starts the generator")
	t.check(GameState.grid.is_powered("aux"), "generator powered the aux circuit")
	t.check(progress.size() > 10 and progress.max() >= 0.9, "hold progress reported to the HUD")

	gen.queue_free()
	p.global_position = Vector3(0, 0.05, 0)
	await t.physics(3)
	# Refusals bubble up as feedback text
	var msgs := []
	var cb := func(m): msgs.append(m)
	Events.interaction_feedback.connect(cb)
	var door: Door = load("res://scripts/interaction/door.gd").new()
	door.key_item = "keycard_blue"
	door.door_label = "TEST"
	door.position = Vector3(-1.5, 0, -1.6)  # set before entering the tree (sync_to_physics panels don't follow later parent moves)
	t.sandbox.add_child(door)
	await t.physics(3)
	await aim_at(p, door.global_position + Vector3(0, 1.2, 0))
	var tgt := p.find_target()
	t.check(tgt != null and tgt.get("target") == door, "door panel forwards to the door")
	p._begin_interact()
	t.check(msgs.size() > 0 and str(msgs[-1]).contains("Blue Keycard"), "locked door explains what it needs")
	Events.interaction_feedback.disconnect(cb)
