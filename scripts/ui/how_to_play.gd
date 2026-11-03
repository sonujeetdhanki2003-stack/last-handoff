class_name HowToPlayScreen
extends TermPanel
## v1.2: How to Play, from the main menu. Four pages: the goal, controls (touch, keyboard
## and mouse, controller; read from the live bindings, so rebinding shows here), survival
## tips, saving and chapters. Pages: the tab buttons, left/right, Q/E or LB/RB, a tap.
## No spoilers: nothing about hidden areas, tapes or endings.

signal back

const PAGES := ["Goal", "Controls", "Survival", "Saving"]
var page := 0
var _tabs: Array[Button] = []
var _text: RichTextLabel
var _scroll: ScrollContainer
var _back: Button
var _prev: Button
var _next: Button


func _init() -> void:
	code = "HD-B2 // FIELD MANUAL"
	add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.03, 0.034, 0.038, 0.97), UIKit.LINE, 2, 32))
	custom_minimum_size = Vector2(1260, 790)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	v.add_child(UIKit.header("How to play", "", 50))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	v.add_child(tabs)
	for i in PAGES.size():
		var b := UIKit.button(PAGES[i].to_upper(), 26)
		b.name = "Tab_" + PAGES[i]
		b.toggle_mode = false
		b.custom_minimum_size = Vector2(190, 58)
		var idx := i
		b.pressed.connect(func(): set_page(idx))
		b.focus_entered.connect(func(): set_page(idx, false))
		tabs.add_child(b)
		_tabs.append(b)
	v.add_child(UIKit.rule())
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_text = RichTextLabel.new()
	_text.name = "Text"
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_override("normal_font", UIKit.font("ui"))
	_text.add_theme_font_override("bold_font", UIKit.font("ui_bold"))
	_text.add_theme_font_override("mono_font", UIKit.font("mono"))
	_text.add_theme_font_size_override("normal_font_size", 27)
	_text.add_theme_font_size_override("bold_font_size", 27)
	_text.add_theme_font_size_override("mono_font_size", 22)
	_text.add_theme_color_override("default_color", UIKit.TEXT)
	_text.add_theme_constant_override("line_separation", 6)
	_scroll.add_child(_text)
	v.add_child(UIKit.rule())
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	v.add_child(bottom)
	bottom.add_child(UIKit.hint_bar([["ui_tab_prev", "Page"], ["ui_cancel", "Back"]]))
	bottom.add_child(UIKit.expand())
	_prev = UIKit.button("<  Prev", 24)
	_prev.name = "Prev"
	_prev.custom_minimum_size.x = 130
	_prev.pressed.connect(func(): set_page(page - 1))
	bottom.add_child(_prev)
	_next = UIKit.button("Next  >", 24)
	_next.name = "Next"
	_next.custom_minimum_size.x = 130
	_next.pressed.connect(func(): set_page(page + 1))
	bottom.add_child(_next)
	_back = UIKit.button("Back", 24)
	_back.name = "Back"
	_back.custom_minimum_size.x = 140
	_back.pressed.connect(func():
		Ux.ui_sound("back")
		back.emit())
	bottom.add_child(_back)
	# focus: the tab row walks left/right; down from any tab goes to the bottom row
	var row: Array = []
	for b in _tabs:
		row.append(b)
	UIKit.chain_focus(row, true)
	UIKit.chain_focus([_prev, _next, _back], true)
	for b in _tabs:
		b.focus_neighbor_bottom = b.get_path_to(_next)
		b.focus_neighbor_top = b.get_path_to(_back)
	for b in [_prev, _next, _back]:
		b.focus_neighbor_top = b.get_path_to(_tabs[0])
		b.focus_neighbor_bottom = b.get_path_to(_tabs[0])


func open() -> void:
	set_page(0, false)
	Ux.quiet_focus()
	_next.grab_focus()


func focusables() -> Array:
	var out: Array = []
	out.append_array(_tabs)
	out.append_array([_prev, _next, _back])
	return out


func set_page(i: int, sound := true) -> void:
	i = wrapi(i, 0, PAGES.size())
	if sound and i != page:
		Ux.ui_sound("tab")
	page = i
	for k in _tabs.size():
		_tabs[k].modulate = Color(1, 1, 1, 1) if k == page else Color(0.6, 0.6, 0.6, 1)
		_tabs[k].add_theme_color_override("font_color", UIKit.AMBER if k == page else UIKit.TEXT)
	_text.text = page_text(page)
	_scroll.scroll_vertical = 0


func _unhandled_input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		Ux.ui_sound("back")
		back.emit()
	elif e.is_action_pressed("ui_tab_prev"):
		get_viewport().set_input_as_handled()
		set_page(page - 1)
	elif e.is_action_pressed("ui_tab_next"):
		get_viewport().set_input_as_handled()
		set_page(page + 1)
	elif e is InputEventScreenDrag and absf(e.relative.y) > 0.0:
		_scroll.scroll_vertical -= int(e.relative.y)


static func _k(action: String, pad := false) -> String:
	return "[color=#f5a83d][b]%s[/b][/color]" % Settings.action_label(action, pad)


static func page_text(i: int) -> String:
	match i:
		0:
			return """[b]You are the next member of the relay.[/b] Seven expeditions went down into Halden Deep before you, and none of them brought the research drive back up.

[color=#f5a83d]>[/color] Get the power back: crank the emergency generator, then find three fuses for the panel and the Lab 3 master switch.
[color=#f5a83d]>[/color] Find this expedition's lab code. It changes every time.
[color=#f5a83d]>[/color] Recover the research drive from Lab 3 and ride the lift back up.

Something lives down there. It is called the Keeper.

When your expedition ends, alive or not, you leave something in the crate for the next member: an item, a message, a chalk mark. The station remembers what every member did. The next one starts where you stopped."""
		1:
			var t := "[b]TOUCH (phone)[/b]\n"
			t += "[color=#f5a83d]>[/color] Thumb down anywhere on the left side and drag: move.  Swipe on the right side: look.\n"
			t += "[color=#f5a83d]>[/color] [b]USE[/b] interact (hold for cranks, doors and lockers)   [b]LIGHT[/b] torch   [b]CROUCH[/b]\n"
			t += "[color=#f5a83d]>[/color] [b]RUN[/b]: tap it once while you move, it glows while you run. The ring around it is your breath. It stops when you let go of the stick, crouch or run out of breath. Red means you can't run right now (too tired, too hurt, no room to stand).\n"
			t += "[color=#f5a83d]>[/color] [b]BAG[/b] inventory   [b]CELL[/b] swap the torch battery   [b]II[/b] pause   Phone back button: back / pause\n\n"
			t += "[b]KEYBOARD AND MOUSE[/b]\n"
			t += "[color=#f5a83d]>[/color] Move %s %s %s %s   Look: mouse   Run %s   Crouch %s\n" % [_k("move_forward"), _k("move_left"), _k("move_back"), _k("move_right"), _k("sprint"), _k("crouch")]
			t += "[color=#f5a83d]>[/color] Interact %s   Torch %s   Swap cell %s   Inventory %s   Objective %s   Shoulder %s   Pause %s\n\n" % [_k("interact"), _k("flashlight"), _k("reload_battery"), _k("inventory"), _k("show_objective"), _k("switch_shoulder"), _k("pause")]
			t += "[b]CONTROLLER[/b]\n"
			t += "[color=#f5a83d]>[/color] Move: left stick   Look: right stick   Run %s   Crouch %s\n" % [_k("sprint", true), _k("crouch", true)]
			t += "[color=#f5a83d]>[/color] Interact %s   Torch %s   Swap cell %s   Inventory %s   Objective %s   Pause %s\n\n" % [_k("interact", true), _k("flashlight", true), _k("reload_battery", true), _k("inventory", true), _k("show_objective", true), _k("pause", true)]
			t += "[color=#8a8d88]Every key and button can be changed in Settings > Controls. This page follows your bindings.[/color]"
			return t
		2:
			return """[color=#f5a83d]>[/color] [b]It hunts by sound.[/b] Running can be heard from far away, walking from close by. Crouching is silent.
[color=#f5a83d]>[/color] [b]Stand still[/b] when it is near. In the dark, crouched, it can barely see you.
[color=#f5a83d]>[/color] [b]Hide in a locker[/b] (or under a cot), but not while it watches you get in.
[color=#f5a83d]>[/color] [b]Your torch[/b] lets you see, and lets it see you from much further away. Held on its face, it drives it back for a while, but that drains the battery. Keep a spare cell.
[color=#f5a83d]>[/color] [b]Listen for the heartbeat.[/b] It speeds up the closer it gets, and on a phone you feel it too. The heartbeat never lies. The station creaks, rattles and flickers on its own. Not every sound is it.
[color=#f5a83d]>[/color] When it rears up and screams, it is about to lunge in a straight line: [b]step aside[/b] or keep moving.
[color=#f5a83d]>[/color] The first time it catches you, it hurts you and lets go. The second time is the end.
[color=#f5a83d]>[/color] Bright working light keeps it out. Watch the lamps: they stutter when it is close."""
		3:
			return """[color=#f5a83d]>[/color] The game saves on its own when you enter a new area, every minute, when you pause and when you leave the app. [b]CONTINUE[/b] picks up where you stopped.
[color=#f5a83d]>[/color] Every expedition joins the chain. [b]EXPEDITION HISTORY[/b] shows every member, how far they got and what they left.
[color=#f5a83d]>[/color] [b]CHAPTERS[/b] let you replay a part you have already reached: the start, emergency power, Lab 3 and the way up. A chapter run is a replay: it never changes your chain or your Continue slot.
[color=#f5a83d]>[/color] [b]ACHIEVEMENTS[/b] are kept on this device. Some stay hidden until you find them.
[color=#f5a83d]>[/color] Everything stays on your device. No account, no internet, no purchases."""
	return ""
