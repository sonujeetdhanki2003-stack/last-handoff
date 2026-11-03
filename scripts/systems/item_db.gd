class_name ItemDB
extends RefCounted
## Static item definitions. `stack` = max per slot. `kind` drives Use behaviour.

const ITEMS := {
	"battery": {
		"name": "Battery Cell", "stack": 4, "kind": "battery", "color": Color(0.95, 0.72, 0.2),
		"desc": "Rechargeable 9 V cell. Swaps into the flashlight (R).",
	},
	"fuse": {
		"name": "Ceramic Fuse", "stack": 3, "kind": "part", "color": Color(0.85, 0.85, 0.8),
		"desc": "30 A cartridge fuse. The corridor fuse panel takes three.",
	},
	"keycard_blue": {
		"name": "Blue Keycard", "stack": 1, "kind": "key", "color": Color(0.25, 0.55, 1.0),
		"desc": "Halden Deep, Storage clearance. The photo is scratched out.",
	},
	"note_code": {
		"name": "Security Memo", "stack": 1, "kind": "document", "color": Color(0.9, 0.88, 0.78),
		"desc": "A memo from the security office.",
	},
	"note_handoff": {
		"name": "Expedition Note", "stack": 1, "kind": "document", "color": Color(0.95, 0.6, 0.35),
		"desc": "Left in the handoff crate by the last expedition.",
	},
	"keycard_red": {
		"name": "Archive Keycard", "stack": 1, "kind": "key", "color": Color(0.95, 0.25, 0.2),
		"desc": "Red card on Varga's lanyard. ARCHIVE / RECORDS. Opens the door across from the fuse panel.",
	},
	"crowbar": {
		"name": "Crowbar", "stack": 1, "kind": "key", "color": Color(0.75, 0.2, 0.15),
		"desc": "Heavy, bent at the tip. Enough to pry a bolted vent grate.",
	},
	"medkit": {
		"name": "Field Dressing", "stack": 2, "kind": "medkit", "color": Color(0.9, 0.9, 0.9),
		"desc": "Gauze, tape and a morphine stick. Use it (U) to treat an injury.",
	},
	"research_drive": {
		"name": "Research Drive", "stack": 1, "kind": "key", "color": Color(0.4, 1.0, 0.75),
		"desc": "Encrypted drive labelled LAB-3 / CONTAINMENT. This is what they sent you for.",
	},
}


static func exists(id: String) -> bool:
	return ITEMS.has(id)


static func get_def(id: String) -> Dictionary:
	return ITEMS.get(id, {"name": id, "stack": 1, "kind": "misc", "color": Color.WHITE, "desc": ""})


static func display_name(id: String) -> String:
	return get_def(id)["name"]


static func max_stack(id: String) -> int:
	return int(get_def(id)["stack"])
