class_name AudioLogs
extends RefCounted
## The station's tapes: who recorded them, and the transcript shown while they play.
## Audio lives in res://audio/logs/<id>.ogg (voiced, run through a cassette chain).

const LOGS := {
	"tape_okafor": {"speaker": "Rafe Okafor, Station Security", "date": "14 March", "where": "Security office",
		"text": "Security log, fourteenth of March. Okafor. ... The lift is down to one cage. One at a time, one person per trip, that's the order. Doctor Varga wants Lab 3 sealed and the generator kept cold, so nobody touches the crank. I've rotated the lab code again. I know. I know. Just read the memo and burn it. Leave everything. Bags, samples, all of it. If it's not in your hands when the cage comes, it stays down here. ... Whatever's in that lab, it hears the power come on. So we go up in the dark."},
	"tape_brandt": {"speaker": "Joel Brandt, Maintenance", "date": "11 March", "where": "Generator room",
		"text": "Gen-two maintenance, Brandt. Note for whoever pulls the next shift. Hold the crank until she catches. About four seconds. Don't let go early, she floods. Corridor breaker is on the west wall. If the corridor lights stutter, it's not the fuses, it's the breaker, so check that first. And the fan in here has been spinning on its own when the power's off. Which it shouldn't. ... I logged it. Nobody answered."},
	"tape_varga1": {"speaker": "Dr. Ilse Varga, Lab 3", "date": "2 March", "where": "Lab 3",
		"text": "Lab 3, day forty. Varga. Specimen H-7 reacts to current. Every time the generator runs, the readings climb, and the tank fluid turns toward the door. Toward whoever is standing in it. I've started to think the tank isn't where it is. The tank is just where it listens from. Everything is on the research drive. If we lose the station, the drive is the only thing that matters."},
	"tape_varga2": {"speaker": "Dr. Ilse Varga, Lab 3", "date": "14 March", "where": "Lab 3, by the broken tank",
		"text": "If anyone finds this. ... We thought we were studying it. It was keeping count. Every one of us who came down. Every light we turned on. It remembers all of it. There are only three ways out of this. Seal the station and let it starve in the dark. Send the data up and let everyone know. Or someone stays. Someone keeps the lights off and keeps it company. ... I couldn't choose. Maybe the next one will."},
	"tape_mara": {"speaker": "Mara, Expedition 0", "date": "Expedition 0, day 2", "where": "Storage, by the sleeping bag",
		"text": "Expedition zero, day two. It's Mara. ... They told us we were the first relay. We're not. There's chalk on the walls down here that's older than us. Tally marks. Someone's sleeping bag. I'm leaving the keycard and a spare cell in the crate by the lift. Whoever comes next, ration the light. It listens when the power is on. ... Leave something for the next one. That's the only rule that works down here."},
	"tape_mara2": {"speaker": "Mara, Expedition 0", "date": "Expedition 0, day 4", "where": "Generator crawlspace",
		"text": "Expedition zero, day four. Mara. ... There's a crawlspace behind the generator. I pried the grate. There's a camp at the end of it, and it isn't ours. Their crates are full. Notes. Batteries. Names. ... The tally on that wall goes back further than the station. Halden wasn't built down here. It was built on top of something. ... I'm going to count them."},
	"tape_mara3": {"speaker": "Mara, Expedition 0", "date": "Expedition 0, day 6", "where": "Archive",
		"text": "Day six. I got into the records room. The relay isn't new. Every few years someone up top opens it again. One name on the roster at a time, one per cage. And every time, the count goes up by one. ... Varga's sheet says it counted seven peaks when they were six. I think I know who the seventh is. It's whoever comes down next."},
	"tape_mara4": {"speaker": "Mara, Expedition 0", "date": "Expedition 0, last day", "where": "The old camp, past the gas",
		"text": "Last tape. I understand it now. It doesn't want the drive, and it doesn't want the power. It wants the next one. Every crate we stock, every note, every mark on the wall, is a promise that somebody else is coming down. That's what it eats. The count. ... So this is my real handoff. Don't leave one. Leave the crate empty, ride up with nothing in your hands, and don't let them send anyone after you. Break the chain. ... I couldn't. I left the keycard anyway. I'm sorry."},
	"tape_relay": {"speaker": "Unknown, older relay", "date": "unknown", "where": "Entrance shaft, old crates",
		"text": "Relay two. Member four. ... The lift only takes one. If you're hearing this, I didn't go back up. My crate is the one by the west wall. It's empty. I'm sorry. I used everything. Count the marks on the wall. Add yours. Then keep going."},
}


static func has(id: String) -> bool:
	return LOGS.has(id)


static func title(id: String) -> String:
	var d: Dictionary = LOGS.get(id, {})
	return "TAPE  -  %s" % d.get("speaker", id)


static func transcript(id: String) -> String:
	var d: Dictionary = LOGS.get(id, {})
	var body := "[i]%s  /  %s[/i]\n\n" % [d.get("date", ""), d.get("where", "")]
	return body + str(d.get("text", "")).replace(" ... ", "\n\n")


static func stream_path(id: String) -> String:
	return "res://audio/logs/%s.ogg" % id


static func found_count() -> int:
	var n := 0
	for k in LOGS:
		if GameState.get_flag("log_" + k):
			n += 1
	return n
