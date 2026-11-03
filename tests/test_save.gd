extends TestCase
## Save / load: atomic writes, the backup slot, corruption handling, run snapshots.

const PATH := "user://test_saveio.json"


func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)


func _write_raw(p: String, text: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read_raw(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func run() -> void:
	SaveIO.delete_all(PATH)
	var data := {"a": 1, "list": [1, 2, 3], "nested": {"name": "Asha Kerr", "pos": [1.5, 0.0, -3.25]}}
	t.eq(SaveIO.save_json(PATH, data), OK, "save_json writes")
	t.check(FileAccess.file_exists(PATH), "main file exists")
	t.check(not FileAccess.file_exists(PATH + ".tmp"), "no temp file left behind (atomic rename)")
	var r := SaveIO.load_json(PATH)
	t.check(r["ok"] and r["source"] == "main", "loads from the main file")
	t.eq(int(r["data"]["a"]), 1, "value round-trips")
	t.eq(str(r["data"]["nested"]["name"]), "Asha Kerr", "nested value round-trips")
	t.eq(_read_raw(PATH).split("\n")[0].contains("md5"), true, "file carries a checksum header")

	# second save: the previous good file becomes the backup slot
	data["a"] = 2
	SaveIO.save_json(PATH, data)
	t.check(FileAccess.file_exists(PATH + ".bak"), "backup slot written on the second save")
	t.eq(int(SaveIO.decode(_read_raw(PATH + ".bak"))["a"]), 1, "backup holds the previous save")
	t.eq(int(SaveIO.load_json(PATH)["data"]["a"]), 2, "main holds the newest save")

	# corruption: garbage in the main file -> backup used, damaged file kept aside
	_write_raw(PATH, "{this is not json at all")
	r = SaveIO.load_json(PATH)
	t.check(r["ok"] and r["source"] == "backup", "corrupt main file falls back to the backup")
	t.eq(int(r["data"]["a"]), 1, "backup data recovered")
	t.check(FileAccess.file_exists(PATH + ".corrupt"), "damaged file moved aside as .corrupt")

	# truncated write (power loss mid-write)
	SaveIO.save_json(PATH, data)
	SaveIO.save_json(PATH, data)
	var full := _read_raw(PATH)
	_write_raw(PATH, full.substr(0, full.length() / 2))
	r = SaveIO.load_json(PATH)
	t.check(r["ok"] and r["source"] == "backup", "truncated file detected, backup used")
	t.check(str(r["error"]) != "", "truncation reported (%s)" % r["error"])

	# bit rot: same length, one character changed -> checksum catches it
	SaveIO.save_json(PATH, data)
	SaveIO.save_json(PATH, data)
	var good := _read_raw(PATH)
	var bad := good.replace("Asha Kerr", "Asha Kerx")
	_write_raw(PATH, bad)
	r = SaveIO.load_json(PATH)
	t.eq(r["source"], "backup", "one flipped character fails the checksum")

	# both main and backup corrupt -> clean failure, no crash
	_write_raw(PATH, "garbage")
	_write_raw(PATH + ".bak", "")
	r = SaveIO.load_json(PATH)
	t.check(not r["ok"], "nothing usable -> load reports failure instead of crashing")
	_write_raw(PATH, "")
	r = SaveIO.load_json(PATH)
	t.check(not r["ok"] and r["data"].is_empty(), "empty file handled")
	SaveIO.delete_all(PATH)
	t.check(not SaveIO.load_json(PATH)["ok"] and SaveIO.last_status == "none", "missing file = no save (new chain)")

	# --- Legacy on top of SaveIO --------------------------------------------------
	var lp := "user://test_legacy_save.json"
	Legacy.use_path(lp)
	t.eq(Legacy.next_expedition(), Lore.FIRST_EXPEDITION, "a new chain starts at expedition %d (after the ghosts)" % Lore.FIRST_EXPEDITION)
	Legacy.begin_expedition()
	t.check(GameState.chain_mode, "chain expedition flagged")
	t.check(GameState.member_name != "", "new member has a name: " + GameState.member_name)
	GameState.inventory.add("fuse")
	GameState.set_world("door_shaft", {"open": true})
	Legacy.save_run({"pos": [1.0, 0.05, -3.0], "yaw": 90.0, "vitals": {"health": 42.0, "stamina": 0.5}})
	var cid := int(Legacy.chain["chain_id"])
	# simulate quitting the game and launching it again
	GameState.new_expedition(1)
	Legacy.load_chain()
	t.eq(int(Legacy.chain["chain_id"]), cid, "chain survives a reload")
	t.check(Legacy.has_run_in_progress(), "the unfinished run is offered as Continue")
	t.check(Legacy.resume_expedition(), "resume works")
	t.check(GameState.inventory.has("fuse"), "inventory restored on Continue")
	t.check(GameState.get_world("door_shaft").get("open", false), "world state restored on Continue")
	t.eq(float(GameState.resume_player["vitals"]["health"]), 42.0, "player vitals restored on Continue")

	# a corrupted chain file is repaired from the backup on launch
	Legacy.save()
	Legacy.save()
	_write_raw(lp, "\u0000\u0000\u0000 broken")
	Legacy.load_chain()
	t.eq(int(Legacy.chain["chain_id"]), cid, "corrupt chain file restored from the backup")
	t.check(Legacy.load_notice.contains("Restored"), "player is told the save was repaired")
	_write_raw(lp, "x")
	_write_raw(lp + ".bak", "y")
	Legacy.load_chain()
	t.check(Legacy.chain["history"].is_empty() and Legacy.load_notice.contains("new chain"), "unrecoverable save -> fresh chain + notice, no crash")
	SaveIO.delete_all(lp)
