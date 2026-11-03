extends TestCase
## Persistent decisions: taken once, by one member, inherited by every later expedition.

var g: Node
var p: Player


func _start() -> void:
	if g:
		g.queue_free()
		await t.physics(3)
	get_tree_().paused = false
	Events.set_modal(false)
	Legacy.begin_expedition()
	g = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(g)
	p = g.player
	await t.physics(8)


func get_tree_() -> SceneTree:
	return t.sandbox.get_tree()


func _end_and_handoff() -> void:
	Legacy.end_expedition("gave_up", p.global_position, GameState.deepest)
	Legacy.commit_handoff(Lore.TEMPLATES[0], "", "", "x")


func _n(name_: String) -> Node:
	return g.get_node("Level/Interactables/" + name_)


func run() -> void:
	await _start()
	var e1 := GameState.expedition_number
	# the junction offers its choice through the choice dialog
	var junction: DecisionPoint = _n("PowerJunction")
	t.check(junction.can_interact(p), "the power junction can be decided")
	junction.interact(p)
	await t.physics(2)
	t.check(g.hud.choice_panel.visible, "a choice dialog opens")
	t.check(g.hud._choice_title.text == "THE LAST CIRCUIT", "it's the power-route choice")
	g.hud.choose("freezer")
	await t.physics(2)
	t.eq(Legacy.decision("power_route"), "freezer", "chose: power the freezer")
	t.check(not g.hud.choice_panel.visible and not Events.modal_open, "dialog closed")
	t.check(not junction.can_interact(p), "a decision can only be made once")
	t.check(not Legacy.decide("power_route", "lift"), "and can't be changed later")
	t.check((g.find_child("LabFreezer", true, false).get("_light") as OmniLight3D).light_energy > 0.0, "the freezer lamp comes on")

	# Varga's terminal needs the drive
	var term: DecisionPoint = _n("VargaTerminal")
	t.check(not term.can_interact(p) and term.get_refusal(p).contains("drive"), "Varga's terminal wants the drive")
	GameState.inventory.add("research_drive")
	t.check(term.can_interact(p), "with the drive: it can read or wipe it")
	term.interact(p)
	await t.physics(2)
	g.hud.choose("destroyed")
	await t.physics(2)
	t.eq(Legacy.decision("drive"), "destroyed", "the drive is wiped")
	t.check(not GameState.inventory.has("research_drive"), "and gone from your pack")

	# the archive vault: seal it
	var vault: Door = _n("DoorVault")
	t.check(not vault.is_open(), "vault starts shut")
	_n("VaultControl").decide("sealed")
	await t.physics(2)
	t.check(vault.welded, "the vault door is welded")
	t.check(not vault.can_interact(p), "a welded door won't open")
	_end_and_handoff()
	var hist: Array = Legacy.chain["history"]
	t.eq(hist[-1]["decisions"].size(), 3, "the history row lists the three decisions this member took")

	# a reload of the game keeps them
	Legacy.load_chain()
	t.eq(Legacy.decision("power_route"), "freezer", "decision survives a restart")
	t.eq(int(Legacy.chain["decisions"]["drive"]["expedition"]), e1, "and remembers who made it")

	# next expedition inherits them
	await _start()
	t.check(GameState.expedition_number == e1 + 1, "next member")
	t.check(not _n("PowerJunction").can_interact(p), "junction already thrown")
	t.check(_n("PowerJunction").get_refusal(p).contains("earlier member"), "'decided by an earlier member'")
	t.check(_n("DoorVault").welded, "the vault is still welded")
	t.check(g.get_node_or_null("Level/Interactables/ResearchDrive") == null, "the wiped drive doesn't come back to the bench")
	t.near(GameState.difficulty, 0.85, 0.01, "the cold slows the Keeper (freezer route)")
	t.check(not _n("Transmitter").can_interact(p), "the transmitter is dead on the freezer route")
	t.check(str(GameState.flags.get("decision_power_route", "")) == "freezer", "decision flags set for the expedition")

	# a fresh chain: the other branches
	Legacy.reset_chain()
	await _start()
	_n("PowerJunction").decide("lift")
	_n("VaultControl").decide("opened")
	await t.physics(60)
	t.check(_n("DoorVault").is_open() or _n("DoorVault").code_unlocked, "opening the vault unlocks and opens the door")
	t.eq(Legacy.decision("archive"), "opened", "archive opened")
	_end_and_handoff()
	await _start()
	t.check(_n("DoorVault").code_unlocked, "the vault stays unlocked for the next member")
	t.check(g.get_node_or_null("Level/Interactables/ResearchDrive") != null, "the kept drive is back on the bench")
	t.near(GameState.difficulty, 1.0, 0.01, "lift route: no slowing")
	g.queue_free()
	g = null
	await t.physics(3)
