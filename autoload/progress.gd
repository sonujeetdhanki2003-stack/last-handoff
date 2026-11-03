extends Node
## v1.2: chapters and local achievements, saved to user://progress.json (SaveIO: atomic
## write + backup slot). Separate from the chain save, so a 1.0 / 1.1 save loads exactly as
## before; on the first launch of 1.2 the old chain is read once to unlock what the player
## already reached (no toasts for those). Fully offline: nothing leaves the device.

signal unlocked(id: String)
signal chapter_unlocked(id: String)

const DEFAULT_PATH := "user://progress.json"

## Chapter runs are self-contained practice expeditions: they never touch the chain save
## (no handoff, no decisions or tapes written, no Continue slot).
const CHAPTERS := [
	{"id": "descent", "num": "I", "title": "The Descent", "text": "Ride the lift down to Level B2. Nothing has power yet.",
		"lock": "Always open."},
	{"id": "power", "num": "II", "title": "Emergency Power", "text": "The generator is running and the corridor lights are on. Find the three fuses.",
		"lock": "Start the emergency generator to open this chapter."},
	{"id": "lab", "num": "III", "title": "Lab 3", "text": "The fuse panel is fixed, the lab has power and you have this expedition's code. Get inside.",
		"lock": "Restore power to Lab 3 to open this chapter."},
	{"id": "ascent", "num": "IV", "title": "The Way Up", "text": "The research drive is in your hands. Get back to the lift.",
		"lock": "Recover the research drive to open this chapter."},
]

## id -> [title, description, hidden]. Hidden ones show as "???" until unlocked.
const ACHIEVEMENTS := {
	"descent": ["First Descent", "Ride the lift down to Level B2.", false],
	"generator": ["Emergency Power", "Crank the generator to life.", false],
	"lab_power": ["Three of Three", "Restore power to Lab 3.", false],
	"lab_open": ["Clearance", "Get through the Lab 3 door.", false],
	"drive": ["The Drive", "Recover the research drive.", false],
	"extracted": ["Rode It Up", "Return to the lift with the drive.", false],
	"repel": ["Not Today", "Drive the Keeper back with your light.", false],
	"hide": ["Hold Your Breath", "Lose the Keeper while hiding.", false],
	"engineer": ["Winch Room", "Read the lift engineer's log.", false],
	"relay": ["Pass It On", "Leave something in the crate for the next member.", false],
	"five": ["The Relay", "Send five members down in one chain.", false],
	"tapes": ["Her Voice", "Find all of Mara's tapes.", true],
	"camp": ["Where It Began", "Reach the Expedition 0 camp.", true],
	"ending": ["Last Handoff", "See how the chain ends.", true],
}

var path := DEFAULT_PATH
var data := {}
var _toast_layer: CanvasLayer
var _toast: PanelContainer
var _toast_title: Label
var _toast_text: Label
var _queue: Array = []
var _toast_t := 0.0
var toasts_shown: Array = []   ## ids (tests)
var tool_mode := false         ## dev tools: no toasts, a scratch save


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var testing := false
	for a in OS.get_cmdline_args():
		if "run_tests" in a:
			testing = true
	if testing or Harness.has("test_save"):
		path = "user://test_progress.json"
		SaveIO.delete_all(path)
	for a in OS.get_cmdline_args():
		# dev tools (screenshots, perf probe, balance sim, scene export) never touch the real progress
		if a.contains("gfx_shots") or a.contains("perf_probe") or a.contains("balance_sim") or a.contains("export_level") or a.contains("keeper_lookdev"):
			path = "user://tool_progress.json"
			tool_mode = true
	load_progress()
	_build_toast()


func fresh() -> Dictionary:
	return {"version": 1, "achievements": {}, "chapters": ["descent"], "retro": false}


func load_progress() -> void:
	var r := SaveIO.load_json(path)
	data = fresh()
	if r["ok"] and r["data"] is Dictionary:
		var d: Dictionary = r["data"]
		if d.get("achievements") is Dictionary:
			for k in d["achievements"]:
				if ACHIEVEMENTS.has(str(k)):
					data["achievements"][str(k)] = int(d["achievements"][k])
		if d.get("chapters") is Array:
			for c in d["chapters"]:
				if chapter_index(str(c)) >= 0 and not (data["chapters"] as Array).has(str(c)):
					data["chapters"].append(str(c))
		data["retro"] = bool(d.get("retro", false))
	if not data["retro"]:
		retro_from_chain(Legacy.chain)
		data["retro"] = true
		save()


func save() -> Error:
	return SaveIO.save_json(path, data)


func use_path(p: String, wipe := true) -> void:
	path = p
	if wipe:
		SaveIO.delete_all(p)
	load_progress()


# ------------------------------------------------------------------ achievements
func is_unlocked(id: String) -> bool:
	return (data["achievements"] as Dictionary).has(id)


func unlocked_count() -> int:
	return (data["achievements"] as Dictionary).size()


## Unlock (once). Returns true when it was new. quiet = no toast (old-save import).
func unlock(id: String, quiet := false) -> bool:
	if not ACHIEVEMENTS.has(id) or is_unlocked(id):
		return false
	data["achievements"][id] = int(Time.get_unix_time_from_system())
	save()
	unlocked.emit(id)
	if not quiet and not tool_mode and not Harness.has("shot"):
		_queue.append(id)
	return true


## What the Achievements screen shows: hidden ones stay "???" until unlocked.
func display(id: String) -> Dictionary:
	var a: Array = ACHIEVEMENTS[id]
	var got := is_unlocked(id)
	if a[2] and not got:
		return {"title": "???", "text": "Hidden. Keep playing.", "unlocked": false, "hidden": true}
	return {"title": a[0], "text": a[1], "unlocked": got, "hidden": a[2]}


# ------------------------------------------------------------------ chapters
func chapter_index(id: String) -> int:
	for i in CHAPTERS.size():
		if CHAPTERS[i]["id"] == id:
			return i
	return -1


func chapter_open(id: String) -> bool:
	return (data["chapters"] as Array).has(id)


func open_chapter(id: String, quiet := false) -> bool:
	if chapter_index(id) < 0 or chapter_open(id):
		return false
	data["chapters"].append(id)
	save()
	chapter_unlocked.emit(id)
	if not quiet and not tool_mode and not Harness.has("shot"):
		_queue.append("chapter:" + id)
	return true


## Look at the live expedition and open any chapter it has reached.
func check_world() -> void:
	if GameState.grid == null:
		return
	if GameState.grid.is_on("aux"):
		open_chapter("power")
	if GameState.grid.is_on("lab"):
		open_chapter("lab")
	if GameState.inventory and GameState.inventory.has("research_drive"):
		open_chapter("ascent")


## First launch of 1.2 over a 1.0 / 1.1 save: unlock what the old chain shows, quietly.
func retro_from_chain(chain: Dictionary) -> void:
	var hist: Array = chain.get("history", []) if chain.get("history") is Array else []
	var best := 0
	for h in hist:
		if not (h is Dictionary):
			continue
		best = maxi(best, Lore.depth_rank(str(h.get("depth", "shaft"))))
		if not bool(h.get("refused", false)) and (str(h.get("item", "")) != "" or str(h.get("message", "")) != "" or str(h.get("custom", "")) != ""):
			unlock("relay", true)
		if str(h.get("depth", "")) == "deep":
			unlock("camp", true)
		if str(h.get("end", "")) == "extracted":
			unlock("extracted", true)
			unlock("drive", true)
			open_chapter("ascent", true)
	var run: Variant = chain.get("run")
	if run is Dictionary and run.get("state") is Dictionary:
		best = maxi(best, Lore.depth_rank(str(run["state"].get("deepest", "shaft"))))
	if not hist.is_empty() or run is Dictionary:
		unlock("descent", true)
	if hist.size() >= 5:
		unlock("five", true)
	if best >= 2:
		open_chapter("power", true)
	if best >= 4:
		open_chapter("lab", true)
		unlock("lab_open", true)
	var dec: Variant = chain.get("decisions", {})
	if dec is Dictionary and dec.has("drive"):
		open_chapter("ascent", true)
	var seen: Variant = chain.get("endings_seen", [])
	if seen is Array and not seen.is_empty():
		unlock("ending", true)
	var tapes: Variant = chain.get("tapes", {})
	if tapes is Dictionary:
		var n := 0
		for t in Lore.MARA_TAPES:
			if tapes.get(t, false):
				n += 1
		if n >= Lore.MARA_TAPES.size():
			unlock("tapes", true)


# ------------------------------------------------------------------ chapter runs
## A chapter checkpoint: the world as a member would have left it by then.
func preset(id: String) -> Dictionary:
	var world := {}
	var inv: Array = []
	var flags := {}
	var spawn := []
	var keeper_at: Variant = null
	var wake := -1.0
	var i := chapter_index(id)
	if i >= 1:
		world["door_shaft"] = {"open": true}
		world["generator_aux"] = {"running": true}
		world["lever_lights"] = {"on": true}
		for p in ["pickup_keycard", "pickup_batterycrate", "pickup_handoffnote"]:
			world[p] = {"taken": true}
		inv = ["keycard_blue", "battery", "note_handoff"]
		spawn = [[-4.2, 0.05, -5.0], -90.0]
		wake = 15.0
	if i >= 2:
		world["door_security"] = {"open": true}
		world["door_storage"] = {"open": true, "key_used": true}
		world["fuse_panel"] = {"inserted": 3}
		world["lever_master"] = {"on": true}
		for p in ["pickup_fusegenerator", "pickup_fusestorage", "pickup_fusesecurity", "pickup_securitymemo"]:
			world[p] = {"taken": true}
		inv = ["keycard_blue", "battery", "note_code"]
		flags["code_read"] = true
		spawn = [[0.0, 0.05, -6.0], 0.0]
		wake = 20.0
	if i >= 3:
		world["door_lab"] = {"open": true, "code_unlocked": true}
		world["keypad_lab"] = {"solved": true}
		world["pickup_researchdrive"] = {"taken": true}
		inv = ["keycard_blue", "battery", "research_drive"]
		flags["lab_entered"] = true
		spawn = [[0.0, 0.05, -26.0], 180.0]
		keeper_at = Vector3(-6.0, 0.0, -6.5)   # out in the generator room, between you and the lift
		wake = 8.0
	return {"world": world, "inventory": inv, "flags": flags, "spawn": spawn, "keeper_at": keeper_at, "wake": wake}


## Set GameState up for a chapter run (the caller changes scene to the game).
func begin_chapter(id: String) -> bool:
	if not chapter_open(id):
		return false
	var p := preset(id)
	GameState.new_expedition()
	GameState.chain_mode = false
	GameState.chapter_run = id
	Legacy.practice = {}
	GameState.expedition_number = Legacy.next_expedition()
	GameState.member_name = "Chapter " + str(CHAPTERS[chapter_index(id)]["num"])
	GameState.world = (p["world"] as Dictionary).duplicate(true)
	for f in p["flags"]:
		GameState.flags[f] = p["flags"][f]
	for it in p["inventory"]:
		GameState.inventory.add(it)
	if not (p["spawn"] as Array).is_empty():
		GameState.resume_player = {"pos": p["spawn"][0], "yaw": p["spawn"][1], "light": true}
	GameState.chapter_keeper_at = p["keeper_at"]
	GameState.chapter_wake = float(p["wake"])
	GameState.play_intro = id == "descent"
	return true


# ------------------------------------------------------------------ toast
func _build_toast() -> void:
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 95
	add_child(_toast_layer)
	_toast = PanelContainer.new()
	_toast.name = "AchievementToast"
	_toast.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.03, 0.034, 0.038, 0.94), UIKit.AMBER_DIM, 2, 16))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_toast_layer.add_child(_toast)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_toast.add_child(v)
	_toast_title = UIKit.label("", 18, UIKit.AMBER, "mono")
	v.add_child(_toast_title)
	_toast_text = UIKit.label("", 28, UIKit.TEXT, "ui_bold")
	v.add_child(_toast_text)


func _process(delta: float) -> void:
	if _toast == null:
		return
	if _toast.visible:
		_toast_t -= delta
		_toast.modulate.a = clampf(minf(_toast_t, 3.6 - _toast_t) * 4.0, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false
		return
	if _queue.is_empty():
		return
	var id: String = _queue.pop_front()
	toasts_shown.append(id)
	if id.begins_with("chapter:"):
		var c: Dictionary = CHAPTERS[chapter_index(id.substr(8))]
		_toast_title.text = "CHAPTER UNLOCKED"
		_toast_text.text = "%s. %s" % [c["num"], c["title"]]
	else:
		_toast_title.text = "ACHIEVEMENT UNLOCKED"
		_toast_text.text = str(ACHIEVEMENTS[id][0])
	_toast_t = 3.6
	_toast.visible = true
	_toast.reset_size()
	var vs := get_viewport().get_visible_rect().size
	var m := Ux.safe_margins(get_viewport())
	var sz := _toast.get_combined_minimum_size()
	_toast.position = Vector2((vs.x - sz.x) * 0.5, m.y + 26.0)
	if not Harness.has("shot"):
		Ux.ui_sound("tab")
