class_name ChaptersScreen
extends TermPanel
## v1.2: chapter select. A chapter opens once you reach it in any expedition. A chapter
## run is a replay: it never writes to the chain, the history or the Continue slot.

signal back
signal start(id: String)

var _list: VBoxContainer
var _back: Button
var rows := {}


func _init() -> void:
	code = "HD-B2 // RELAY CHECKPOINTS"
	add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.03, 0.034, 0.038, 0.97), UIKit.LINE, 2, 32))
	custom_minimum_size = Vector2(1180, 760)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	v.add_child(UIKit.header("Chapters", "", 50))
	var sub := UIKit.label("Replay any part you have reached. Replays never change your chain or your Continue slot.", 23, UIKit.DIM, "ui")
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	v.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	sc.add_child(_list)
	v.add_child(UIKit.rule())
	var bottom := HBoxContainer.new()
	v.add_child(bottom)
	bottom.add_child(UIKit.hint_bar([["ui_accept", "Play"], ["ui_cancel", "Back"]]))
	bottom.add_child(UIKit.expand())
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


func open() -> void:
	refresh()
	Ux.quiet_focus()
	(focusables()[0] as Control).grab_focus()


func focusables() -> Array:
	var out: Array = _list.get_children().filter(func(c): return c is FocusRow and not c.is_queued_for_deletion())
	out.append(_back)
	return out


func refresh() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	rows.clear()
	for c in Progress.CHAPTERS:
		var r := _row(c)
		rows[c["id"]] = r
		_list.add_child(r)
	UIKit.chain_focus(focusables())


func _row(c: Dictionary) -> FocusRow:
	var open_: bool = Progress.chapter_open(c["id"])
	var p := FocusRow.new()
	p.name = "Chapter_" + str(c["id"])
	p.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.05, 0.055, 0.06, 0.92 if open_ else 0.45), UIKit.LINE, 1, 16))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	p.add_child(h)
	var num := UIKit.label(str(c["num"]), 52, UIKit.AMBER if open_ else UIKit.FAINT, "title")
	num.custom_minimum_size.x = 90
	h.add_child(num)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	v.add_child(UIKit.label(str(c["title"]).to_upper(), 32, UIKit.TEXT if open_ else UIKit.DIM, "ui_bold"))
	var d := UIKit.label(str(c["text"]) if open_ else str(c["lock"]), 23, UIKit.DIM if open_ else UIKit.FAINT, "ui")
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	h.add_child(UIKit.label("PLAY  >" if open_ else "LOCKED", 22, UIKit.AMBER if open_ else UIKit.FAINT, "mono_bold"))
	var id: String = c["id"]
	p.activated.connect(func():
		if Progress.chapter_open(id):
			Ux.ui_sound("click")
			start.emit(id)
		else:
			Ux.ui_sound("back"))
	return p
