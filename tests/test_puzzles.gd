extends TestCase

func run() -> void:
	# --- Puzzle 1: fuse panel
	var panel := FusePanel.new()
	panel.persist_id = "fuse_test"
	t.sandbox.add_child(panel)
	await t.frames(1)
	t.check(not panel.can_interact(null), "empty-handed: panel refuses")
	t.check(panel.get_refusal(null).contains("0/3"), "refusal shows 0/3")
	GameState.inventory.add("fuse", 2)
	panel.interact(null)
	panel.interact(null)
	t.eq(panel.inserted, 2, "two fuses seated")
	t.eq(GameState.inventory.count("fuse"), 0, "fuses consumed from inventory")
	t.check(not panel.can_interact(null), "out of fuses: refuses")
	t.check(not GameState.get_flag("fuse_panel_complete"), "not complete at 2/3")
	t.check(panel._fuse_meshes[1].visible and not panel._fuse_meshes[2].visible, "seated fuses are visible in the panel")
	GameState.inventory.add("fuse")
	panel.interact(null)
	t.check(panel.is_complete() and GameState.get_flag("fuse_panel_complete"), "third fuse completes the panel")
	t.eq(GameState.objectives.get_objective("fuses")["progress"], 3, "fuse objective 3/3")
	GameState.inventory.add("fuse")
	t.check(not panel.can_interact(null), "completed panel takes no more fuses")
	t.eq(GameState.get_world("fuse_test").get("inserted"), 3, "panel state stored for persistence")

	# --- Puzzle 2: keypad + code from the memo
	t.eq(GameState.lab_code.length(), 4, "expedition has a 4-digit lab code")
	var other := GameState.lab_code
	GameState.new_expedition(999)
	t.check(GameState.lab_code != other, "different expeditions get different codes")
	var memo := Notes.get_note("note_code")
	t.check(memo["body"].contains(GameState.lab_code), "the security memo shows this expedition's code")
	var door: Door = load("res://scripts/interaction/door.gd").new()
	door.needs_code = true
	door.required_circuit = "lab"
	door.name = "LabDoor"
	t.sandbox.add_child(door)
	var pad := Keypad.new()
	pad.required_circuit = "lab"
	pad.door_path = NodePath("../LabDoor")
	pad.lockout_seconds = 0.5
	t.sandbox.add_child(pad)
	await t.frames(1)
	t.check(not pad.can_interact(null), "keypad dead without lab power")
	t.check(not pad.submit(GameState.lab_code), "correct code ignored while unpowered")
	GameState.grid.set_on("aux", true)
	GameState.set_flag("fuse_panel_complete")
	GameState.grid.set_on("lab", true)
	await t.frames(1)
	t.check(pad.can_interact(null), "keypad live with lab power")
	var opened := [false]
	Events.open_keypad.connect(func(k): opened[0] = k == pad, CONNECT_ONE_SHOT)
	pad.interact(null)
	t.check(opened[0], "interacting opens the keypad UI")
	var wrong := "0000" if GameState.lab_code != "0000" else "1111"
	t.check(not pad.submit(wrong), "wrong code rejected")
	t.check(not door.code_unlocked, "door stays locked")
	pad.submit(wrong)
	pad.submit(wrong)
	t.check(pad.is_locked_out(), "3 wrong codes -> lockout")
	t.check(not pad.submit(GameState.lab_code), "even the right code is ignored during lockout")
	t.check(pad.get_refusal(null).contains("locked out"), "lockout explained")
	await t.get_tree().create_timer(0.7).timeout
	t.check(not pad.is_locked_out(), "lockout expires")
	t.check(pad.submit(GameState.lab_code), "correct code accepted")
	t.check(door.code_unlocked, "door unlocked by the keypad")
	t.eq(door.state, Door.State.OPENING, "door opens automatically")
	t.check(not pad.can_interact(null), "solved keypad is done")

	# --- Keypad UI drives the same logic (HUD)
	GameState.new_expedition(4321)
	GameState.grid.set_on("aux", true)
	GameState.set_flag("fuse_panel_complete")
	GameState.grid.set_on("lab", true)
	var door2: Door = load("res://scripts/interaction/door.gd").new()
	door2.needs_code = true
	door2.name = "LabDoor2"
	t.sandbox.add_child(door2)
	var pad2 := Keypad.new()
	pad2.door_path = NodePath("../LabDoor2")
	t.sandbox.add_child(pad2)
	var hud: CanvasLayer = load("res://scenes/ui/hud.tscn").instantiate()
	t.sandbox.add_child(hud)
	await t.frames(2)
	hud.open_keypad(pad2)
	t.check(hud.keypad_panel.visible and Events.modal_open, "keypad panel opens as a modal")
	for ch in GameState.lab_code:
		hud._keypad_press(ch)
	t.eq(hud._keypad_display.text, " ".join(GameState.lab_code.split("")), "display shows typed digits")
	hud._keypad_press("ENT")
	await t.get_tree().create_timer(0.8).timeout
	t.check(door2.code_unlocked, "typing the code in the UI unlocks the door")
	t.check(not hud.keypad_panel.visible and not Events.modal_open, "keypad closes after success")
