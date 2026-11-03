class_name AchievementsScreen
extends TermPanel
## v1.2: local achievements (Progress). Hidden ones show as ??? until unlocked.

signal back

var _list: VBoxContainer
var _summary: Label
var _back: Button
var _scroll: ScrollContainer


func _init() -> void:
	code = "HD-B2 // SERVICE RECORD"
	add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.03, 0.034, 0.038, 0.97), UIKit.LINE, 2, 32))
	custom_minimum_size = Vector2(1180, 790)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	v.add_child(UIKit.header("Achievements", "", 50))
	_summary = UIKit.label("", 24, UIKit.DIM, "ui")
	v.add_child(_summary)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	v.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)
	v.add_child(UIKit.rule())
	var bottom := HBoxContainer.new()
	v.add_child(bottom)
	bottom.add_child(UIKit.hint_bar([["ui_up", "Scroll"], ["ui_cancel", "Back"]]))
	bottom.add_child(UIKit.expand())
	_back = UIKit.button("Back", 24)
	_back.name = "Back"
	_back.custom_minimum_size.x = 140
	_back.pressed.connect(func():
		Ux.ui_sound("back")
		back.emit())
	bottom.add_child(_back)


func _unhandled_input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		Ux.ui_sound("back")
		back.emit()
	elif e is InputEventScreenDrag:
		_scroll.scroll_vertical -= int(e.relative.y)


func open() -> void:
	refresh()
	Ux.quiet_focus()
	var f := focusables()
	(f[0] as Control).grab_focus()


func focusables() -> Array:
	var out: Array = _list.get_children().filter(func(c): return c is FocusRow and not c.is_queued_for_deletion())
	out.append(_back)
	return out


func refresh() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var n := Progress.ACHIEVEMENTS.size()
	_summary.text = "%d of %d unlocked.   Kept on this device only." % [Progress.unlocked_count(), n]
	for id in Progress.ACHIEVEMENTS:
		_list.add_child(_row(id))
	UIKit.chain_focus(focusables())


func _row(id: String) -> Control:
	var d := Progress.display(id)
	var got: bool = d["unlocked"]
	var p := FocusRow.new()
	p.name = "Row_" + id
	p.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.05, 0.055, 0.06, 0.9 if got else 0.45), UIKit.AMBER_DIM if got else UIKit.LINE, 1, 14))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	p.add_child(h)
	var mark := UIKit.label("[+]" if got else "[ ]", 30, UIKit.AMBER if got else UIKit.FAINT, "mono_bold")
	mark.custom_minimum_size.x = 64
	h.add_child(mark)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	v.add_child(UIKit.label(str(d["title"]).to_upper(), 30, UIKit.TEXT if got else UIKit.DIM, "ui_bold"))
	var desc := UIKit.label(str(d["text"]), 23, UIKit.DIM if got else UIKit.FAINT, "ui")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)
	var st := UIKit.label("UNLOCKED" if got else ("HIDDEN" if d["hidden"] else "LOCKED"), 18, UIKit.GREEN if got else UIKit.FAINT, "mono")
	h.add_child(st)
	return p
