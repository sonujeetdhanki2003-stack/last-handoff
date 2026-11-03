class_name Notes
extends RefCounted
## Readable documents. Text that depends on the expedition (codes) is filled here.

static func get_note(id: String) -> Dictionary:
	match id:
		"note_code":
			if not GameState.old_codes.is_empty():
				var crossed := ""
				for c in GameState.old_codes:
					crossed += "[s]%s[/s]   " % c
				return {
					"title": "SECURITY MEMO  -  14 MARCH",
					"body": "To all night staff:\n\nLab 3 access code has been rotated after the incident.\nNew code:  %s\n\n[i]Every code is crossed out, each in a different hand. Underneath, in chalk-dusty pencil:[/i]\n\nIT CHANGES EVERY TIME THE CAGE COMES DOWN.\nTHE DUTY TERMINAL IN HERE PRINTS THE NEW ONE.\nNEEDS POWER." % crossed,
				}
			return {
				"title": "SECURITY MEMO  -  14 MARCH",
				"body": "To all night staff:\n\nLab 3 access code has been rotated after the incident.\nNew code:  [b]%s[/b]\n\nDo NOT write this down.\n(Yes, I know. Burn this after reading.)\n\n- R. Okafor, Station Security" % GameState.lab_code,
			}
		"doc_relay_card":
			return {
				"title": "RELAY PROGRAMME  -  BRIEFING CARD",
				"body": "HALDEN DEEP RECOVERY RELAY\n\n1.  The lift carries ONE. You go down alone.\n2.  Restore power only where you must. Lights draw attention.\n3.  Recover the Lab 3 research drive. Nothing else is worth it.\n4.  Before you ride up (or if you can't), stock the handoff crate for the next member.\n5.  Leave a mark. The next one needs to know how far you got.\n\n[i]Someone has scratched a sixth line under it:[/i]\n6.  Don't trust the count.",
			}
		"doc_fan_ticket":
			return {
				"title": "MAINTENANCE TICKET  #0419",
				"body": "Area: B2 Generator room\nReported by: J. Brandt\n\nWall extractor fan turning with AUX power OFF.\nNo draught. Breaker isolated. Checked twice.\nRPM rises when someone stands near the generator.\n\nStatus:  [b]NOT A FAULT[/b]   (signed: Dr I. Varga)\n\n[i]Brandt's handwriting underneath:[/i]  then what is it",
			}
		"doc_roster":
			return {
				"title": "EVACUATION ROSTER  -  B2, 14 MARCH",
				"body": "One per cage. Tick when clear of the shaft.\n\n[x] Okafor R.        security\n[x] Brandt J.        maintenance\n[x] Lindqvist A.     lab tech\n[x] Osei K.          lab tech\n[x] Moreau P.        medical\n[ ] Varga I.         Lab 3 lead\n\n[i]Next to Varga, in pencil:[/i]  stayed. said someone has to.",
			}
		"doc_h7_sheet":
			return {
				"title": "SPECIMEN H-7  -  OBSERVATION SHEET",
				"body": "Tank 2. Fluid temp 4.1 C. Lights: AUX only.\n\n03 MAR   resonance 19.0 Hz   (baseline)\n06 MAR   19.1 Hz   fluid rotates toward door\n09 MAR   19.2 Hz   rotates toward OBSERVER, not door\n11 MAR   resonance rises with each person in the room\n13 MAR   counted 7 'peaks'. We are 6.\n\n[i]Circled twice:[/i]  WHO IS THE SEVENTH",
			}
		"doc_rotation":
			return {
				"title": "DUTY TERMINAL  -  ACCESS ROTATION",
				"body": "HALDEN DEEP / B2 SECURITY\n\nROTATION TRIGGER: LIFT CAGE DESCENT\nDESCENTS LOGGED: %d\n\nLAB 3 ............ [b]%s[/b]\nARCHIVE .......... CARD ONLY (RED)\nVAULT ............ PANEL\n\n> PRINT AND DESTROY" % [GameState.expedition_number, GameState.lab_code],
			}
		"doc_relay_rosters":
			var lines := "RELAY PROGRAMME  -  B2 ROSTER (one per cage)\n\n"
			for gh in Lore.GHOSTS:
				lines += "%02d   %-22s %s\n" % [gh["expedition"], gh["member"], Lore.end_label(gh["end"]).to_upper()]
			for hh in Legacy.chain.get("history", []):
				lines += "%02d   %-22s %s\n" % [int(hh["expedition"]), hh["member"], Lore.end_label(str(hh["end"])).to_upper()]
			lines += "%02d   %-22s ..." % [GameState.expedition_number, GameState.member_name if GameState.member_name != "" else "(you)"]
			return {"title": "ARCHIVE  -  RELAY ROSTERS", "body": lines + "\n\n[i]The roster goes back further than the station. The first pages are in a hand nobody here recognises.[/i]"}
		"doc_relay_log":
			return {"title": "TRANSMITTER LOG", "body": "RELAY LINE  B2 -> SURFACE\n\nTX  HANDOFF RECEIVED      ACK: SEND NEXT\nTX  HANDOFF RECEIVED      ACK: SEND NEXT\nTX  DRIVE RECEIVED        ACK: CORRUPT. SEND NEXT\nTX  NO HANDOFF            ACK: ...\n\n[i]The last line has no reply. Below it, in Varga's hand:[/i]\nThe line takes everything in one go. Every light on the level will come on with it.\nDon't be standing anywhere it can reach you."}
		"doc_camp_list":
			return {"title": "A LIST, ON THE BACK OF A RATION BOX", "body": "who came down:\n\nIIII IIII IIII IIII IIII IIII IIII IIII\nIIII IIII IIII IIII IIII IIII IIII II\n\nwho went up:\n\n[i](nothing written)[/i]\n\n- the crates are always full. we always fill them."}
		"note_handoff":
			return {
				"title": "EXPEDITION 0  -  HANDOFF",
				"body": "Whoever comes down next:\n\nGenerator room is first door on the LEFT. Hold the crank until it catches.\nThe lab needs three fuses. I found where one was, couldn't get to the rest.\nI left you a keycard and a spare cell. Ration the light.\n\nDon't stay longer than you have to.\nIt listens when the power is on.\n\n- M.",
			}
	return {"title": ItemDB.display_name(id), "body": ItemDB.get_def(id).get("desc", "")}
