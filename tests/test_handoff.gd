extends TestCase
## The handoff across three simulated expeditions in the real game scene: the crate,
## the item, the message, the marks, the inherited world, the rotated keypad code.

var g: Node
var p: Player


func _start() -> void:
	if g:
		g.queue_free()
		await t.physics(3)
	t.sandbox.get_tree().paused = false
	Events.set_modal(false)
	Legacy.begin_expedition()
	g = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(g)
	p = g.player
	await t.physics(10)


func _wait_handoff() -> HandoffScreen:
	for i in 400:
		await t.sandbox.get_tree().process_frame
		if g.hud.handoff != null and g.hud.handoff.visible:
			return g.hud.handoff
	return null


func run() -> void:
	# ------------------------------------------------------------ Expedition 7
	await _start()
	var first_name := GameState.member_name
	t.eq(GameState.expedition_number, 7, "a new chain's first member is Expedition 7 (six went before)")
	t.check(first_name != "", "member has a name: " + first_name)
	var cd: ChainDirector = g.chain_director
	t.check(cd != null, "chain director runs in chain mode")
	t.check(cd.spawned["crate_note"] != null and str(cd.spawned["crate_note"].title).contains("EXPEDITION 6"), "Expedition 6's crate note is by the lift")
	t.eq(cd.spawned["crate_item"].item_id, "battery", "Dana left a battery")
	t.check(t.sandbox.get_tree().get_nodes_in_group("chalk_marks").size() >= 5, "the ghost expeditions' marks are on the floors")
	t.check(g.find_children("GhostNote_*", "", true, false).size() >= 3, "ghost notes on the walls")
	var code7: String = GameState.lab_code
	# do things the next member should inherit
	g.get_node("Level/Interactables/Keycard").interact(p)
	t.check(GameState.inventory.has("keycard_blue"), "took the keycard")
	var door: Door = g.get_node("Level/Interactables/DoorShaft")
	door.interact(p)
	await t.physics(90)
	t.check(door.is_open(), "opened the shaft door")
	GameState.inventory.add("battery")
	GameState.note_area("storage")
	p.global_position = Vector3(-3.0, 0.05, -14.6)
	await t.physics(3)
	p.hurt(500, "steam")
	var hs := await _wait_handoff()
	t.check(hs != null, "death -> fade -> the handoff screen")
	t.check(t.sandbox.get_tree().paused, "the world is paused behind it")
	t.check(hs.handoff_choices_shown().has("battery") and hs.handoff_choices_shown().has("keycard_blue"), "you can leave what you were carrying")
	t.check(not hs._refuse.visible, "no 'break the chain' option without Mara's tapes")
	hs.select_template(2)
	hs._custom_edit.text = "the second locker sticks"
	hs.set_custom("the second locker sticks")
	hs.select_item("battery")
	hs.select_symbol("circle")
	var entry := hs.confirm()
	t.eq(int(entry["expedition"]), 7, "handoff recorded for Expedition 7")
	t.eq(str(entry["end"]), "injured", "ended: killed by a hazard")
	t.eq(Legacy.chain["history"].size(), 1, "history has one member")
	t.check(Legacy.chain["remains"].any(func(r): return r["item"] == "keycard_blue"), "the keycard (not handed off) spills where you fell")
	var saved := SaveIO.load_json(Legacy.path)
	t.check(saved["ok"] and saved["data"]["history"].size() == 1, "the chain is on disk")

	# ------------------------------------------------------------ Expedition 8
	await _start()
	t.eq(GameState.expedition_number, 8, "next member: Expedition 8")
	t.check(GameState.member_name != first_name, "a different person: " + GameState.member_name)
	cd = g.chain_director
	t.check(str(cd.spawned["crate_note"].title).contains("EXPEDITION 7"), "the crate note is from Expedition 7")
	t.check(str(cd.spawned["crate_note"].body).contains(Lore.TEMPLATES[2]), "the chosen message is in it")
	t.check(str(cd.spawned["crate_note"].body).contains("the second locker sticks"), "and the typed words")
	t.eq(cd.spawned["crate_item"].item_id, "battery", "the battery is in the crate")
	var m7: Array = t.sandbox.get_tree().get_nodes_in_group("chalk_marks").filter(func(m): return int(m.get_meta("expedition")) == 7)
	t.eq(m7.size(), 1, "Expedition 7's mark is chalked on the floor")
	t.check(m7[0].global_position.distance_to(Vector3(-3.0, 0.0, -14.6)) < 0.5 and m7[0].get_meta("symbol") == "circle", "where they fell, the symbol they chose")
	t.check(cd.spawned["remains"].size() == 1 and cd.spawned["remains"][0].item_id == "keycard_blue", "the dead member's keycard lies where they fell")
	t.check(g.get_node("Level/Interactables/DoorShaft").is_open(), "the shaft door is still open (world inherited)")
	t.check(not g.get_node_or_null("Level/Interactables/Keycard") or GameState.get_world("pickup_keycard").get("taken", false), "the keycard Exp 7 took is not back in the old crate")
	t.check(GameState.old_codes.has(code7), "the old lab code is remembered")
	t.check(GameState.lab_code != code7, "the keypad code has changed (%s -> %s)" % [code7, GameState.lab_code])
	var memo := Notes.get_note("note_code")
	t.check(str(memo["body"]).contains("[s]" + code7 + "[/s]"), "the memo shows the old code crossed out")
	t.check(str(memo["body"]).to_lower().contains("duty terminal") or str(memo["body"]).to_lower().contains("security"), "with a hint where the new one is")
	cd.spawned["crate_item"].interact(p)
	cd.spawned["remains"][0].interact(p)
	t.check(GameState.inventory.has("keycard_blue") and GameState.inventory.count("battery") >= 1, "picked up the crate battery and the remains")
	GameState.elapsed = 200.0
	Events.expedition_ended.emit("gave_up")
	hs = await _wait_handoff()
	t.check(hs != null, "giving up -> the handoff screen")
	hs.select_template(0)
	hs.select_item("keycard_blue")
	hs.select_symbol("x")
	hs.confirm()

	# ------------------------------------------------------------ Expedition 9
	await _start()
	t.eq(GameState.expedition_number, 9, "Expedition 9")
	cd = g.chain_director
	t.eq(cd.spawned["crate_item"].item_id, "keycard_blue", "Exp 8 left the keycard in the crate")
	var wall: Array = g.find_children("WallNote_*", "", true, false).filter(func(n): return n is TextNote)
	t.check(wall.any(func(n): return str(n.body).contains("the second locker sticks")), "Exp 7's note moved up onto the shaft wall")
	var marks: Array = t.sandbox.get_tree().get_nodes_in_group("chalk_marks")
	t.check(marks.any(func(m): return int(m.get_meta("expedition")) == 7) and marks.any(func(m): return int(m.get_meta("expedition")) == 8), "both earlier members' marks are on the floor")
	t.check(cd.spawned["remains"].is_empty(), "no remains (the keycard was handed off this time)")
	var rows: Array = Legacy.history_rows(true)
	t.eq(rows.size(), Lore.GHOSTS.size() + 2, "history: the ghosts + two members")
	t.eq(str(rows[-1]["end"]), "gave_up", "newest row is Expedition 8, gave up")
	t.eq(str(rows[-1]["item"]), "keycard_blue", "with the item they left")
	t.check(GameState.old_codes.size() >= 2, "two old codes remembered")

	# ------------------------------------------------------------ caps
	for i in 20:
		Legacy.end_expedition("died", Vector3(i * 0.3, 0, -5), "corridor")
		Legacy.commit_handoff("Don't trust the lights.", "note %d" % i, "", "tally")
	t.eq(Legacy.chain["marks"].size(), Legacy.MAX_MARKS, "chalk marks pile up but are capped at %d" % Legacy.MAX_MARKS)
	t.check(Legacy.chain["notes"].size() <= Legacy.MAX_NOTES, "wall notes are capped at %d" % Legacy.MAX_NOTES)
	t.eq(int(Legacy.chain["marks"][-1]["expedition"]), int(Legacy.chain["history"][-1]["expedition"]), "the newest mark is kept, the oldest dropped")
	g.queue_free()
	g = null
	t.sandbox.get_tree().paused = false
	Events.set_modal(false)
	await t.physics(3)
