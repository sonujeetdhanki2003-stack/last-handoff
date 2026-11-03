class_name SettingsMenu
extends TermPanel
## Settings: four tabs (Audio, Controls with key rebinding, Graphics, Accessibility).
## LB/RB (Q/E) switch tabs; the d-pad/stick walks the rows; left/right changes a
## value; B/Esc goes back. Every control writes straight to Settings.

signal back

const TABS := ["AUDIO", "CONTROLS", "GRAPHICS", "ACCESSIBILITY"]

var tab := 0
var listening := {}   ## {"action": .., "slot": "kb"/"pad", "button": Button} while waiting for a key
var _rows := {}
var _tab_buttons: Array[Button] = []
var _pages: Array[VBoxContainer] = []
var _scroll: ScrollContainer
var _bind_buttons := {}
var _reset: Button
var _back: Button
var calibrate: Callable   ## set by the owner: opens the brightness screen


func _init() -> void:
	code = "HD-B2 // FIELD TERMINAL 07 // CONFIG"
	add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.03, 0.034, 0.038, 0.97), UIKit.LINE, 2, 34))
	custom_minimum_size = Vector2(1120, 800)


func _ready() -> void:
	super._ready()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(UIKit.header("Settings", "", 50))
	head.add_child(UIKit.expand())
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	tabs.alignment = BoxContainer.ALIGNMENT_END
	tabs.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(tabs)
	tabs.add_child(GlyphBadge.new("ui_tab_prev", 18))
	for i in TABS.size():
		var b := TermButton.new()
		b.text = TABS[i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 24)
		var k := i
		b.pressed.connect(func(): set_tab(k))
		tabs.add_child(b)
		_tab_buttons.append(b)
	tabs.add_child(GlyphBadge.new("ui_tab_next", 18))

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	v.add_child(_scroll)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(stack)
	for i in TABS.size():
		var page := VBoxContainer.new()
		page.name = "Page_" + TABS[i]
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 4)
		stack.add_child(page)
		_pages.append(page)

	var a := _pages[0]
	_section(a, "Volume")
	_slider(a, "Master", "audio", "master", 0.0, 1.0, 0.05, true)
	_slider(a, "Music", "audio", "music", 0.0, 1.0, 0.05, true)
	_slider(a, "Sound effects", "audio", "sfx", 0.0, 1.0, 0.05, true)
	_slider(a, "Ambience", "audio", "ambience", 0.0, 1.0, 0.05, true)
	_cycle(a, "Heartbeat when the Keeper is near", "audio", "heartbeat", ["Off", "On"], [false, true])
	_note(a, "Tapes and voices play on the sound-effects channel. Subtitles are under Accessibility.")

	var c := _pages[1]
	_section(c, "Camera")
	_slider(c, "Mouse sensitivity", "controls", "mouse_sensitivity", 0.02, 1.0, 0.01, false)
	_slider(c, "Gamepad look speed", "controls", "gamepad_sensitivity", 0.5, 6.0, 0.1, false)
	_cycle(c, "Invert look (Y)", "controls", "invert_y", ["Off", "On"], [false, true])
	_cycle(c, "Camera shoulder", "controls", "camera_side", ["Left", "Right"], [-1, 1])
	_section(c, "Movement")
	_cycle(c, "Sprint", "controls", "sprint_mode", ["Hold", "Toggle"], [0, 1])
	_cycle(c, "Crouch", "controls", "crouch_mode", ["Hold", "Toggle"], [0, 1])
	_cycle(c, "Vibration (phone and controller)", "controls", "vibration", ["Off", "On"], [false, true])
	_section(c, "Key bindings")
	var colh := HBoxContainer.new()
	colh.add_child(UIKit.expand())
	for t in ["KEYBOARD / MOUSE", "GAMEPAD"]:
		var l := UIKit.label(t, 17, UIKit.DIM, "mono")
		l.custom_minimum_size.x = 230
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		colh.add_child(l)
	c.add_child(colh)
	for act in Settings.REBINDABLE:
		_bind_row(c, act)
	var rb := UIKit.button("Reset key bindings", 24)
	rb.name = "ResetBinds"
	rb.pressed.connect(func():
		Settings.reset_binds()
		_refresh_binds())
	c.add_child(rb)
	_note(c, "Select a binding and press the new key or button. Esc cancels. Taking a key another action uses swaps the two.")

	var g := _pages[2]
	_section(g, "Display")
	if not Quality.is_phone_platform():   # a phone is always full screen
		_cycle(g, "Display mode", "video", "fullscreen", ["Windowed", "Fullscreen"], [false, true])
	_cycle(g, "V-Sync", "video", "vsync", ["Off", "On"], [false, true])
	_cycle(g, "Quality", "video", "quality", Settings.QUALITY_NAMES, [0, 1, 2, 3])
	_slider(g, "Resolution scale", "video", "resolution_scale", 0.5, 1.0, 0.05, true)
	_slider(g, "Field of view", "video", "fov", 55.0, 95.0, 1.0, false)
	_section(g, "Image")
	_slider(g, "Brightness", "video", "brightness", 0.6, 1.6, 0.05, true)
	var cal := UIKit.button("Calibrate brightness ...", 24)
	cal.name = "Calibrate"
	cal.pressed.connect(func(): if calibrate.is_valid(): calibrate.call())
	g.add_child(cal)
	_note(g, "Quality changes shadows, fog, ambient occlusion and reflections. Below 100 % resolution, FSR upscaling is used.")

	var x := _pages[3]
	_section(x, "Subtitles")
	_cycle(x, "Subtitles (tapes, voices, PA)", "access", "subtitles", ["Off", "On"], [false, true])
	_cycle(x, "Sound captions  [door slams]", "access", "captions", ["Off", "On"], [false, true])
	_cycle(x, "Subtitle size", "access", "subtitle_size", ["Small", "Medium", "Large", "Extra large"], [0, 1, 2, 3])
	_slider(x, "Subtitle background", "access", "subtitle_bg", 0.0, 1.0, 0.05, true)
	_section(x, "Visual")
	_cycle(x, "Colour-blind-safe prompts", "access", "colorblind_prompts", ["Off", "On"], [false, true])
	_slider(x, "Camera shake", "access", "camera_shake", 0.0, 1.0, 0.05, true)
	_cycle(x, "Reduce flashes", "access", "reduce_flashes", ["Off", "On"], [false, true])
	_cycle(x, "Objective fades out", "access", "objective_fade", ["Off", "On"], [false, true])
	_note(x, "Colour-blind-safe prompts draw every button prompt in plain black and white and mark warnings with a symbol, not only a colour.")

	v.add_child(UIKit.rule())
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	v.add_child(bottom)
	bottom.add_child(UIKit.hint_bar([["ui_tab_prev", "Tab"], ["ui_accept", "Select"], ["ui_cancel", "Back"]]))
	bottom.add_child(UIKit.expand())
	_reset = UIKit.button("Reset tab", 24)
	_reset.name = "ResetTab"
	_reset.pressed.connect(_reset_tab)
	bottom.add_child(_reset)
	_back = UIKit.button("Back", 24)
	_back.name = "BackButton"
	_back.custom_minimum_size.x = 140
	_back.pressed.connect(go_back)
	bottom.add_child(_back)
	visibility_changed.connect(func(): if visible: _refresh_all())
	set_tab(0, false)


func go_back() -> void:
	if not listening.is_empty():
		_stop_listen(false)
		return
	Ux.ui_sound("back")
	back.emit()


func set_tab(i: int, sound := true) -> void:
	tab = posmod(i, TABS.size())
	for k in _pages.size():
		_pages[k].visible = k == tab
		_tab_buttons[k].set_pressed_no_signal(k == tab)
	_scroll.scroll_vertical = 0
	if sound:
		Ux.ui_sound("tab")
	_wire_focus()
	if is_visible_in_tree():
		focus_first()


func focus_first() -> void:
	Ux.quiet_focus()
	var f := focusables()
	if not f.is_empty():
		(f[0] as Control).grab_focus()


## The focusable controls on the current tab, then Reset tab and Back.
func focusables() -> Array:
	var out := []
	for n in _pages[tab].find_children("*", "Control", true, false):
		var c := n as Control
		if c.focus_mode == Control.FOCUS_ALL and _shown_in(c, _pages[tab]):
			out.append(c)
	out.append(_reset)
	out.append(_back)
	return out


func _shown_in(c: Node, top: Node) -> bool:
	var n := c
	while n != null and n != top:
		if n is CanvasItem and not (n as CanvasItem).visible:
			return false
		n = n.get_parent()
	return true


func _wire_focus() -> void:
	var f := focusables()
	UIKit.chain_focus(f)
	# bindings: left/right moves between the keyboard and gamepad column
	# a grid: down/up stays in the same column, row to row
	var acts: Array = _bind_buttons.keys().filter(func(a): return f.has(_bind_buttons[a][0]))
	for r in acts.size():
		var pair: Array = _bind_buttons[acts[r]]
		pair[0].focus_neighbor_right = pair[0].get_path_to(pair[1])
		pair[1].focus_neighbor_left = pair[1].get_path_to(pair[0])
		var first: Control = _bind_buttons[acts[0]][0]
		var last: Control = _bind_buttons[acts[acts.size() - 1]][1]
		var above_all: Control = f[(f.find(first) - 1 + f.size()) % f.size()]
		var below_all: Control = f[(f.find(last) + 1) % f.size()]
		for col in 2:
			var b: Control = pair[col]
			var up: Control = _bind_buttons[acts[r - 1]][col] if r > 0 else above_all
			var dn: Control = _bind_buttons[acts[r + 1]][col] if r + 1 < acts.size() else below_all
			b.focus_neighbor_top = b.get_path_to(up)
			b.focus_neighbor_bottom = b.get_path_to(dn)
			b.focus_next = b.get_path_to(dn)
			b.focus_previous = b.get_path_to(up)
	_reset.focus_neighbor_right = _reset.get_path_to(_back)
	_back.focus_neighbor_left = _back.get_path_to(_reset)


func _input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if not listening.is_empty():
		_capture(e)
		return


func _unhandled_input(e: InputEvent) -> void:
	if not is_visible_in_tree() or not listening.is_empty():
		return
	if e.is_action_pressed("ui_tab_prev"):
		set_tab(tab - 1)
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("ui_tab_next"):
		set_tab(tab + 1)
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("ui_cancel") or e.is_action_pressed("pause"):
		go_back()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ rows
func _section(parent: Control, t: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.custom_minimum_size.y = 44
	var l := UIKit.label("// " + t.to_upper(), 19, UIKit.AMBER, "mono_bold")
	l.size_flags_vertical = Control.SIZE_SHRINK_END
	h.add_child(l)
	parent.add_child(h)
	parent.add_child(UIKit.rule(Color(0.96, 0.66, 0.24, 0.2)))


func _note(parent: Control, t: String) -> void:
	var l := UIKit.label(t, 19, UIKit.FAINT, "ui")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.y = 34
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	parent.add_child(l)


func _row(parent: Control, t: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.custom_minimum_size.y = 46
	var l := UIKit.label(t, 25, UIKit.TEXT, "ui")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	parent.add_child(h)
	return h


func _slider(parent: Control, t: String, s: String, k: String, mn: float, mx: float, step: float, pct: bool) -> void:
	var h := _row(parent, t)
	var sl := HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = step
	sl.custom_minimum_size = Vector2(380, 40)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.focus_mode = Control.FOCUS_ALL
	h.add_child(sl)
	var val := UIKit.label("", 22, UIKit.AMBER, "mono")
	val.custom_minimum_size.x = 80
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	var fmt := func(x: float) -> String: return ("%d%%" % roundi(x * 100.0)) if pct else (("%.2f" % x) if step < 1.0 else "%d" % int(x))
	sl.value_changed.connect(func(x):
		val.text = fmt.call(x)
		Settings.set_value(s, k, x)
		Ux.ui_sound("hover", 1.2))
	sl.focus_entered.connect(func():
		Ux.ui_sound("hover")
		h.modulate = Color(1.15, 1.05, 0.9))
	sl.focus_exited.connect(func(): h.modulate = Color.WHITE)
	sl.mouse_entered.connect(func(): sl.grab_focus())
	_rows[s + "/" + k] = {"control": sl, "kind": "slider", "label": val, "fmt": fmt}


func _cycle(parent: Control, t: String, s: String, k: String, names: Array, values: Array) -> void:
	var h := _row(parent, t)
	var c := CycleButton.new()
	c.options = names
	c.custom_minimum_size = Vector2(380 + 96, 40)
	c.add_theme_font_size_override("font_size", 24)
	c.value_changed.connect(func(i): Settings.set_value(s, k, values[i]))
	h.add_child(c)
	_rows[s + "/" + k] = {"control": c, "kind": "cycle", "values": values}


func _bind_row(parent: Control, act: String) -> void:
	var h := _row(parent, str(Settings.ACTION_NAMES.get(act, act)))
	var pair := []
	for slot in ["kb", "pad"]:
		var b := UIKit.button("", 22)
		b.name = "Bind_%s_%s" % [act, slot]
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(230, 40)
		b.add_theme_font_override("font", UIKit.font("mono_bold"))
		var sl: String = slot
		b.pressed.connect(func(): start_listen(act, sl))
		h.add_child(b)
		pair.append(b)
	_bind_buttons[act] = pair


func _refresh_binds() -> void:
	for act in _bind_buttons:
		var pair: Array = _bind_buttons[act]
		pair[0].text = Settings.action_label(act, false)
		pair[1].text = Settings.action_label(act, true)


func start_listen(act: String, slot: String) -> void:
	var b: Button = _bind_buttons[act][0 if slot == "kb" else 1]
	listening = {"action": act, "slot": slot, "button": b}
	b.text = "press a key ..." if slot == "kb" else "press a button ..."
	b.add_theme_color_override("font_color", UIKit.AMBER)


func _stop_listen(applied: bool) -> void:
	var b: Button = listening.get("button")
	listening = {}
	if b:
		b.remove_theme_color_override("font_color")
		b.grab_focus()
	if not applied:
		Ux.ui_sound("back")
	_refresh_binds()


## Takes the next key/mouse button (keyboard slot) or gamepad button (pad slot).
func _capture(e: InputEvent) -> void:
	if not (e is InputEventKey or e is InputEventMouseButton or e is InputEventJoypadButton):
		return
	if not e.is_pressed() or e.is_echo():
		return
	get_viewport().set_input_as_handled()
	if e is InputEventKey and (e.physical_keycode == KEY_ESCAPE or e.keycode == KEY_ESCAPE):
		_stop_listen(false)
		return
	if e is InputEventJoypadButton and e.button_index == JOY_BUTTON_START:
		_stop_listen(false)
		return
	if e is InputEventMouseButton and (e.device == InputEvent.DEVICE_ID_EMULATION or Quality.is_phone_platform()):
		# a finger tap posing as a left click: binding it would make every tap on the screen fire
		# that action. Cancel instead, so a phone player is never stuck listening.
		_stop_listen(false)
		return
	var slot: String = listening["slot"]
	var is_pad := e is InputEventJoypadButton
	if is_pad != (slot == "pad"):
		return
	if e is InputEventMouseButton and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		return
	var ev: InputEvent = e
	if e is InputEventKey:
		var k := InputEventKey.new()
		k.physical_keycode = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		ev = k
	elif e is InputEventMouseButton:
		var m := InputEventMouseButton.new()
		m.button_index = e.button_index
		ev = m
	else:
		var j := InputEventJoypadButton.new()
		j.button_index = e.button_index
		ev = j
	Settings.rebind(listening["action"], ev)
	Ux.ui_sound("click")
	_stop_listen(true)


func _reset_tab() -> void:
	var sec: Array = [["audio"], ["controls"], ["video"], ["access"]][tab]
	for key in _rows:
		var p: PackedStringArray = key.split("/")
		if p[0] in sec and p[1] != "calibrated":
			Settings.set_value(p[0], p[1], Settings.DEFAULTS[p[0]][p[1]], false)
	if tab == 1:
		Settings.reset_binds(false)
	Settings.save_settings()
	_refresh_all()


func _refresh_all() -> void:
	for key in _rows:
		var parts: PackedStringArray = key.split("/")
		var v: Variant = Settings.get_value(parts[0], parts[1])
		var r: Dictionary = _rows[key]
		match r["kind"]:
			"slider":
				r["control"].set_value_no_signal(float(v))
				r["label"].text = r["fmt"].call(float(v))
			"cycle":
				r["control"].set_index(maxi(0, r["values"].find(v)))
	_refresh_binds()
