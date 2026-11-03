extends TestCase

func _door(props: Dictionary) -> Door:
	var d: Door = load("res://scripts/interaction/door.gd").new()
	for k in props:
		d.set(k, props[k])
	t.sandbox.add_child(d)
	return d


func run() -> void:
	var plain := _door({"door_label": "PLAIN"})
	await t.frames(1)
	t.check(plain.can_interact(null), "unlocked door can be used")
	t.eq(plain.get_prompt(null), "Open Plain", "prompt says open")
	plain.interact(null)
	t.eq(plain.state, Door.State.OPENING, "door starts opening")
	for i in 70:
		await t.physics(1)
	t.check(plain.is_open(), "door fully open after the animation")
	t.near(plain._panel.position.x, plain.width, 0.01, "panel slid into the wall")
	t.eq(plain.get_prompt(null), "Close Plain", "prompt flips to close")
	plain.interact(null)
	for i in 70:
		await t.physics(1)
	t.eq(plain.state, Door.State.CLOSED, "door closes again")

	# panel blocks movement when closed, not when open
	var space := plain.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(plain.global_position + Vector3(0, 1, 1), plain.global_position + Vector3(0, 1, -1), 1)
	await t.physics(2)
	t.check(not space.intersect_ray(q).is_empty(), "closed door blocks (world layer)")
	plain.set_open_immediate(true)
	await t.physics(3)
	t.check(space.intersect_ray(q).is_empty(), "open door is passable")

	var powered := _door({"door_label": "SEC", "required_circuit": "aux"})
	await t.frames(1)
	t.check(not powered.can_interact(null), "powered door locked without power")
	t.eq(powered.get_refusal(null), "No power", "refusal: no power")
	t.eq(powered._status_mat.emission_energy_multiplier, 0.0, "status lamp dark without power")
	GameState.grid.set_on("aux", true)
	await t.frames(1)
	t.check(powered.can_interact(null), "powered door works with power")
	t.check(powered._status_mat.emission_energy_multiplier > 0.0, "status lamp lit with power")

	var keyed := _door({"door_label": "STORE", "key_item": "keycard_blue"})
	await t.frames(1)
	t.check(not keyed.can_interact(null), "keycard door locked without the card")
	t.check(keyed.get_refusal(null).contains("Blue Keycard"), "refusal names the card")
	GameState.inventory.add("keycard_blue")
	t.check(keyed.can_interact(null), "card in inventory unlocks")
	t.eq(keyed.get_prompt(null), "Use Blue Keycard", "prompt says use card")
	keyed.interact(null)
	GameState.inventory.remove("keycard_blue")
	t.check(keyed.can_interact(null), "reader remembers the card after first use")

	var coded := _door({"door_label": "LAB", "needs_code": true, "required_circuit": "lab"})
	await t.frames(1)
	GameState.grid.set_on("lab", true)
	t.check(not coded.can_interact(null), "code door stays locked with power but no code")
	t.check(coded.get_refusal(null).contains("keypad"), "refusal points at the keypad")
	coded.unlock_code()
	t.check(coded.can_interact(null), "unlock_code opens the lock")
	GameState.grid.set_on("aux", false)
	t.check(not coded.can_interact(null), "losing upstream power locks it again")
	GameState.grid.set_on("aux", true)

	# persistence hook
	var pers := _door({"door_label": "P", "persist_id": "door_test"})
	await t.frames(1)
	pers.interact(null)
	for i in 70:
		await t.physics(1)
	t.eq(GameState.get_world("door_test").get("open"), true, "door state stored in GameState.world")
	var again := _door({"door_label": "P2", "persist_id": "door_test"})
	await t.frames(1)
	t.check(again.is_open(), "a door rebuilt with the same id restores open state")
