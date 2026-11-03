extends Node
## State of the current expedition: inventory, power grid, objectives, flags
## and per-object world state. Phase 4 will persist `world` + `flags` across
## expeditions (the handoff system); everything here already serialises to a Dictionary.

signal flag_changed(flag: String, value: Variant)
signal expedition_started

const FUSES_NEEDED := 3

var inventory: Inventory
var grid: PowerGrid
var objectives: ObjectiveTracker
var flags := {}
var world := {}          # persist_id -> Dictionary (doors, generators, panels...)
var expedition_seed := 0
var lab_code := "0000"
var expedition_number := 1
var battery_charge := 0.6  # flashlight charge carried between scenes / saves
var elapsed := 0.0
var active := false

# --- Phase 4: the handoff chain -------------------------------------------------
var chain_mode := false        ## true when this expedition belongs to the saved chain
var threat_enabled := true     ## the Keeper and hazards (the legacy system tests turn it off)
var member_name := ""
var deepest := "shaft"         ## deepest area reached this run (Lore.DEPTH)
var old_codes: Array = []      ## lab codes of earlier expeditions (crossed out on the memo)
var resume_player := {}        ## player position/vitals when continuing a saved run
var difficulty := 1.0          ## keeper speed scale (the freezer decision lowers it)
var play_intro := false        ## Phase 5: the next game scene opens with the lift cold-open
var title_card := false        ## Phase 5: the next game scene opens with the expedition title card
var chapter_run := ""          ## v1.2: a chapter-select run (self-contained, never written to the chain)
var chapter_keeper_at: Variant = null   ## v1.2: where the Keeper starts in that chapter (null = its lair)
var chapter_wake := -1.0       ## v1.2: seconds until the Keeper wakes in that chapter (-1 = as usual)


func _ready() -> void:
	new_expedition()


func _process(delta: float) -> void:
	if active and not get_tree().paused:
		elapsed += delta


func new_expedition(p_seed := -1) -> void:
	expedition_seed = p_seed if p_seed >= 0 else int(Time.get_unix_time_from_system()) % 1000000
	var rng := RandomNumberGenerator.new()
	rng.seed = expedition_seed
	lab_code = "%04d" % rng.randi_range(1000, 9999)
	flags.clear()
	world.clear()
	elapsed = 0.0
	battery_charge = 0.6
	chain_mode = false
	chapter_run = ""
	chapter_keeper_at = null
	chapter_wake = -1.0
	member_name = ""
	deepest = "shaft"
	old_codes = []
	resume_player = {}
	difficulty = 1.0

	inventory = Inventory.new(8)
	grid = PowerGrid.new()
	grid.define("aux")                       # emergency generator
	grid.define("corridor_lights", ["aux"])  # breaker lever in the generator room
	grid.define("lab", ["aux"])              # fuse panel + master switch

	objectives = ObjectiveTracker.new()
	objectives.add("power", "Start the emergency generator")
	objectives.add("fuses", "Find replacement fuses", FUSES_NEEDED)
	objectives.add("fuse_panel", "Repair the fuse panel and restore lab power")
	objectives.add("code", "Find the lab access code")
	objectives.add("enter_lab", "Get into Lab 3")
	objectives.add("drive", "Recover the research drive", 1, true)
	objectives.add("extract", "Return to the lift with the drive", 1, true)

	inventory.item_added.connect(_on_item_added)
	grid.circuit_changed.connect(_on_circuit_changed)
	active = true
	expedition_started.emit()


func set_flag(flag: String, value: Variant = true) -> void:
	if flags.get(flag) == value:
		return
	flags[flag] = value
	flag_changed.emit(flag, value)
	match flag:
		"code_read":
			objectives.complete("code")
		"lab_entered":
			objectives.complete("enter_lab")
			objectives.reveal("drive")
		"fuses_installed":
			_update_fuse_progress()


func get_flag(flag: String, default: Variant = false) -> Variant:
	return flags.get(flag, default)


func get_world(persist_id: String) -> Dictionary:
	return world.get(persist_id, {})


func set_world(persist_id: String, state: Dictionary) -> void:
	if persist_id != "":
		world[persist_id] = state


func _on_item_added(id: String, _qty: int) -> void:
	match id:
		"fuse":
			_update_fuse_progress()
		"research_drive":
			objectives.reveal("drive")
			objectives.complete("drive")
			objectives.reveal("extract")


func _update_fuse_progress() -> void:
	var total := inventory.count("fuse") + int(get_flag("fuses_installed", 0))
	objectives.set_progress("fuses", total)


func _on_circuit_changed(id: String, powered: bool) -> void:
	if not powered:
		return
	match id:
		"aux":
			objectives.complete("power")
		"lab":
			objectives.complete("fuse_panel")


func to_dict() -> Dictionary:
	return {
		"version": 1, "seed": expedition_seed, "lab_code": lab_code, "expedition": expedition_number,
		"flags": flags.duplicate(true), "world": world.duplicate(true), "battery": battery_charge,
		"elapsed": elapsed, "inventory": inventory.to_dict(), "grid": grid.to_dict(),
		"objectives": objectives.to_dict(), "deepest": deepest, "old_codes": old_codes.duplicate(),
		"difficulty": difficulty, "member": member_name,
	}



# --- Phase 4 ------------------------------------------------------------------
## Take over the world as the previous member left it (Legacy.begin_expedition).
func inherit(prev_world: Dictionary, chain: Dictionary) -> void:
	world = prev_world.duplicate(true)
	var codes: Variant = world.get("_codes", {}).get("old", [])
	old_codes = (codes as Array).duplicate() if codes is Array else []
	world.erase("_codes")
	# re-placed every expedition: the memo (now crossed out) and the drive on the bench
	world.erase("pickup_securitymemo")
	world.erase("pickup_researchdrive")
	battery_charge = 0.5
	var dec: Dictionary = chain.get("decisions", {})
	for id in dec:
		if dec[id] is Dictionary:
			flags["decision_" + str(id)] = str(dec[id].get("choice", ""))
	if dec.get("power_route", {}).get("choice", "") == "freezer":
		difficulty = 0.85


## The world handed to the next member: generators run dry between descents,
## everything else (doors, panels, levers, solved puzzles, taken items) stays.
func world_for_next() -> Dictionary:
	var w := world.duplicate(true)
	var gen: Dictionary = w.get("generator_aux", {})
	if gen.get("running", false) or gen.get("primed", false):
		w["generator_aux"] = {"running": false, "primed": true}
	var olds: Array = old_codes.duplicate()
	if not olds.has(lab_code):
		olds.append(lab_code)
	while olds.size() > 4:
		olds.pop_front()
	w["_codes"] = {"old": olds}
	return w


func restore(d: Dictionary) -> void:
	new_expedition(int(d.get("seed", 0)))
	lab_code = str(d.get("lab_code", lab_code))
	expedition_number = int(d.get("expedition", expedition_number))
	flags = (d.get("flags", {}) as Dictionary).duplicate(true)
	world = (d.get("world", {}) as Dictionary).duplicate(true)
	battery_charge = float(d.get("battery", battery_charge))
	elapsed = float(d.get("elapsed", 0.0))
	deepest = str(d.get("deepest", "shaft"))
	old_codes = (d.get("old_codes", []) as Array).duplicate()
	difficulty = float(d.get("difficulty", 1.0))
	inventory.from_dict(d.get("inventory", {}))
	if d.has("objectives"):
		objectives.from_dict(d["objectives"])


func inventory_ids() -> Array:
	var out: Array = []
	for i in inventory.size:
		var s: Variant = inventory.get_slot(i)
		if s != null:
			for k in int(s["qty"]):
				out.append(s["id"])
	return out


func note_area(area: String) -> bool:
	if Lore.depth_rank(area) > Lore.depth_rank(deepest):
		deepest = area
		return true
	return false
