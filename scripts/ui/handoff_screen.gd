class_name HandoffScreen
extends Control
## THE HANDOFF. At the end of every expedition you leave three things for the next
## member: a message (template + optional words of your own), ONE item in the
## crate, and a chalk mark where your run ended. If you have found all of Mara's
## tapes you can also refuse: leave nothing, and break the chain.

var hud: Node
var template_idx := -1
var custom := ""
var item := ""
var symbol := "x"
var committed: Dictionary = {}

var _tpl_buttons: Array[Button] = []
var _item_buttons := {}
var _sym_buttons := {}
var _custom_edit: LineEdit
var _preview: RichTextLabel
var _header: Label
var _sub: Label
var _main: Control
var _done: Control
var _done_text: Label
var _confirm: Button
var _refuse: Button


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.014, 0.016, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	add_child(UIKit.backdrop(0.0))
	_main = MarginContainer.new()
	_main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right"]:
		_main.add_theme_constant_override("margin_" + s, 70)
	_main.add_theme_constant_override("margin_top", 44)
	_main.add_theme_constant_override("margin_bottom", 36)
	add_child(_main)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_main.add_child(v)
	v.add_child(UIKit.label("HD-B2 // RELAY FORM 7-B // THE HANDOFF", 16, UIKit.AMBER_DIM, "mono"))
	_header = UIKit.label("", 56, UIKit.TEXT, "title")
	v.add_child(_header)
	v.add_child(UIKit.rule(UIKit.AMBER, 3, 140))
	_sub = UIKit.label("", 24, UIKit.DIM, "ui")
	v.add_child(_sub)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)

	# 1. message
	var c1 := _column(cols, "1   LEAVE A MESSAGE", 1.35)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	c1.add_child(grid)
	for i in Lore.TEMPLATES.size():
		var b := _toggle(Lore.TEMPLATES[i], 20)
		b.custom_minimum_size = Vector2(330, 52)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var idx := i
		b.pressed.connect(func(): select_template(idx))
		grid.add_child(b)
		_tpl_buttons.append(b)
	c1.add_child(UIKit.label("In your own words (optional):", 20, UIKit.DIM, "ui"))
	_custom_edit = LineEdit.new()
	_custom_edit.max_length = 80
	_custom_edit.placeholder_text = "e.g.  the second locker sticks. tell my sister I'm sorry"
	_custom_edit.add_theme_font_override("font", UIKit.font("mono"))
	_custom_edit.add_theme_font_size_override("font_size", 20)
	_custom_edit.custom_minimum_size.y = 46
	_custom_edit.text_changed.connect(func(t: String): set_custom(t))
	c1.add_child(_custom_edit)

	# 2. item
	var c2 := _column(cols, "2   ONE ITEM FOR THE CRATE", 0.8)
	var items := VBoxContainer.new()
	items.name = "Items"
	items.add_theme_constant_override("separation", 8)
	c2.add_child(items)

	# 3. mark
	var c3 := _column(cols, "3   YOUR MARK", 0.85)
	var sg := GridContainer.new()
	sg.columns = 3
	sg.add_theme_constant_override("h_separation", 8)
	sg.add_theme_constant_override("v_separation", 8)
	c3.add_child(sg)
	for sid in Lore.SYMBOLS:
		var b := _toggle("", 18)
		b.custom_minimum_size = Vector2(118, 108)
		b.icon = load("res://assets/decals/mark_%s.png" % sid)
		b.expand_icon = true
		b.tooltip_text = Lore.SYMBOLS[sid][1]
		var s2 := str(sid)
		b.pressed.connect(func(): select_symbol(s2))
		sg.add_child(b)
		_sym_buttons[sid] = b
	var meaning := UIKit.label("", 20, UIKit.DIM, "ui")
	meaning.name = "Meaning"
	meaning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c3.add_child(meaning)

	# preview + buttons
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 24)
	v.add_child(bottom)
	var pv := UIKit.panel(Color(0.85, 0.81, 0.71, 0.98), 18)
	pv.custom_minimum_size = Vector2(760, 150)
	var paper := UIKit.panel_style(Color(0.85, 0.81, 0.71, 0.98), Color(0, 0, 0, 0.3), 1, 18)
	paper.shadow_color = Color(0, 0, 0, 0.5)
	paper.shadow_size = 10
	pv.add_theme_stylebox_override("panel", paper)
	bottom.add_child(pv)
	_preview = RichTextLabel.new()
	_preview.bbcode_enabled = true
	_preview.fit_content = true
	_preview.add_theme_font_override("normal_font", UIKit.font("mono"))
	_preview.add_theme_font_override("italics_font", UIKit.font("mono"))
	_preview.add_theme_font_override("bold_font", UIKit.font("mono"))
	_preview.add_theme_font_size_override("bold_font_size", 19)
	_preview.add_theme_font_size_override("normal_font_size", 19)
	_preview.add_theme_font_size_override("italics_font_size", 19)
	_preview.add_theme_color_override("default_color", Color(0.13, 0.12, 0.1))
	pv.add_child(_preview)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 10)
	bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(bv)
	_confirm = UIKit.button("Leave the handoff", 32)
	_confirm.pressed.connect(confirm)
	bv.add_child(_confirm)
	_refuse = UIKit.button("Leave nothing. Break the chain.", 24)
	_refuse.add_theme_color_override("font_color", UIKit.RED)
	_refuse.pressed.connect(refuse)
	bv.add_child(_refuse)
	bv.add_child(UIKit.expand())
	bv.add_child(UIKit.hint_bar([["ui_accept", "Choose"], ["ui_up", "Move"]]))

	# after committing
	_done = CenterContainer.new()
	_done.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_done.visible = false
	add_child(_done)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 18)
	dv.custom_minimum_size.x = 900
	_done.add_child(dv)
	dv.add_child(UIKit.label("HD-B2 // RELAY FORM 7-B // FILED", 16, UIKit.AMBER_DIM, "mono"))
	var stamp := UIKit.label("HANDED OFF", 76, UIKit.AMBER, "title")
	stamp.name = "Stamp"
	dv.add_child(stamp)
	dv.add_child(UIKit.rule(UIKit.AMBER, 3, 160))
	_done_text = UIKit.label("", 26, UIKit.TEXT, "ui")
	_done_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(_done_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	dv.add_child(row)
	var nxt := UIKit.button("Send the next member down", 30)
	nxt.name = "Next"
	nxt.pressed.connect(next_member)
	row.add_child(nxt)
	var menu := UIKit.button("Main menu", 30)
	menu.pressed.connect(func(): Ux.change_scene("res://scenes/ui/main_menu.tscn"))
	row.add_child(menu)


func _column(parent: Control, title: String, ratio: float) -> VBoxContainer:
	var p := UIKit.term_panel("", 20)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = ratio
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UIKit.label(title, 22, UIKit.AMBER, "mono_bold"))
	v.add_child(UIKit.rule(Color(0.96, 0.66, 0.24, 0.25)))
	return v


func _toggle(text: String, size: int) -> Button:
	var b := UIKit.button(text, size)
	b.toggle_mode = true
	b.clip_text = false
	return b


func open() -> void:
	visible = true
	_main.visible = true
	_done.visible = false
	committed = {}
	var pd: Dictionary = Legacy.pending
	var n := int(pd.get("expedition", GameState.expedition_number))
	var who := str(pd.get("member", GameState.member_name))
	_header.text = "EXPEDITION %d   -   %s" % [n, who.to_upper()]
	var t := int(pd.get("time", 0))
	_sub.text = "%s   -   deepest: %s   -   %d:%02d underground" % [Lore.end_label(str(pd.get("end", ""))), Lore.depth_name(str(pd.get("depth", "shaft"))), t / 60, t % 60]
	# items
	var box: VBoxContainer = _main.find_child("Items", true, false)
	for c in box.get_children():
		c.queue_free()
	_item_buttons.clear()
	var choices: Array = Legacy.handoff_choices()
	for id in choices:
		var b := _toggle(ItemDB.display_name(id), 24)
		b.icon = null
		var i2 := str(id)
		b.pressed.connect(func(): select_item(i2))
		box.add_child(b)
		_item_buttons[i2] = b
	var none := _toggle("Nothing", 24)
	none.pressed.connect(func(): select_item(""))
	box.add_child(none)
	_item_buttons[""] = none
	if choices.is_empty():
		box.add_child(UIKit.label("Your pockets are empty.", 20, UIKit.DIM, "ui"))
	template_idx = -1
	custom = ""
	_custom_edit.text = ""
	select_item(choices[0] if not choices.is_empty() else "")
	select_symbol("x" if str(pd.get("end", "")) in ["died", "injured"] else "arrow")
	select_template(0 if str(pd.get("end", "")) in ["died", "injured"] else 9)
	_refuse.visible = Legacy.can_break()
	_wire_focus.call_deferred()
	Ux.quiet_focus(400)
	_confirm.grab_focus()


## Explicit d-pad routes: the message grid, your own words, the items, the marks,
## then Leave / Break. Left/right moves between the three columns.
func _wire_focus() -> void:
	var items: Array = (_main.find_child("Items", true, false) as Node).get_children().filter(func(c): return c is Button and not c.is_queued_for_deletion())
	var syms: Array = _sym_buttons.values()
	var bottom: Array = [_confirm] + ([_refuse] if _refuse.visible else [])
	# column 1: template grid (2 wide) then the text box
	for i in _tpl_buttons.size():
		var b: Button = _tpl_buttons[i]
		var col := i % 2
		var up := i - 2
		var dn := i + 2
		b.focus_neighbor_top = b.get_path_to(_tpl_buttons[up] if up >= 0 else _confirm)
		b.focus_neighbor_bottom = b.get_path_to(_tpl_buttons[dn] if dn < _tpl_buttons.size() else _custom_edit)
		b.focus_neighbor_left = b.get_path_to(_tpl_buttons[i - 1] if col == 1 else syms[0])
		b.focus_neighbor_right = b.get_path_to(_tpl_buttons[i + 1] if col == 0 and i + 1 < _tpl_buttons.size() else (items[0] if not items.is_empty() else syms[0]))
	_custom_edit.focus_neighbor_top = _custom_edit.get_path_to(_tpl_buttons[_tpl_buttons.size() - 2])
	_custom_edit.focus_neighbor_bottom = _custom_edit.get_path_to(_confirm)
	# column 2: items, top to bottom
	for i in items.size():
		var b: Button = items[i]
		b.focus_neighbor_top = b.get_path_to(items[i - 1] if i > 0 else _confirm)
		b.focus_neighbor_bottom = b.get_path_to(items[i + 1] if i + 1 < items.size() else _confirm)
		b.focus_neighbor_left = b.get_path_to(_tpl_buttons[mini(i * 2 + 1, _tpl_buttons.size() - 1)])
		b.focus_neighbor_right = b.get_path_to(syms[mini(i / 2 * 3, syms.size() - 1)])
	# column 3: marks (3 wide)
	for i in syms.size():
		var b: Button = syms[i]
		var c := i % 3
		b.focus_neighbor_top = b.get_path_to(syms[i - 3] if i >= 3 else _confirm)
		b.focus_neighbor_bottom = b.get_path_to(syms[i + 3] if i + 3 < syms.size() else _confirm)
		b.focus_neighbor_left = b.get_path_to(syms[i - 1] if c > 0 else (items[mini(i / 3 * 2, items.size() - 1)] if not items.is_empty() else _tpl_buttons[1]))
		b.focus_neighbor_right = b.get_path_to(syms[i + 1] if c < 2 and i + 1 < syms.size() else _tpl_buttons[0])
	# bottom row
	for i in bottom.size():
		var b: Button = bottom[i]
		b.focus_neighbor_top = b.get_path_to(_custom_edit)
		b.focus_neighbor_bottom = b.get_path_to(bottom[(i + 1) % bottom.size()] if bottom.size() > 1 else _tpl_buttons[0])
		b.focus_neighbor_left = b.get_path_to(_custom_edit)
		b.focus_neighbor_right = b.get_path_to(items[0] if not items.is_empty() else syms[0])


## Every control a gamepad can reach on this screen (tests walk these).
func focusables() -> Array:
	var out: Array = []
	out.append_array(_tpl_buttons)
	out.append(_custom_edit)
	out.append_array((_main.find_child("Items", true, false) as Node).get_children().filter(func(c): return c is Button and not c.is_queued_for_deletion()))
	out.append_array(_sym_buttons.values())
	out.append(_confirm)
	if _refuse.visible:
		out.append(_refuse)
	return out


func handoff_choices_shown() -> Array:
	return _item_buttons.keys().filter(func(k): return k != "")


func select_template(i: int) -> void:
	template_idx = i
	for k in _tpl_buttons.size():
		_tpl_buttons[k].set_pressed_no_signal(k == i)
	_update_preview()


func set_custom(t: String) -> void:
	custom = t.left(80)
	_update_preview()


func select_item(id: String) -> void:
	item = id
	for k in _item_buttons:
		(_item_buttons[k] as Button).set_pressed_no_signal(k == id)
	_update_preview()


func select_symbol(id: String) -> void:
	symbol = id
	for k in _sym_buttons:
		(_sym_buttons[k] as Button).set_pressed_no_signal(k == id)
	var m: Label = _main.find_child("Meaning", true, false)
	if m:
		var where := Lore.depth_name(Zones.area_at(_end_pos()))
		m.text = "%s: %s\nChalked where your run ended (%s)." % [Lore.SYMBOLS[id][0], Lore.SYMBOLS[id][1], where if where != "Unknown" else "here"]
	_update_preview()


func _end_pos() -> Vector3:
	var p: Array = Legacy.pending.get("pos", [0, 0, 0])
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func message() -> String:
	return Lore.TEMPLATES[template_idx] if template_idx >= 0 else ""


func _update_preview() -> void:
	if _preview == null:
		return
	var n := int(Legacy.pending.get("expedition", GameState.expedition_number))
	var body := ChainDirector._note_body(n, str(Legacy.pending.get("member", GameState.member_name)), message(), custom.strip_edges())
	var it := ("In the crate: [b]%s[/b]" % ItemDB.display_name(item)) if item != "" else "In the crate: nothing"
	_preview.text = "[i]What Expedition %d will find:[/i]\n%s\n%s" % [n + 1, body.replace("\n\n", "\n"), it]


func confirm() -> Dictionary:
	if not committed.is_empty():
		return committed
	committed = Legacy.commit_handoff(message(), custom, item, symbol)
	_show_done(false)
	return committed


func refuse() -> Dictionary:
	if not committed.is_empty() or not Legacy.can_break():
		return committed
	Legacy.pending["end"] = "break"
	committed = Legacy.commit_handoff("", "", "", "", true)
	visible = false
	get_tree().paused = false
	Events.set_modal(false)
	Events.ending_started.emit("break")
	return committed


func _show_done(_refused: bool) -> void:
	_main.visible = false
	_done.visible = true
	Ux.ui_sound("stamp")
	var st := _done.find_child("Stamp", true, false) as Control
	if st:
		st.pivot_offset = Vector2(0, 40)
		st.scale = Vector2(1.25, 1.25)
		st.modulate.a = 0.0
		var tw := st.create_tween().set_parallel(true)
		tw.tween_property(st, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(st, "modulate:a", 1.0, 0.12)
	var n := int(committed.get("expedition", 0))
	var it := ItemDB.display_name(item) if item != "" else "nothing"
	_done_text.text = "Expedition %d is over.\n\nThe next member, %s, will find your note and %s in the crate by the lift, and your mark on the floor of the %s.\n\nEverything you opened, fixed and decided stays that way." % [
		n, Lore.member_name(int(Legacy.chain["chain_id"]), n + 1), it, Lore.depth_name(Zones.area_at(_end_pos())).to_lower() if Zones.area_at(_end_pos()) != "" else "station"]
	(_done.find_child("Next", true, false) as Button).grab_focus()


func next_member() -> void:
	Legacy.begin_expedition()
	GameState.play_intro = true
	Ux.change_scene("res://scenes/game.tscn", 0.6, 0.01)
