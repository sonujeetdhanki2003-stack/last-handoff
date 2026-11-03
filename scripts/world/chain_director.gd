class_name ChainDirector
extends Node3D
## Puts the chain into the world at the start of an expedition:
##   * the newest handoff crate (item + note) by the lift,
##   * older handoff notes pinned on the shaft wall, plus the ghost expeditions' notes,
##   * chalk marks where earlier members died or left (ghosts + the chain, capped),
##   * remains: vital items dropped where a member fell,
##   * the research drive back on the bench (unless it's been wiped / handed off).

const CRATE_POS := Vector3(-3.0, 0.0, 4.65)
const NOTE_WALL_X := -3.83
const DEC := "res://assets/decals/%s.png"

var level: Node3D
var spawned := {"crate_item": null, "crate_note": null, "notes": [], "marks": [], "remains": []}


func setup(lvl: Node3D) -> void:
	level = lvl
	name = "ChainDirector"
	_crate()
	_notes()
	_marks()
	_remains()
	_drive()


func _crate() -> void:
	var lh: Dictionary = Legacy.chain.get("last_handoff", {})
	var exp_n := int(lh.get("expedition", 6))
	var who := str(lh.get("member", "Dana Haas"))
	var item := str(lh.get("item", "battery"))
	var msg := str(lh.get("message", ""))
	var custom := str(lh.get("custom", ""))
	if lh.is_empty():
		# first run of a chain: Expedition 6's crate
		var g: Dictionary = Lore.GHOSTS[6]
		item = g["item"]
		msg = g["message"]
		who = g["member"]
		exp_n = 6
	var root := Node3D.new()
	root.name = "HandoffCrateLatest"
	root.position = CRATE_POS
	root.rotation.y = PI / 2
	add_child(root)
	var vis: Node3D = load("res://assets/props/wooden_military_crate/wooden_military_crate_1k.gltf").instantiate()
	for c in vis.get_children():
		if c.name.contains("lid"):
			c.visible = false
	root.add_child(vis)
	var body := StaticBody3D.new()
	body.collision_layer = 8
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.95, 0.5, 0.55)
	cs.shape = bs
	cs.position.y = 0.25
	body.add_child(cs)
	root.add_child(body)
	var lbl := Label3D.new()
	lbl.text = "EXP-%d" % exp_n
	lbl.font = load("res://assets/fonts/PermanentMarker-Regular.ttf")
	lbl.font_size = 64
	lbl.pixel_size = 0.0035
	lbl.modulate = Color(0.93, 0.92, 0.86, 0.85)
	lbl.double_sided = false
	lbl.position = Vector3(0, 0.27, 0.285)
	root.add_child(lbl)
	if item != "" and ItemDB.exists(item):
		var pid := "handoff_e%d_item" % exp_n
		if not GameState.get_world(pid).get("taken", false):
			var p := Pickup.new()
			p.item_id = item
			p.persist_id = pid
			p.name = "HandoffItem"
			add_child(p)
			p.global_position = root.global_position + Vector3(0.15, 0.45, -0.05)
			spawned["crate_item"] = p
	var note_text := _note_body(exp_n, who, msg, custom)
	var n := TextNote.new()
	n.name = "HandoffCrateNote"
	n.title = "EXPEDITION %d  -  HANDOFF" % exp_n
	n.body = note_text
	n.verb = "Read the handoff note"
	add_child(n)
	n.global_position = root.global_position + Vector3(-0.1, 0.5, 0.12)
	spawned["crate_note"] = n


static func _note_body(exp_n: int, who: String, msg: String, custom: String) -> String:
	var t := ""
	if msg != "":
		t += msg + "\n\n"
	if custom != "":
		t += "[i]" + custom + "[/i]\n\n"
	if t == "":
		t = "[i](No message. Just the item.)[/i]\n\n"
	return t + "- %s, Expedition %d" % [who, exp_n]


func _notes() -> void:
	# older handoffs from the chain, pinned on the shaft's west wall
	var notes: Array = Legacy.chain.get("notes", [])
	var k := 0
	for i in range(notes.size() - 1, -1, -1):
		var nd: Dictionary = notes[i]
		var pos := Vector3(NOTE_WALL_X, 1.75 + 0.6 * (k / 4), 4.5 + 0.72 * (k % 4))
		_wall_note(pos, Vector3(1, 0, 0), "EXPEDITION %d" % int(nd.get("expedition", 0)),
			_note_body(int(nd.get("expedition", 0)), str(nd.get("member", "")), str(nd.get("message", "")), str(nd.get("custom", ""))), "WallNote_%d" % k)
		k += 1
	# the ghost expeditions' notes, where they left them
	for g in Lore.GHOSTS:
		if g["note"] == null:
			continue
		var p: Array = g["note"][0]
		var nn: Array = g["note"][1]
		_wall_note(Vector3(p[0], p[1], p[2]), Vector3(nn[0], nn[1], nn[2]), "EXPEDITION %d" % g["expedition"],
			_note_body(g["expedition"], g["member"], g["message"], ""), "GhostNote_%d" % g["expedition"])


func _wall_note(pos: Vector3, normal: Vector3, title: String, body: String, nname: String) -> void:
	var d := Decal.new()
	d.name = nname + "_Paper"
	d.texture_albedo = load(DEC % "handoff_note")
	d.size = Vector3(0.32, 0.12, 0.42)
	var y := normal.normalized()
	var z := Vector3.DOWN
	d.transform = Transform3D(Basis(y.cross(z), y, z), pos)
	d.cull_mask = 0xFFFFF & ~2
	add_child(d)
	var n := TextNote.new()
	n.name = nname
	n.title = title
	n.body = body
	n.box_size = Vector3(0.36, 0.46, 0.08) if absf(normal.x) < 0.5 else Vector3(0.08, 0.46, 0.36)
	add_child(n)
	n.global_position = pos + normal * 0.03
	spawned["notes"].append(n)


func _marks() -> void:
	var all: Array = []
	for g in Lore.GHOSTS:
		all.append({"expedition": g["expedition"], "symbol": g["symbol"], "pos": [g["mark"][0], 0.0, g["mark"][1]], "ghost": true})
	for m in Legacy.chain.get("marks", []):
		all.append(m)
	for m in all:
		var p: Array = m["pos"]
		var mk := make_mark(str(m["symbol"]), int(m["expedition"]))
		add_child(mk)
		mk.global_position = Vector3(float(p[0]), float(p[1]) + 0.02, float(p[2]))
		spawned["marks"].append(mk)


static func make_mark(symbol: String, exp_n: int) -> Node3D:
	var root := Node3D.new()
	root.name = "ChalkMark_%d" % exp_n
	root.add_to_group("chalk_marks")
	root.set_meta("symbol", symbol)
	root.set_meta("expedition", exp_n)
	var d := Decal.new()
	d.texture_albedo = load(DEC % ("mark_" + symbol))
	d.size = Vector3(0.9, 0.5, 0.9)
	d.rotation.y = float(hash(exp_n) % 628) / 100.0
	d.modulate = Color(1, 1, 1, 0.92)
	d.cull_mask = 0xFFFFF & ~2
	d.distance_fade_enabled = true
	d.distance_fade_begin = 24.0
	d.distance_fade_length = 6.0
	root.add_child(d)
	var l := Label3D.new()
	l.text = str(exp_n)
	l.font = load("res://assets/fonts/PermanentMarker-Regular.ttf")
	l.font_size = 80
	l.pixel_size = 0.003
	l.modulate = Color(0.93, 0.92, 0.86, 0.8)
	l.rotation.x = -PI / 2
	l.position = Vector3(0.38, 0.015, 0.38)
	l.double_sided = false
	root.add_child(l)
	return root


func _remains() -> void:
	for r in Legacy.chain.get("remains", []):
		var id := str(r.get("id", ""))
		if GameState.get_world(id).get("taken", false):
			continue
		var p := Pickup.new()
		p.item_id = str(r["item"])
		p.persist_id = id
		p.name = "Remains_" + id
		add_child(p)
		var pos: Array = r["pos"]
		p.global_position = Vector3(float(pos[0]), float(pos[1]) + 0.05, float(pos[2]))
		spawned["remains"].append(p)


## Varga's drive returns to the bench every descent ("it always does"), unless it was
## wiped, or a member handed it off in the crate or dropped it where they fell.
func _drive() -> void:
	var bench := level.get_node_or_null("Interactables/ResearchDrive")
	if bench == null:
		return
	var elsewhere := false
	var ci: Variant = spawned["crate_item"]
	if ci != null and (ci as Pickup).item_id == "research_drive":
		elsewhere = true
	for r in spawned["remains"]:
		if (r as Pickup).item_id == "research_drive":
			elsewhere = true
	if Legacy.decision("drive") == "destroyed" or elsewhere or GameState.inventory.has("research_drive"):
		bench.queue_free()
