class_name DecisionPoint
extends Interactable
## One of the three persistent choices. Interact opens a two-way choice; the
## answer is saved to the chain at once and sticks for every later expedition.
##   power_route  (crawlspace junction):  freezer | lift
##   drive        (Varga's terminal, Lab 3, needs the drive in hand): kept | destroyed
##   archive      (vault door control):   opened | sealed

@export var decision_id := "power_route"
@export var requires_item := ""
@export var requires_item_text := ""
@export var visual := "junction"        ## junction | terminal | vault_panel

var _lamp: StandardMaterial3D
var _label: Label3D


func _ready() -> void:
	solid = true
	super._ready()
	_build()
	Legacy.decision_made.connect(func(id, _c):
		if id == decision_id:
			_refresh())
	_refresh()


func _build() -> void:
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	match visual:
		"terminal":
			bm.size = Vector3(0.5, 0.42, 0.3)
		"vault_panel":
			bm.size = Vector3(0.36, 0.5, 0.12)
		_:
			bm.size = Vector3(0.7, 0.9, 0.22)
	body.mesh = bm
	body.material_override = ArtMats.local("rusty", Color(0.75, 0.75, 0.72))
	add_child(body)
	_lamp = StandardMaterial3D.new()
	_lamp.emission_enabled = true
	var lamp := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(bm.size.x * 0.6, 0.08 if visual != "terminal" else 0.22, 0.02)
	lamp.mesh = lm
	lamp.material_override = _lamp
	lamp.position = Vector3(0, bm.size.y * 0.25, bm.size.z / 2.0 + 0.005)
	add_child(lamp)
	_label = Label3D.new()
	_label.font_size = 28
	_label.pixel_size = 0.003
	_label.double_sided = false
	_label.position = Vector3(0, -bm.size.y * 0.22, bm.size.z / 2.0 + 0.01)
	_label.modulate = Color(0.85, 0.85, 0.8)
	add_child(_label)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	add_child(cs)


func _refresh() -> void:
	var c := Legacy.decision(decision_id)
	var col := Color(1.0, 0.55, 0.1) if c == "" else (Color(0.3, 0.7, 1.0) if c in ["freezer", "sealed", "destroyed"] else Color(0.3, 1.0, 0.45))
	_lamp.albedo_color = col * 0.3
	_lamp.emission = col
	_lamp.emission_energy_multiplier = 2.0
	var titles := {"power_route": "JUNCTION B2-W", "drive": "VARGA / LAB 3", "archive": "VAULT"}
	_label.text = str(titles.get(decision_id, decision_id)) + ("" if c == "" else "\n" + c.to_upper())


func get_prompt(_a: Node) -> String:
	var c := Legacy.decision(decision_id)
	if c != "":
		return Lore.decision_label(decision_id, c)
	match decision_id:
		"power_route":
			return "Route the last circuit"
		"drive":
			return "Varga's terminal"
		"archive":
			return "Vault door control"
	return "Decide"


func can_interact(a: Node) -> bool:
	if Legacy.decision(decision_id) != "":
		return false
	if requires_item != "" and not GameState.inventory.has(requires_item):
		return false
	return super.can_interact(a)


func get_refusal(a: Node) -> String:
	var c := Legacy.decision(decision_id)
	if c != "":
		return "Done. Decided by an earlier member" if int(Legacy.chain["decisions"][decision_id].get("expedition", -1)) != GameState.expedition_number else "Done"
	if requires_item != "" and not GameState.inventory.has(requires_item):
		return requires_item_text
	return super.get_refusal(a)


func choice_text() -> Dictionary:
	match decision_id:
		"power_route":
			return {"title": "THE LAST CIRCUIT",
				"body": "One working feed is left at this junction and it can only go one way. The breaker is old: once thrown, it won't move again.\n\n[b]FREEZER[/b]: keep Lab 3 cold. Varga said the cold slows it down.\n[b]LIFT & RELAY LINE[/b]: power the cage motor and the old relay cable that runs up the shaft.",
				"options": [["freezer", "Power the freezer"], ["lift", "Power the lift + relay line"]]}
		"drive":
			return {"title": "VARGA'S DRIVE",
				"body": "Varga's terminal can read the drive, or wipe it. Forty days of data on H-7. The relay sent you down for this.\n\n[b]KEEP[/b]: it's the only proof of what's down here.\n[b]WIPE[/b]: if it can't be studied, maybe it can be starved.\n\nWhatever you choose, the next member inherits it.",
				"options": [["kept", "Keep the drive"], ["destroyed", "Wipe the drive"]]}
		"archive":
			return {"title": "THE ARCHIVE VAULT",
				"body": "Behind this door: every relay roster since the station opened, and the transmitter that talks to the surface. The panel will open it, or fuse the bolts for good.\n\n[b]OPEN[/b]: the records and the transmitter.\n[b]WELD IT SHUT[/b]: nothing in, nothing out. Ever.",
				"options": [["opened", "Open the vault"], ["sealed", "Weld it shut"]]}
	return {"title": decision_id, "body": "", "options": []}


func interact(actor: Node) -> void:
	if not can_interact(actor):
		return
	var c := choice_text()
	Events.open_choice.emit(c["title"], c["body"], c["options"], func(choice: String): decide(choice))
	super.interact(actor)


func decide(choice: String) -> void:
	if not Legacy.decide(decision_id, choice):
		return
	match decision_id + ":" + choice:
		"drive:destroyed":
			GameState.inventory.remove("research_drive")
			Events.toast.emit("The drive is wiped. Forty days of data, gone.")
		"drive:kept":
			Events.toast.emit("You keep the drive.")
		"power_route:freezer":
			GameState.difficulty = 0.85
			for k in get_tree().get_nodes_in_group("keeper"):
				k.set("speed_scale", 0.85)
			Events.toast.emit("The freezer shudders on. Somewhere, something slows down.")
		"power_route:lift":
			Events.toast.emit("The lift motor and the relay line hum awake.")
		"archive:opened":
			var d := get_parent().get_node_or_null("DoorVault") as Door
			if d:
				d.unlock_code()
				d.open()
			Events.toast.emit("The vault bolts draw back.")
		"archive:sealed":
			var d2 := get_parent().get_node_or_null("DoorVault") as Door
			if d2:
				d2.weld()
			Events.toast.emit("The bolts fuse. The vault is sealed for good.")
	_refresh()
