class_name Lore
extends RefCounted
## Authored content for the handoff chain: ghost expeditions (so the first run
## doesn't start in an empty world), member names, handoff templates, chalk
## symbols, depth names, decisions and endings.

## The relay before the player. Expedition 0 is Mara; 6 wrote "6 BEFORE ME".
## pos/yaw place their chalk mark, note = where their wall note hangs (wall, normal).
const GHOSTS := [
	{"expedition": 0, "member": "Mara Sorensen", "depth": "storage", "end": "unknown",
		"item": "keycard_blue", "message": "Leave something for the next one. That's the only rule that works down here.",
		"symbol": "tally", "mark": [-6.3, -16.4], "note": null},
	{"expedition": 1, "member": "Tobi Achebe", "depth": "corridor", "end": "died",
		"item": "battery", "message": "DON'T RUN. IT HEARS RUNNING.",
		"symbol": "x", "mark": [0.6, -11.6], "note": [[-1.58, 1.5, -9.0], [1, 0, 0]]},
	{"expedition": 2, "member": "\"Member four\"", "depth": "shaft", "end": "gave_up",
		"item": "", "message": "I'm sorry. I used everything. Count the marks on the wall. Add yours.",
		"symbol": "tally", "mark": [-3.0, 1.6], "note": null},
	{"expedition": 3, "member": "Yuki Sato", "depth": "generator", "end": "died",
		"item": "fuse", "message": "Hold the crank. Don't let go early. It comes when the lights come on.",
		"symbol": "arrow", "mark": [-3.2, -6.2], "note": [[-3.4, 1.5, -1.02], [0, 0, -1]]},
	{"expedition": 4, "member": "Pia Lindgren", "depth": "security", "end": "extracted",
		"item": "battery", "message": "THE CODE CHANGES EVERY TIME. THE LOCKERS SAVED ME.",
		"symbol": "circle", "mark": [6.4, -5.4], "note": [[1.62, 1.55, -10.0], [1, 0, 0]]},
	{"expedition": 5, "member": "Rui Duarte", "depth": "lab", "end": "died",
		"item": "", "message": "WE WERE NEVER THE FIRST",
		"symbol": "eye", "mark": [0.4, -20.7], "note": null},
	{"expedition": 6, "member": "Dana Haas", "depth": "storage", "end": "died",
		"item": "battery", "message": "6 before me. Shine the light in its face, it hates that. It drinks the battery though.",
		"symbol": "x", "mark": [-2.6, -15.0], "note": null},
]

const FIRST_EXPEDITION := 7

const FIRST := ["Asha", "Dev", "Ines", "Tomas", "Kofi", "Lena", "Ravi", "Noor", "Pavel", "Mei",
	"Arjun", "Sana", "Elif", "Jonah", "Priya", "Matteo", "Yusuf", "Hana", "Oskar", "Leila",
	"Viktor", "Zara", "Imran", "Freya", "Nikhil", "Aiko", "Bruno", "Kavya", "Emil", "Tara"]
const LAST := ["Kerr", "Mehta", "Novak", "Achterberg", "Rao", "Lindahl", "Okonjo", "Ferreira",
	"Brennan", "Kapoor", "Dalca", "Moreno", "Halvorsen", "Iqbal", "Varela", "Strand",
	"Nair", "Kowal", "Duval", "Banerjee", "Aho", "Castell", "Imai", "Petrov", "Sorel", "Mbeki", "Quinn", "Tanaka", "Ozturk", "Haddad"]

## Message templates on the handoff screen.
const TEMPLATES := [
	"It hunts by sound. Crouch.",
	"Light drives it back. Not for long.",
	"Hide in the lockers. Don't let it see you go in.",
	"The generator is fixed. Keep it running.",
	"The code changes every time. Check the security room.",
	"Lab 3 is open. The drive is on the bench.",
	"Watch the floor near the puddle. Live wires.",
	"No light in the crawlspace. Gas.",
	"I'm sorry. I used everything.",
	"Keep going. Add your mark.",
]

## Chalk symbols: id -> [label, meaning]
const SYMBOLS := {
	"x": ["X", "Danger. Someone died here."],
	"arrow": ["Arrow", "This way."],
	"circle": ["Circle", "Safe. Hide here."],
	"eye": ["Eye", "It watches from here."],
	"tally": ["Tally", "I was here."],
	"bolt": ["Bolt", "Power / hazard."],
}

## Depth: area id -> [rank, name]
const DEPTH := {
	"shaft": [0, "Entrance shaft"],
	"corridor": [1, "B2 corridor"],
	"generator": [2, "Generator room"],
	"security": [2, "Security office"],
	"storage": [3, "Storage"],
	"lab": [4, "Lab 3"],
	"archive": [5, "Archive"],
	"crawlspace": [5, "Generator crawlspace"],
	"deep": [6, "Expedition 0 camp"],
}

const END_LABELS := {
	"died": "Taken in the dark",
	"injured": "Died of injuries",
	"extracted": "Rode the lift up",
	"gave_up": "Gave up",
	"unknown": "Did not return",
	"seal": "Sealed the station and stayed",
	"broadcast": "Sent the data up",
	"break": "Broke the chain",
}

## The three persistent decisions.
const DECISIONS := {
	"power_route": {"title": "THE LAST CIRCUIT", "where": "Crawlspace junction",
		"options": {"freezer": "Powered the Lab 3 freezer", "lift": "Powered the lift and relay line"}},
	"drive": {"title": "VARGA'S DRIVE", "where": "Lab 3",
		"options": {"kept": "Kept Varga's drive", "destroyed": "Wiped Varga's drive"}},
	"archive": {"title": "THE ARCHIVE VAULT", "where": "Archive",
		"options": {"opened": "Opened the archive vault", "sealed": "Welded the archive vault shut"}},
}

const MARA_TAPES := ["tape_mara", "tape_mara2", "tape_mara3", "tape_mara4"]

const ENDINGS := {
	"seal": {"title": "SEAL", "sub": "The last keeper",
		"text": "You cut the lift cable from below and listen to the cage fall. The freezer hums. The drive is ash. Up top, they will wait for a handoff that never comes, and in time they will stop sending people.\n\nDown here, someone has to keep the lights off and keep it company. Varga knew that. Now you do.\n\nYou turn off your lamp and sit with your back to the crate."},
	"broadcast": {"title": "BROADCAST", "sub": "Everyone will know",
		"text": "Every light in Halden Deep comes on at once. The relay line sings up the shaft with forty days of Varga's data, and for eleven seconds the station is brighter than it has been in years.\n\nIt heard all of it.\n\nThe upload finished. You did not. Somewhere above, a screen fills with numbers and a count that starts at zero and does not stop."},
	"break": {"title": "BREAK THE CHAIN", "sub": "Leave nothing",
		"text": "You leave the crate empty. No note. No mark. You ride up in the dark with nothing in your hands, and the cage arrives with nobody waiting for it.\n\nMara was right. It never needed the drive, or the power. It needed the count. Every crate we stocked was a reason for the next one to come down.\n\nThe relay ends with you. Nobody else goes down."},
}


## Deterministic per chain. First names and surnames are dealt from per-chain
## shuffled decks, so no two members of a chain share a surname (or a first name)
## until the decks run out (30 members).
static func member_name(chain_id: int, expedition: int) -> String:
	var i := maxi(0, expedition - FIRST_EXPEDITION)
	var firsts := _deck(FIRST, chain_id * 31 + 7)
	var lasts := _deck(LAST, chain_id * 17 + 3)
	var lap := i / lasts.size()
	return "%s %s" % [firsts[(i + lap) % firsts.size()], lasts[i % lasts.size()]]


static func _deck(src: Array, seed_: int) -> Array:
	var d := src.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	for k in range(d.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp: Variant = d[k]
		d[k] = d[j]
		d[j] = tmp
	return d


static func depth_rank(area: String) -> int:
	return int(DEPTH.get(area, [-1, ""])[0])


static func depth_name(area: String) -> String:
	return str(DEPTH.get(area, [0, "Unknown"])[1])


static func end_label(end: String) -> String:
	return str(END_LABELS.get(end, end))


static func decision_label(id: String, choice: String) -> String:
	return str(DECISIONS.get(id, {}).get("options", {}).get(choice, "%s: %s" % [id, choice]))
