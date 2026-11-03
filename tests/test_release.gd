extends TestCase
## Phase 6 release pass: a long chain of expeditions in the real game scene with a
## death in every area, save / quit / Continue at random points, power cuts during
## saves, hostile save files, settings persistence, a leak check over a long session,
## and the "no network" rule.

var g: Node
var p: Player
var rng := RandomNumberGenerator.new()


func _tree() -> SceneTree:
	return t.sandbox.get_tree()


func _spawn_game() -> void:
	if g:
		g.queue_free()
		g = null
		await t.physics(3)
	_tree().paused = false
	Events.set_modal(false)
	g = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(g)
	p = g.player
	await t.physics(8)


func _wait_handoff() -> HandoffScreen:
	for i in 500:
		await _tree().process_frame
		if g.hud.handoff != null and g.hud.handoff.visible:
			return g.hud.handoff
	return null


## A standing spot inside an area (closest navmesh point to the rect centre, or the
## centre itself where the Keeper's navmesh does not reach).
func _spot(area: String) -> Vector3:
	var r: Array = Zones.RECTS[area]
	var c := Vector3((r[0] + r[1]) * 0.5, 0.05, (r[2] + r[3]) * 0.5)
	var map: RID = g.get_world_3d().navigation_map
	var q := NavigationServer3D.map_get_closest_point(map, c)
	if Zones.area_at(q) == area:
		return q + Vector3(0, 0.05, 0)
	return c


func run() -> void:
	rng.seed = 6006
	Legacy.reset_chain()
	await _chain_with_death_everywhere()
	await _power_cuts()
	await _hostile_saves()
	await _settings_persist()
	await _leak_check()
	_no_network_code()
	if g:
		g.queue_free()
		g = null
	_tree().paused = false
	Events.set_modal(false)


# ------------------------------------------------------------------ chain
func _chain_with_death_everywhere() -> void:
	var areas: Array = Zones.RECTS.keys()
	var names := {}
	var last_item := ""
	var causes := ["keeper", "steam", "gas", "wire", "fall"]
	for i in areas.size():
		var area: String = areas[i]
		Legacy.begin_expedition()
		await _spawn_game()
		var n := GameState.expedition_number
		t.eq(n, Lore.FIRST_EXPEDITION + i, "expedition %d starts (%d in a row)" % [n, i + 1])
		t.check(not names.has(GameState.member_name), "a new member every time: " + GameState.member_name)
		names[GameState.member_name] = true
		if last_item != "":
			var cd: ChainDirector = g.chain_director
			t.check(cd.spawned.get("crate_item") != null and cd.spawned["crate_item"].item_id == last_item, "Exp %d finds what Exp %d left (%s)" % [n, n - 1, last_item])
		# do something the world should remember, then save / quit / Continue mid-run
		GameState.inventory.add("battery")
		if i % 2 == 0:
			GameState.inventory.add("medkit")
		var spot := _spot(area)
		p.global_position = spot
		p.vitals.health = 63.0 + i
		await t.physics(int(rng.randi_range(5, 40)))
		g.autosave()
		var inv_before: Dictionary = GameState.inventory.to_dict()
		var pos_before := p.global_position
		# quit: drop the scene and reload the chain from disk, as a restart would
		g.queue_free()
		g = null
		await t.physics(3)
		Legacy.load_chain()
		t.check(Legacy.has_run_in_progress(), "Exp %d: Continue is offered after quitting in the %s" % [n, area])
		t.check(Legacy.resume_expedition(), "Exp %d: Continue works" % n)
		await _spawn_game()
		t.eq(GameState.expedition_number, n, "same expedition after Continue")
		t.check(p.global_position.distance_to(pos_before) < 0.6, "position restored in the %s (%.2f m off)" % [area, p.global_position.distance_to(pos_before)])
		t.eq(GameState.inventory.to_dict(), inv_before, "inventory restored")
		t.near(p.vitals.health, 63.0 + i, 0.5, "health restored")
		# die here
		var cause: String = causes[i % causes.size()]
		var at := p.global_position
		if cause == "keeper":
			p.vitals.health = 10.0
			var k: Keeper = g.keeper if g.keeper else g.spawn_keeper()
			k.think = false
			k.global_position = at + Vector3(0.4, 0, 0.4)
			k._catch(false)
		else:
			p.hurt(500, cause)
		var hs := await _wait_handoff()
		t.check(hs != null, "death in the %s (%s) -> the handoff screen" % [area, cause])
		if hs == null:
			return
		var choices := hs.handoff_choices_shown()
		var item: String = "battery" if choices.has("battery") else (choices[0] if choices.size() > 0 else "")
		hs.select_template(i % Lore.TEMPLATES.size())
		hs.select_item(item)
		hs.select_symbol(["circle", "x", "tally", "arrow"][i % 4] if i % 4 != 3 else "circle")
		var entry := hs.confirm()
		last_item = item
		t.eq(int(entry["expedition"]), n, "handoff recorded")
		var mark: Dictionary = Legacy.chain["marks"][-1] if not Legacy.chain["marks"].is_empty() else {}
		var mp: Array = mark.get("pos", [999, 0, 999])
		t.eq(Zones.area_at(Vector3(mp[0], mp[1], mp[2])), area, "the mark is chalked in the %s" % area)
		var disk := SaveIO.load_json(Legacy.path)
		t.check(disk["ok"] and (disk["data"]["history"] as Array).size() == i + 1 and disk["data"]["run"] == null, "chain on disk: %d members, no run in progress" % (i + 1))
	t.eq(Legacy.chain["history"].size(), areas.size(), "%d consecutive expeditions, each ended by a death in a different area" % areas.size())
	# the next member still starts cleanly after all that
	Legacy.begin_expedition()
	await _spawn_game()
	t.check(is_instance_valid(p) and not p.dead and p.control_enabled, "Exp %d starts cleanly after %d deaths" % [GameState.expedition_number, areas.size()])
	t.check(_tree().get_nodes_in_group("chalk_marks").size() >= mini(areas.size(), Legacy.MAX_MARKS), "every member's mark is on the floor")


# ------------------------------------------------------------------ power cuts
const PC := "user://test_powercut.json"


func _power_cuts() -> void:
	SaveIO.delete_all(PC)
	SaveIO.save_json(PC, {"counter": 1})
	SaveIO.save_json(PC, {"counter": 2})
	# 1. the cut lands while the new file is being written: a torn .tmp
	var full := SaveIO.encode({"counter": 3, "pad": "x".repeat(400)})
	for frac in [0.0, 0.1, 0.5, 0.9, 0.97]:
		var f := FileAccess.open(PC + ".tmp", FileAccess.WRITE)
		f.store_string(full.left(int(full.length() * frac)))
		f.close()
		var r := SaveIO.load_json(PC)
		t.check(r["ok"] and int(r["data"]["counter"]) == 2, "cut at %d%% of the write: the last good save (2) loads" % int(frac * 100))
		t.check(not FileAccess.file_exists(PC + ".tmp"), "the torn temp file is cleaned up")
	# 2a. the cut lands after the new file was verified but before the rename
	var f1 := FileAccess.open(PC + ".tmp", FileAccess.WRITE)
	f1.store_string(full)
	f1.close()
	var r1 := SaveIO.load_json(PC)
	t.check(r1["ok"] and r1["source"] == "tmp" and int(r1["data"]["counter"]) == 3, "cut before the rename: the newer complete save (3) wins over the old main")
	t.eq(int(SaveIO.decode(FileAccess.get_file_as_string(PC + ".bak"))["counter"]), 2, "and the old main becomes the backup")
	SaveIO.save_json(PC, {"counter": 2})
	# 2b. the cut lands after the old main was removed but before the rename
	var f2 := FileAccess.open(PC + ".tmp", FileAccess.WRITE)
	f2.store_string(full)
	f2.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PC))
	var r2 := SaveIO.load_json(PC)
	t.check(r2["ok"] and r2["source"] == "tmp" and int(r2["data"]["counter"]) == 3, "cut between remove and rename: the complete new save (3) is recovered from .tmp")
	t.check(FileAccess.file_exists(PC) and SaveIO.load_json(PC)["source"] == "main", "and it becomes the main file again")
	# 3. the cut tears the main file itself (a torn rename / bad sector): backup
	var txt := FileAccess.get_file_as_string(PC)
	var f3 := FileAccess.open(PC, FileAccess.WRITE)
	f3.store_string(txt.left(txt.length() / 3))
	f3.close()
	var r3 := SaveIO.load_json(PC)
	t.check(r3["ok"] and r3["source"] == "backup", "torn main file: the backup slot loads")
	SaveIO.delete_all(PC)


# ------------------------------------------------------------------ hostile files
func _hostile_saves() -> void:
	var path := "user://test_hostile_chain.json"
	var cases := {
		"wrong types": {"history": "oops", "marks": 5, "next_expedition": "seven", "run": "x", "world": [], "decisions": null},
		"junk entries": {"history": [1, "a", null, {"expedition": 7}], "marks": [[1, 2], {"pos": [0, 0, 0], "symbol": "x", "expedition": 7}]},
		"empty object": {},
	}
	for name_ in cases:
		SaveIO.delete_all(path)
		SaveIO.save_json(path, cases[name_])
		Legacy.use_path(path, false)
		t.check(Legacy.chain["history"] is Array and Legacy.chain["marks"] is Array and Legacy.chain["world"] is Dictionary, "%s: the chain loads with sane types" % name_)
		t.check(Legacy.next_expedition() >= Lore.FIRST_EXPEDITION, "%s: next expedition is valid (%d)" % [name_, Legacy.next_expedition()])
		t.check((Legacy.chain["history"] as Array).all(func(e): return e is Dictionary), "%s: non-dictionary history rows dropped" % name_)
		# the game scene must come up on it
		Legacy.begin_expedition()
		await _spawn_game()
		t.check(is_instance_valid(p) and p.control_enabled, "%s: the game starts on the repaired chain" % name_)
		var rows := Legacy.history_rows(true)
		t.check(rows.size() >= Lore.GHOSTS.size(), "%s: the history screen has rows to show" % name_)
	# raw garbage (not even our header)
	SaveIO.delete_all(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	var junk := PackedByteArray()
	for i in 2048:
		junk.append(rng.randi() % 256)
	f.store_buffer(junk)
	f.close()
	Legacy.use_path(path, false)
	t.check(Legacy.chain.has("chain_id") and Legacy.load_notice.contains("new chain"), "random bytes: a fresh chain and a notice, no crash")
	SaveIO.delete_all(path)
	Legacy.use_path("user://test_chain_release.json")


# ------------------------------------------------------------------ settings
func _settings_persist() -> void:
	var keys := [["audio", "music", 0.37], ["controls", "mouse_sensitivity", 0.61], ["video", "quality", 0], ["access", "subtitle_size", 2]]
	var before := {}
	for k in keys:
		before[k] = Settings.get_value(k[0], k[1])
		Settings.set_value(k[0], k[1], k[2], false)
	Settings.save_settings()
	var cf := ConfigFile.new()
	t.eq(cf.load(Settings.path), OK, "settings file is on disk")
	for k in keys:
		t.check(is_equal_approx(float(cf.get_value(k[0], k[1], -99)), float(k[2])), "%s/%s persisted (%s)" % [k[0], k[1], str(cf.get_value(k[0], k[1], "missing"))])
	for k in keys:
		Settings.set_value(k[0], k[1], before[k], false)
	Settings.save_settings()


# ------------------------------------------------------------------ leaks
func _leak_check() -> void:
	if g:
		g.queue_free()
		g = null
		await t.physics(3)
	var samples: Array = []
	for i in 14:
		Legacy.begin_expedition()
		await _spawn_game()
		await t.physics(20)
		g.queue_free()
		g = null
		await t.physics(4)
		Legacy.end_expedition("gave_up", Vector3.ZERO, "shaft")
		Legacy.commit_handoff("", "", "", "")
		samples.append([Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), Performance.get_monitor(Performance.MEMORY_STATIC)])
	var a: Array = samples[3]
	var b: Array = samples[-1]
	print("  leak samples (objects, nodes, orphans, static MB): ", samples.map(func(s): return [int(s[0]), int(s[1]), int(s[2]), snappedf(s[3] / 1048576.0, 0.1)]))
	t.check(b[1] - a[1] <= 5, "no node growth over 10 more expeditions (%d -> %d)" % [a[1], b[1]])
	t.check(b[2] - a[2] <= 2, "no orphan nodes pile up (%d -> %d)" % [a[2], b[2]])
	t.check(b[0] - a[0] < 400, "object count stays flat (%d -> %d)" % [a[0], b[0]])
	t.check((b[3] - a[3]) / 1048576.0 < 24.0, "static memory stays flat (%.1f -> %.1f MB)" % [a[3] / 1048576.0, b[3] / 1048576.0])


# ------------------------------------------------------------------ network
func _no_network_code() -> void:
	var banned := ["HTTPRequest", "HTTPClient", "StreamPeerTCP", "PacketPeerUDP", "TCPServer", "UDPServer",
		"WebSocketPeer", "ENetMultiplayerPeer", "WebRTC", "OS.shell_open", "JavaScriptBridge", "IP.resolve"]
	var hits: Array = []
	for f in _files("res://", [".gd", ".tscn", ".tres"]):
		if f.begins_with("res://tests/") or f.begins_with("res://tools/") or f.begins_with("res://addons/"):
			continue
		var s := FileAccess.get_file_as_string(f)
		for b in banned:
			if s.contains(b):
				hits.append("%s: %s" % [f, b])
	t.check(hits.is_empty(), "no networking API anywhere in the game code %s" % str(hits))


func _files(dir: String, exts: Array) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		for e in exts:
			if f.ends_with(e):
				out.append(dir.path_join(f))
	for sub in d.get_directories():
		if sub.begins_with("."):
			continue
		out.append_array(_files(dir.path_join(sub), exts))
	return out
