class_name HistoryScreen
extends TermPanel
## Local expedition history: every member of the chain (and the ghosts before
## them) with depth, how it ended, the item left, the message and the decisions.

signal back

var _list: VBoxContainer
var _summary: Label
var _confirm_new: Button


var _back: Button


func _init() -> void:
	code = "HD-B2 // PERSONNEL RELAY LOG"
	add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.03, 0.034, 0.038, 0.97), UIKit.LINE, 2, 32))
	custom_minimum_size = Vector2(1340, 800)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	v.add_child(UIKit.header("Expedition history", "", 50))
	_summary = UIKit.label("", 22, UIKit.DIM, "ui")
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_summary)
	var sc := ScrollContainer.new()
	sc.name = "Scroll"
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	v.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	sc.add_child(_list)
	v.add_child(UIKit.rule())
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	v.add_child(bottom)
	bottom.add_child(UIKit.hint_bar([["ui_up", "Scroll"], ["ui_cancel", "Back"]]))
	bottom.add_child(UIKit.expand())
	_confirm_new = UIKit.button("Start a new chain (erases this one)", 22)
	_confirm_new.name = "NewChain"
	_confirm_new.pressed.connect(_on_new_chain)
	bottom.add_child(_confirm_new)
	_back = UIKit.button("Back", 24)
	_back.name = "Back"
	_back.custom_minimum_size.x = 140
	_back.pressed.connect(func():
		Ux.ui_sound("back")
		back.emit())
	bottom.add_child(_back)


func _unhandled_input(e: InputEvent) -> void:
	if is_visible_in_tree() and (e.is_action_pressed("ui_cancel") or e.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		Ux.ui_sound("back")
		back.emit()


func focus_first() -> void:
	Ux.quiet_focus()
	_back.grab_focus()


func focusables() -> Array:
	var out: Array = _list.get_children().filter(func(c): return c is FocusRow and not c.is_queued_for_deletion())
	out.append(_confirm_new)
	out.append(_back)
	return out


func _on_new_chain() -> void:
	if _confirm_new.text.begins_with("Sure"):
		Legacy.reset_chain()
		_confirm_new.text = "Start a new chain (erases this one)"
		refresh()
	else:
		_confirm_new.text = "Sure? Every member, mark and decision will be gone. Click again."


func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var rows: Array = Legacy.history_rows(true)
	var real := Legacy.expeditions_done()
	var dec := []
	for d in Lore.DECISIONS:
		var c := Legacy.decision(d)
		if c != "":
			dec.append(Lore.decision_label(d, c))
	var endings: Array = Legacy.chain.get("endings_seen", [])
	_summary.text = "%d members sent down in this chain, after %d before them.   Mara's tapes found: %d / 4.\nDecisions: %s.%s" % [
		real, Lore.GHOSTS.size(), Legacy.mara_tapes_found(),
		", ".join(dec) if not dec.is_empty() else "none yet",
		("   Endings seen: " + ", ".join(endings.map(func(e): return str(Lore.ENDINGS.get(e, {}).get("title", e))))) if not endings.is_empty() else ""]
	rows.reverse()
	for r in rows:
		_list.add_child(_row(r))
	var f := focusables()
	UIKit.chain_focus(f)
	_confirm_new.focus_neighbor_right = _confirm_new.get_path_to(_back)
	_back.focus_neighbor_left = _back.get_path_to(_confirm_new)


func _row(r: Dictionary) -> Control:
	var ghost: bool = r.get("ghost", false)
	var p := FocusRow.new()
	p.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.05, 0.055, 0.06, 0.5 if ghost else 0.9), UIKit.LINE, 1, 14))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	p.add_child(h)
	var num := UIKit.label("%02d" % int(r.get("expedition", 0)), 52, UIKit.DIM if ghost else UIKit.AMBER, "title")
	num.custom_minimum_size.x = 92
	h.add_child(num)
	if str(r.get("symbol", "")) != "":
		var ic := TextureRect.new()
		ic.texture = load("res://assets/decals/mark_%s.png" % r["symbol"])
		ic.custom_minimum_size = Vector2(64, 64)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.modulate = Color(1, 1, 1, 0.55 if ghost else 0.9)
		h.add_child(ic)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 2)
	h.add_child(mid)
	var name_line := str(r.get("member", "?"))
	if ghost:
		name_line += "   (recovered from the station)"
	mid.add_child(UIKit.label(name_line, 28, UIKit.DIM if ghost else UIKit.TEXT, "ui_bold"))
	var end_s := Lore.end_label(str(r.get("end", "")))
	var t := int(r.get("time", 0))
	var meta := "%s   -   deepest: %s" % [end_s, Lore.depth_name(str(r.get("depth", "shaft")))]
	if not ghost and t > 0:
		meta += "   -   %d:%02d underground   -   %s" % [t / 60, t % 60, str(r.get("date", ""))]
	mid.add_child(UIKit.label(meta, 21, UIKit.DIM, "ui"))
	var msg := str(r.get("message", ""))
	var cus := str(r.get("custom", ""))
	var said := ("\"%s\"" % msg) if msg != "" else ""
	if cus != "":
		said += ("   " if said != "" else "") + "\"%s\"" % cus
	if r.get("refused", false):
		said = "Left nothing."
	if said != "":
		var l := UIKit.label(said, 22, Color(0.85, 0.83, 0.76), "mono")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mid.add_child(l)
	for d in r.get("decisions", []):
		mid.add_child(UIKit.label("DECIDED:  " + str(d), 20, UIKit.AMBER, "ui_bold"))
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 230
	h.add_child(right)
	right.add_child(UIKit.label("LEFT IN THE CRATE", 16, UIKit.DIM, "ui_bold"))
	var it := str(r.get("item", ""))
	right.add_child(UIKit.label(ItemDB.display_name(it) if it != "" else "nothing", 24, UIKit.TEXT if it != "" else UIKit.DIM, "ui"))
	return p
