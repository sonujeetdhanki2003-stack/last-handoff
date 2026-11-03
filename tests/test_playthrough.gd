extends TestCase
## End-to-end: loads the real game scene and completes the prototype mission
## using the player's own interaction path (aim + interact / hold), checking
## objectives and world state at each step.

var g: Node
var p: Player


func _go(pos: Vector3, yaw: float) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.cam.set_view(yaw, -10.0)
	p.cam.global_position = pos + Vector3.UP * 1.55
	await t.physics(4)


func _node(n: String) -> Node:
	return g.get_node("Level/Interactables/" + n)


## Aim at a node and interact like a player would (holding when required).
func _use(target_name: String, offset := Vector3.ZERO, expect_target := true) -> bool:
	var n: Node3D = _node(target_name)
	if n == null:
		t.fail("missing node " + target_name)
		return false
	await aim_at(p, n.global_position + offset)
	await t.physics(2)
	var tgt := p.find_target()
	var ok: bool = tgt == n or (tgt != null and tgt.get("target") == n)
	if expect_target:
		t.check(ok, "aiming at %s targets it (got %s)" % [target_name, str(tgt.name) if tgt else "nothing"])
	if not ok:
		return false
	if not tgt.can_interact(p):
		t.fail("%s refused: %s" % [target_name, tgt.get_refusal(p)])
		return false
	var hold: float = tgt.get_hold_time(p)
	if hold > 0.0:
		Input.action_press("interact")
		p._begin_interact()
		var frames := int(hold * 60.0) + 20
		for i in frames:
			await t.physics(1)
			if p._holding_target == null:
				break
		Input.action_release("interact")
	else:
		p._begin_interact()
	await t.physics(2)
	if Events.modal_open and g.hud.note_panel.visible:
		g.hud.close_note()
	return true


func _wait_door(n: String) -> void:
	for i in 80:
		await t.physics(1)
		if _node(n).is_open():
			break


func run() -> void:
	GameState.new_expedition(2026)
	g = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(g)
	p = g.player
	await t.physics(10)
	t.eq(GameState.objectives.current_id(), "power", "start: objective is the generator")
	t.check(p.flashlight.on, "flashlight starts on")
	t.near(GameState.battery_charge, 0.6, 0.01, "starts at 60% charge")

	# 1. Handoff crate in the shaft
	await _go(Vector3(-1.2, 0.05, 4.2), 45.0)
	await _use("Keycard")
	await _use("BatteryCrate")
	await _use("HandoffNote")
	t.check(GameState.inventory.has("keycard_blue") and GameState.inventory.has("battery") and GameState.inventory.has("note_handoff"), "took keycard, cell and note from the handoff crate")

	# 2. Shaft door, then actually walk through it
	await _go(Vector3(0, 0.05, 1.6), 0.0)
	await _use("DoorShaft", Vector3(0.3, 1.3, 0))
	await _wait_door("DoorShaft")
	t.check(_node("DoorShaft").is_open(), "shaft door open")
	p.cam.set_view(0.0, -10.0)
	Input.action_press("move_forward")
	for i in 120:
		await t.physics(1)
	Input.action_release("move_forward")
	t.check(p.global_position.z < -1.5, "walked through the open door into the corridor (z %.2f)" % p.global_position.z)

	# 3. Generator room
	await _go(Vector3(0.0, 0.05, -5.0), 90.0)
	await _use("DoorGenerator", Vector3(0, 1.3, 0.3))
	await _wait_door("DoorGenerator")
	await _go(Vector3(-4.0, 0.05, -5.0), 90.0)
	t.check(not _node("DoorSecurity").can_interact(p), "security door has no power yet")
	await _use("Generator", Vector3(0, 0.7, 0))
	t.check(GameState.grid.is_powered("aux"), "generator cranked: aux power on")
	t.check(GameState.objectives.is_complete("power"), "objective 'power' complete")
	await _go(Vector3(-8.6, 0.05, -3.0), 90.0)
	await _use("LightsBreaker")
	t.check(GameState.grid.is_powered("corridor_lights"), "corridor lights on via breaker")
	await _go(Vector3(-8.0, 0.05, -7.3), 160.0)
	await _use("FuseGenerator")
	t.eq(GameState.inventory.count("fuse"), 1, "fuse 1/3 (generator room)")

	# 4. Security office: memo with the code + fuse
	await _go(Vector3(0.0, 0.05, -7.0), -90.0)
	await _use("DoorSecurity", Vector3(0, 1.3, -0.3))
	await _wait_door("DoorSecurity")
	t.check(_node("DoorSecurity").is_open(), "powered security door opens")
	await _go(Vector3(6.1, 0.05, -8.8), 180.0)
	await _use("SecurityMemo")
	t.check(GameState.get_flag("code_read"), "read the security memo (code known)")
	t.check(GameState.objectives.is_complete("code"), "objective 'code' complete")
	await _go(Vector3(6.6, 0.05, -4.2), -60.0)
	await _use("FuseSecurity")
	t.eq(GameState.inventory.count("fuse"), 2, "fuse 2/3 (security)")

	# 5. Storage with the keycard
	await _go(Vector3(0.0, 0.05, -15.0), 90.0)
	await _use("DoorStorage", Vector3(0, 1.3, 0.3))
	await _wait_door("DoorStorage")
	t.check(_node("DoorStorage").is_open(), "keycard opens storage")
	await _go(Vector3(-4.6, 0.05, -17.2), 180.0)
	await _use("FuseStorage")
	t.eq(GameState.inventory.count("fuse"), 3, "fuse 3/3 (storage)")
	t.check(GameState.objectives.is_complete("fuses"), "objective 'fuses' complete")
	await _go(Vector3(-3.0, 0.05, -14.2), 180.0)
	await _use("BatteryStorage")

	# 6. Fuse panel + master switch
	await _go(Vector3(0.2, 0.05, -17.0), -90.0)
	for i in 3:
		await _use("FusePanel", Vector3.ZERO, i == 0)
	t.check(GameState.get_flag("fuse_panel_complete"), "fuse panel repaired")
	await _go(Vector3(0.2, 0.05, -18.3), -90.0)
	await _use("MasterSwitch")
	t.check(GameState.grid.is_powered("lab"), "lab power restored")
	t.check(GameState.objectives.is_complete("fuse_panel"), "objective 'fuse_panel' complete")

	# 7. Keypad through the HUD
	await _go(Vector3(0.9, 0.05, -20.6), 0.0)
	await _use("LabKeypad")
	t.check(g.hud.keypad_panel.visible, "keypad UI opened")
	for ch in GameState.lab_code:
		g.hud._keypad_press(ch)
	g.hud._keypad_press("ENT")
	await t.get_tree().create_timer(0.8).timeout
	await _wait_door("DoorLab")
	t.check(_node("DoorLab").is_open(), "lab door opened by the code")

	# 8. Walk into the lab (trigger), take the drive
	await _go(Vector3(0.0, 0.05, -21.0), 0.0)
	Input.action_press("move_forward")
	for i in 90:
		await t.physics(1)
	Input.action_release("move_forward")
	t.check(GameState.get_flag("lab_entered"), "walking into Lab 3 completes 'enter_lab'")
	await _go(Vector3(0.2, 0.05, -28.4), 180.0)
	await _use("ResearchDrive")
	t.check(GameState.inventory.has("research_drive"), "research drive recovered")
	t.eq(GameState.objectives.current_id(), "extract", "objective: return to the lift")

	# 9. Use a spare battery cell
	p.flashlight.battery.charge = 0.3
	t.check(p.flashlight.replace_battery(), "spare cell swapped in")

	# 10. Lift
	var ended := [""]
	Events.expedition_ended.connect(func(r): ended[0] = r, CONNECT_ONE_SHOT)
	await _go(Vector3(2.0, 0.05, 4.4), 180.0)
	await _use("LiftPanel")
	t.eq(ended[0], "extracted", "riding the lift ends the expedition (extracted)")
	t.check(GameState.objectives.is_all_complete(), "all objectives complete")
	t.check(g.hud.end_panel.visible, "end screen shown")
	print("  INFO  world state keys: ", GameState.world.keys())
	get_tree_safe().paused = false
	Events.set_modal(false)


func get_tree_safe() -> SceneTree:
	return t.get_tree()
