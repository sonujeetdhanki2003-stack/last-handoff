extends TestCase
## Every ending is reachable: SEAL, BROADCAST, BREAK THE CHAIN.

var g: Node
var p: Player


func _tree() -> SceneTree:
	return t.sandbox.get_tree()


func _start() -> void:
	if g:
		g.queue_free()
		await t.physics(3)
	_tree().paused = false
	Events.set_modal(false)
	Legacy.begin_expedition()
	g = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(g)
	p = g.player
	await t.physics(8)


func _done(n: int) -> void:
	for i in n:
		Legacy.begin_expedition()
		Legacy.end_expedition("died", Vector3(0, 0, -4), "corridor")
		Legacy.commit_handoff(Lore.TEMPLATES[1], "", "", "x")


func _wait_card() -> bool:
	for i in 60 * 40:
		await _tree().process_frame
		if g.hud.end_card != null and g.hud.end_card.visible:
			return true
	return false


func _n(name_: String) -> Node:
	return g.get_node("Level/Interactables/" + name_)


func run() -> void:
	# --------------------------------------------------------------- SEAL
	Legacy.reset_chain()
	t.check(not Legacy.can_seal(), "SEAL is not available on a fresh chain")
	_done(2)
	Legacy.decide("power_route", "freezer")
	Legacy.decide("drive", "destroyed")
	t.check(Legacy.can_seal(), "freezer + wiped drive + two members before you: SEAL available")
	await _start()
	GameState.grid.set_on("aux", true)
	GameState.grid.set_on("lift", true)
	var lift: Lift = _n("LiftPanel")
	t.check(lift.can_interact(p), "the lift panel can be used (%s)" % lift.get_refusal(p))
	lift.interact(p)
	await t.physics(2)
	t.check(g.hud.choice_panel.visible and g.hud._choice_title.text == "THE LAST CAGE", "the lift offers to cut the cable")
	g.hud.choose("seal")
	t.check(await _wait_card(), "SEAL sequence plays and ends on its card")
	t.eq(Legacy.ending_reached(), "seal", "chain ended: SEAL")
	t.check(g.ending.played == "seal", "the in-engine sequence ran")
	t.eq(g.hud.end_card._title.text, Lore.ENDINGS["seal"]["title"], "end card title")
	t.check(Legacy.chain["endings_seen"].has("seal"), "recorded as seen")

	# --------------------------------------------------------------- BROADCAST
	Legacy.reset_chain()
	_done(1)
	Legacy.decide("power_route", "lift")
	Legacy.decide("archive", "opened")
	t.check(Legacy.can_broadcast(), "lift route + vault open + drive kept: BROADCAST available")
	await _start()
	var tx: Transmitter = _n("Transmitter")
	t.check(not tx.can_interact(p) and tx.get_refusal(p).contains("drive"), "the transmitter needs the drive")
	GameState.inventory.add("research_drive")
	t.check(tx.can_interact(p), "with the drive it can broadcast")
	t.check(tx.get_hold_time(p) >= 2.5, "holding to send (%.1f s)" % tx.get_hold_time(p))
	tx.interact(p)
	t.check(await _wait_card(), "BROADCAST sequence plays and ends on its card")
	t.eq(Legacy.ending_reached(), "broadcast", "chain ended: BROADCAST")
	t.eq(Legacy.decision("drive"), "kept", "broadcasting keeps the drive (decision recorded)")

	# --------------------------------------------------------------- BREAK THE CHAIN
	Legacy.reset_chain()
	await _start()
	t.check(not Legacy.can_break(), "BREAK needs all of Mara's tapes")
	for id in Lore.MARA_TAPES:
		var log_: AudioLog = g.find_child("Log_" + id, true, false)
		t.check(log_ != null, "Mara's tape is in the level: " + id)
		Legacy.record_tape(id)
	t.check(Legacy.can_break(), "all four tapes heard: BREAK available")
	Legacy.load_chain()
	t.check(Legacy.can_break(), "tapes heard are remembered across restarts")
	Events.expedition_ended.emit("gave_up")
	var hs: HandoffScreen = null
	for i in 400:
		await _tree().process_frame
		if g.hud.handoff != null and g.hud.handoff.visible:
			hs = g.hud.handoff
			break
	t.check(hs != null and hs._refuse.visible, "the handoff screen offers to leave nothing")
	hs.refuse()
	t.check(await _wait_card(), "BREAK sequence plays and ends on its card")
	t.eq(Legacy.ending_reached(), "break", "chain ended: BREAK THE CHAIN")
	t.check(Legacy.chain["history"][-1]["refused"], "the last member left nothing")
	t.check(Legacy.chain["last_handoff"].is_empty(), "no crate for anyone after")
	t.check(not Legacy.has_run_in_progress(), "nothing to continue")
	g.queue_free()
	g = null
	_tree().paused = false
	Events.set_modal(false)
	await t.physics(3)
