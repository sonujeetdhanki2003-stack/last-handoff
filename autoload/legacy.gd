extends Node
## The handoff chain: everything that survives between expeditions.
## Saved to user://chain.json through SaveIO (atomic write + backup slot).
##
##   history        every finished expedition (ghosts are in Lore.GHOSTS)
##   last_handoff   what the previous member left in the crate (item + message)
##   marks          chalk marks left where members died / exited (capped)
##   notes          older handoff messages, pinned as wall notes (capped)
##   remains        key items dropped where a member fell (so nothing vital is lost)
##   decisions      the three persistent choices
##   world          per-object world state (doors, generator, panels, pickups)
##   tapes          tapes ever heard (Mara's tapes gate the true ending)
##   run            snapshot of an expedition in progress (Continue)

signal chain_changed
signal decision_made(id: String, choice: String)

const DEFAULT_PATH := "user://chain.json"
const MAX_MARKS := 12
const MAX_NOTES := 8
const MAX_HISTORY := 200
const CRITICAL := ["keycard_blue", "keycard_red", "fuse", "crowbar", "research_drive"]

var path := DEFAULT_PATH
var chain := {}
var load_notice := ""         # shown on the menu when the save had to be repaired
var pending := {}             # result of the run that just ended, awaiting the handoff


func _ready() -> void:
	var testing := Harness.has("test_save")
	for a in OS.get_cmdline_args():
		if "run_tests" in a:
			testing = true
	if testing:
		# the test runner never touches the player's real save
		path = "user://test_chain.json"
		SaveIO.delete_all(path)
	load_chain()


func fresh_chain() -> Dictionary:
	return {
		"version": 1, "chain_id": randi() % 1000000 + 1, "created": int(Time.get_unix_time_from_system()),
		"next_expedition": Lore.FIRST_EXPEDITION, "history": [], "marks": [], "notes": [],
		"remains": [], "last_handoff": {}, "decisions": {}, "world": {}, "tapes": {},
		"ending": "", "endings_seen": [], "run": null, "counter": 0,
	}


func load_chain() -> void:
	var r := SaveIO.load_json(path)
	load_notice = ""
	if r["ok"]:
		chain = _migrate(r["data"])
		if r["source"] == "backup":
			load_notice = "Your save file was damaged. Restored the previous save."
			save()
		elif r["source"] == "tmp":
			save()   # the newest save survived a cut-off write; make it the main file again
	else:
		chain = fresh_chain()
		if SaveIO.last_status == "corrupt_reset":
			load_notice = "Your save file was damaged and no backup was usable. A new chain was started."
	chain_changed.emit()


func _migrate(d: Dictionary) -> Dictionary:
	var base := fresh_chain()
	for k in base:
		# Phase 6: a missing key OR a value of the wrong type (an old or hand-edited
		# save) takes the default instead of crashing later. "run" may be null.
		if not d.has(k):
			d[k] = base[k]
		elif k == "run":
			if d[k] != null and not (d[k] is Dictionary):
				d[k] = null
		elif typeof(base[k]) in [TYPE_INT, TYPE_FLOAT]:
			if not (typeof(d[k]) in [TYPE_INT, TYPE_FLOAT]):
				d[k] = base[k]
		elif typeof(d[k]) != typeof(base[k]):
			d[k] = base[k]
	# entries inside the lists must be dictionaries too
	for k in ["history", "marks", "notes", "remains"]:
		d[k] = (d[k] as Array).filter(func(e): return e is Dictionary)
	# JSON numbers come back as floats
	d["next_expedition"] = maxi(int(d["next_expedition"]), Lore.FIRST_EXPEDITION)
	d["chain_id"] = int(d["chain_id"])
	return d


func save() -> Error:
	chain["counter"] = int(chain.get("counter", 0)) + 1
	chain["saved"] = int(Time.get_unix_time_from_system())
	return SaveIO.save_json(path, chain)


func reset_chain() -> void:
	var seen: Array = chain.get("endings_seen", [])
	chain = fresh_chain()
	chain["endings_seen"] = seen
	save()
	chain_changed.emit()


func use_path(p: String, wipe := true) -> void:
	path = p
	if wipe:
		SaveIO.delete_all(p)
	load_chain()


# ----------------------------------------------------------------- queries
func has_run_in_progress() -> bool:
	return chain.get("run") is Dictionary and not (chain["run"] as Dictionary).is_empty()


func expeditions_done() -> int:
	return (chain["history"] as Array).size()


func next_expedition() -> int:
	return int(chain["next_expedition"])


var practice := {}   ## v1.2: decisions taken in a chapter run (never written to the chain)
func decision(id: String) -> String:
	var src: Dictionary = practice if GameState.chapter_run != "" else chain["decisions"]
	var d: Variant = src.get(id)
	return str(d.get("choice", "")) if d is Dictionary else ""


func has_tape(id: String) -> bool:
	return bool(chain["tapes"].get(id, false))


func mara_tapes_found() -> int:
	var n := 0
	for t in Lore.MARA_TAPES:
		if has_tape(t) or GameState.get_flag("log_" + t):
			n += 1
	return n


func ending_reached() -> String:
	return str(chain.get("ending", ""))


## Which endings are open right now (for the lift, transmitter and handoff screen).
func can_seal() -> bool:
	return decision("power_route") == "freezer" and decision("drive") == "destroyed" and expeditions_done() >= 2


func can_broadcast() -> bool:
	return decision("power_route") == "lift" and decision("archive") == "opened" and decision("drive") != "destroyed" and expeditions_done() >= 1


func can_break() -> bool:
	return mara_tapes_found() >= Lore.MARA_TAPES.size()


# ----------------------------------------------------------------- expedition lifecycle
## Start the next expedition of the chain: a new member who inherits the world.
func begin_expedition() -> void:
	var n := next_expedition()
	var seed_ := hash("%d-exp-%d" % [int(chain["chain_id"]), n]) & 0x7fffffff
	GameState.new_expedition(seed_ % 1000000)
	GameState.chain_mode = true
	GameState.expedition_number = n
	GameState.member_name = Lore.member_name(int(chain["chain_id"]), n)
	GameState.inherit(chain["world"], chain)
	pending = {}
	chain["run"] = {"expedition": n, "member": GameState.member_name, "seed": GameState.expedition_seed, "started": int(Time.get_unix_time_from_system())}
	save()


## Resume an expedition that was saved mid-run.
func resume_expedition() -> bool:
	if not has_run_in_progress():
		return false
	var run: Dictionary = chain["run"]
	if not run.has("state"):
		begin_expedition()
		return true
	GameState.restore(run["state"])
	GameState.chain_mode = true
	GameState.member_name = str(run.get("member", ""))
	GameState.expedition_number = int(run.get("expedition", next_expedition()))
	GameState.resume_player = run.get("player", {})
	return true


## Autosave an expedition in progress (called on area change, decisions, pause-quit).
func save_run(player_state: Dictionary) -> void:
	if not GameState.chain_mode or not has_run_in_progress():
		return
	var run: Dictionary = chain["run"]
	run["state"] = GameState.to_dict()
	run["player"] = player_state
	save()


func record_tape(id: String) -> void:
	if GameState.chapter_run != "":
		return   # a chapter run never writes the chain (the flag still counts for this run)
	if not chain["tapes"].get(id, false):
		chain["tapes"][id] = true
		if GameState.chain_mode:
			save()


func decide(id: String, choice: String) -> bool:
	if decision(id) != "":
		return false
	if GameState.chapter_run != "":
		practice[id] = {"choice": choice, "expedition": GameState.expedition_number, "member": GameState.member_name}
		GameState.set_flag("decision_" + id, choice)
		decision_made.emit(id, choice)
		return true
	chain["decisions"][id] = {"choice": choice, "expedition": GameState.expedition_number, "member": GameState.member_name}
	GameState.set_flag("decision_" + id, choice)
	decision_made.emit(id, choice)
	if GameState.chain_mode:
		save()
	return true


## The run is over (death / lift / giving up). Remember how it ended; the handoff
## screen then calls commit_handoff() with what the member leaves behind.
func end_expedition(reason: String, where: Vector3, deepest: String) -> Dictionary:
	pending = {
		"expedition": GameState.expedition_number, "member": GameState.member_name,
		"end": reason, "depth": deepest, "pos": [where.x, where.y, where.z],
		"time": int(GameState.elapsed), "items": GameState.inventory.to_dict(),
		"carried": GameState.inventory_ids(),
	}
	return pending


## Items the member can leave in the crate.
func handoff_choices() -> Array:
	var out: Array = []
	for id in pending.get("carried", []):
		if id in ["note_code", "note_handoff"]:
			continue
		if not out.has(id):
			out.append(id)
	return out


func commit_handoff(message: String, custom: String, item: String, symbol: String, refuse := false) -> Dictionary:
	var n := int(pending.get("expedition", GameState.expedition_number))
	custom = custom.strip_edges().left(80)
	var taken := []
	for id in Lore.DECISIONS:
		var d: Variant = chain["decisions"].get(id)
		if d is Dictionary and int(d.get("expedition", -1)) == n:
			taken.append(Lore.decision_label(id, d["choice"]))
	var entry := {
		"expedition": n, "member": pending.get("member", GameState.member_name),
		"depth": pending.get("depth", "shaft"), "end": pending.get("end", "unknown"),
		"item": "" if refuse else item, "message": "" if refuse else message, "custom": "" if refuse else custom,
		"symbol": "" if refuse else symbol, "decisions": taken, "time": pending.get("time", 0),
		"date": Time.get_date_string_from_system(), "refused": refuse,
	}
	var hist: Array = chain["history"]
	hist.append(entry)
	while hist.size() > MAX_HISTORY:
		hist.pop_front()
	# the world as this member left it
	chain["world"] = GameState.world_for_next()
	for k in GameState.flags:
		if str(k).begins_with("log_"):
			chain["tapes"][str(k).substr(4)] = true
	if not refuse:
		# the previous crate note moves to the wall
		var prev: Dictionary = chain["last_handoff"]
		if not prev.is_empty() and (str(prev.get("message", "")) != "" or str(prev.get("custom", "")) != ""):
			var notes: Array = chain["notes"]
			notes.append(prev)
			while notes.size() > MAX_NOTES:
				notes.pop_front()
		chain["last_handoff"] = {"expedition": n, "member": entry["member"], "item": item, "message": message, "custom": custom}
		var pos: Array = pending.get("pos", [0, 0, 0])
		if symbol != "":
			var marks: Array = chain["marks"]
			marks.append({"expedition": n, "symbol": symbol, "pos": pos})
			while marks.size() > MAX_MARKS:
				marks.pop_front()
		# vital items not handed off spill where the member's run ended
		var spilled := []
		for id in pending.get("carried", []):
			if id in CRITICAL and id != item and not (id == "research_drive" and pending.get("end") == "extracted"):
				spilled.append(id)
		var rem: Array = chain["remains"]
		for k in spilled.size():
			rem.append({"item": spilled[k], "pos": [float(pos[0]) + 0.35 * (k % 2), float(pos[1]), float(pos[2]) + 0.3 * (k / 2)], "id": "remains_%d_%s_%d" % [n, spilled[k], k]})
	else:
		chain["last_handoff"] = {}
	chain["next_expedition"] = n + 1
	chain["run"] = null
	pending = {}
	save()
	chain_changed.emit()
	# v1.2 achievements
	if not refuse and (item != "" or message != "" or custom != ""):
		Progress.unlock("relay")
	if expeditions_done() >= 5:
		Progress.unlock("five")
	return entry


func reach_ending(id: String) -> void:
	chain["ending"] = id
	var seen: Array = chain["endings_seen"]
	if not seen.has(id):
		seen.append(id)
	chain["run"] = null
	save()
	chain_changed.emit()


## Rows for the history screen: ghosts first (marked), then real members, newest last.
func history_rows(include_ghosts := true) -> Array:
	var rows: Array = []
	if include_ghosts:
		for g in Lore.GHOSTS:
			var r: Dictionary = g.duplicate()
			r["ghost"] = true
			r["decisions"] = []
			rows.append(r)
	for h in chain["history"]:
		var r2: Dictionary = (h as Dictionary).duplicate()
		r2["ghost"] = false
		rows.append(r2)
	return rows
