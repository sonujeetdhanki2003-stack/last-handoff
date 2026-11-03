extends CanvasLayer
## In-game HUD: objective, battery, crosshair, interaction prompt + hold ring,
## toasts, and the modal panels (inventory, note reader, keypad, end screen).

const SLOT_COUNT := 8

var player: Player
var _root: Control
var _obj_title: Label
var _obj_text: Label
var _battery_bar: SegmentBar
var _battery_pct: Label
var _cells: Label
var _cross: ColorRect
var _prompt_box: Control
var _prompt_key: Label
var _prompt_text: Label
var _hold_bar: ProgressBar
var _refusal: Label
var _refusal_t := 0.0
var _toasts: VBoxContainer
var _fade: ColorRect

var inventory_panel: Control
var _slot_buttons: Array[Button] = []
var _sel := 0
var _detail_name: Label
var _detail_desc: Label
var _use_btn: Button
var _drop_btn: Button

var note_panel: Control
var _note_title: Label
var _note_body: RichTextLabel

var keypad_panel: Control
var _keypad: Keypad
var _keypad_display: Label
var _keypad_entry := ""
var _keypad_msg: Label

var tape_bar: Control
var _tape_label: Label
var _tape_prog: ProgressBar
var _tape_len := 0.0
var _tape_t := 0.0

var end_panel: Control
var _end_title: Label
var _end_stats: Label
var _end_again: Button

# Phase 5
var _obj_box: Control
var _obj_show_t := 0.0
var _device: Control
var _device_t := 0.0
var _ecg: EcgTrace
var _area_box: Control
var _area_title: Label
var _area_code: Label
var _prompt_glyph: GlyphBadge
var _detail_icon: TextureRect
var _inv_hints: HintBar
var _inv_stats: Label
var _icons := {}
var _last_battery := -1.0
var _last_health := -1.0
const OBJ_SHOW := 7.0
var touch: TouchControls = null


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_objective()
	_build_battery()
	_build_center()
	_build_toasts()
	_build_inventory()
	_build_note()
	_build_keypad()
	_build_end()
	_build_tape()
	_build_vitals()
	_build_choice()
	_build_cinematic()
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 1.6).set_delay(0.2)

	Events.toast.connect(show_toast)
	Ux.device_changed.connect(func(_p): if player: _refresh_battery())   # "[R] SWAP" follows the device
	Events.interaction_feedback.connect(show_refusal)
	Events.show_note.connect(open_note)
	Events.open_keypad.connect(open_keypad)
	Events.tape_started.connect(_on_tape_started)
	Events.tape_finished.connect(func(): tape_bar.visible = false)
	Events.open_choice.connect(open_choice)
	Events.player_hurt.connect(_on_hurt)
	GameState.objectives.objective_updated.connect(func(_i): _refresh_objective())
	GameState.objectives.objective_completed.connect(_on_obj_done)
	GameState.inventory.changed.connect(_refresh_inventory)
	_refresh_objective()
	_refresh_inventory()


func bind_player(p: Player) -> void:
	player = p
	# Phase 6: on-screen controls on touchscreens, above the HUD and its panels
	if TouchControls.wanted() and touch == null:
		var tl := CanvasLayer.new()
		tl.name = "TouchLayer"
		tl.layer = 6
		tl.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(tl)
		touch = TouchControls.new()
		touch.player = p
		tl.add_child(touch)
	apply_safe_area()
	p.interaction_target_changed.connect(_on_target)
	p.hold_progress.connect(_on_hold)
	p.flashlight.battery_changed.connect(func(_c): _refresh_battery())
	p.flashlight.toggled.connect(func(_o): _refresh_battery())
	_refresh_battery()


# ------------------------------------------------------------------ build
func _build_objective() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(48, 38)
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_obj_box = box
	_obj_title = UIKit.shadowed(UIKit.label("OBJECTIVE  //  B2", 16, UIKit.AMBER, "mono_bold"))
	box.add_child(_obj_title)
	_obj_text = UIKit.shadowed(UIKit.label("", 30, UIKit.TEXT, "ui"))
	box.add_child(_obj_text)
	var hint := HBoxContainer.new()
	hint.name = "ObjHint"
	hint.add_theme_constant_override("separation", 8)
	hint.modulate.a = 0.0
	box.add_child(hint)
	_hud_items.append(box)


func _build_battery() -> void:
	# the "field device" cluster, bottom left: light, cells, pulse, stamina
	var p := TermPanel.new()
	p.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.02, 0.024, 0.027, 0.55), Color(1, 1, 1, 0.05), 2, 14))
	p.scanlines = true
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = 40
	p.offset_top = -150
	p.offset_bottom = -36
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(p)
	_device = p
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	p.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	row.add_child(UIKit.label("LIGHT", 16, UIKit.DIM, "mono_bold"))
	_battery_bar = SegmentBar.new()
	_battery_bar.custom_minimum_size = Vector2(200, 12)
	_battery_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_battery_bar)
	_battery_pct = UIKit.label("60%", 17, UIKit.TEXT, "mono")
	_battery_pct.custom_minimum_size.x = 92
	row.add_child(_battery_pct)
	_cells = UIKit.label("", 16, UIKit.DIM, "mono")
	box.add_child(_cells)


func _build_center() -> void:
	_cross = ColorRect.new()
	_cross.size = Vector2(4, 4)
	_cross.color = Color(1, 1, 1, 0.55)
	_cross.anchor_left = 0.5
	_cross.anchor_top = 0.5
	_cross.anchor_right = 0.5
	_cross.anchor_bottom = 0.5
	_cross.offset_left = -2
	_cross.offset_top = -2
	_cross.offset_right = 2
	_cross.offset_bottom = 2
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_cross)

	var col := VBoxContainer.new()
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_top = 1.0
	col.anchor_bottom = 1.0
	col.offset_left = -400
	col.offset_right = 400
	col.offset_top = -230
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(col)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	_prompt_box = row
	_prompt_glyph = GlyphBadge.new("interact", 21)
	_prompt_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_prompt_glyph)
	_prompt_key = UIKit.label("", 1, Color(0, 0, 0, 0), "mono_bold")
	_prompt_key.visible = false
	row.add_child(_prompt_key)
	_prompt_text = UIKit.label("", 30, UIKit.TEXT, "ui")
	_prompt_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_prompt_text.add_theme_constant_override("shadow_offset_y", 2)
	row.add_child(_prompt_text)
	_prompt_box.visible = false
	_hold_bar = ProgressBar.new()
	_hold_bar.custom_minimum_size = Vector2(220, 6)
	_hold_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hold_bar.show_percentage = false
	_hold_bar.max_value = 1.0
	_hold_bar.step = 0.001
	_hold_bar.visible = false
	col.add_child(_hold_bar)
	_refusal = UIKit.label("", 26, UIKit.RED, "ui")
	_refusal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_refusal.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_refusal.add_theme_constant_override("shadow_offset_y", 2)
	col.add_child(_refusal)


func _build_toasts() -> void:
	_toasts = VBoxContainer.new()
	_toasts.anchor_left = 1.0
	_toasts.anchor_right = 1.0
	_toasts.offset_left = -600
	_toasts.offset_right = -44
	_toasts.offset_top = 40
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.add_theme_constant_override("separation", 6)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)
	# area title, lower left above the device: "B2 // SECURITY OFFICE"
	_area_box = VBoxContainer.new()
	_area_box.anchor_top = 1.0
	_area_box.anchor_bottom = 1.0
	_area_box.offset_left = 48
	_area_box.offset_top = -290
	_area_box.add_theme_constant_override("separation", 0)
	_area_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area_box.modulate.a = 0.0
	_root.add_child(_area_box)
	_area_code = UIKit.shadowed(UIKit.label("", 16, UIKit.AMBER, "mono"))
	_area_box.add_child(_area_code)
	_area_title = UIKit.shadowed(UIKit.label("", 44, UIKit.TEXT, "title"))
	_area_box.add_child(_area_title)
	Events.area_entered.connect(show_area)


func _modal_base(w: float, h: float, code := "") -> PanelContainer:
	var dim := UIKit.backdrop(0.62)
	dim.visible = false
	_root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(cc)
	var p := UIKit.term_panel(code, 28)
	p.custom_minimum_size = Vector2(w, h)
	cc.add_child(p)
	return p


func _build_inventory() -> void:
	var p := _modal_base(1180, 640, "HD-B2 // FIELD PACK")
	inventory_panel = p.get_parent().get_parent()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	v.add_child(UIKit.header("Inventory", "", 46))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 30)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(grid)
	var sn := UIKit.panel_style(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.1), 2, 8)
	var sh := UIKit.panel_style(Color(0.96, 0.66, 0.24, 0.1), UIKit.AMBER, 2, 8)
	var sf := StyleBoxFlat.new()
	sf.draw_center = false
	sf.border_color = UIKit.AMBER
	sf.set_border_width_all(2)
	for i in SLOT_COUNT:
		var b := Button.new()
		b.name = "Slot%d" % i
		b.custom_minimum_size = Vector2(150, 160)
		b.focus_mode = Control.FOCUS_ALL
		b.add_theme_font_override("font", UIKit.font("ui"))
		b.add_theme_font_size_override("font_size", 19)
		b.add_theme_stylebox_override("normal", sn)
		b.add_theme_stylebox_override("hover", sh)
		b.add_theme_stylebox_override("pressed", sh)
		b.add_theme_stylebox_override("focus", sf)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 84)
		var idx := i
		b.pressed.connect(func(): _select(idx))
		b.focus_entered.connect(func():
			_select(idx)
			Ux.ui_sound("hover"))
		b.mouse_entered.connect(func(): b.grab_focus())
		grid.add_child(b)
		_slot_buttons.append(b)
	var det := VBoxContainer.new()
	det.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	det.add_theme_constant_override("separation", 10)
	body.add_child(det)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	det.add_child(top)
	_detail_icon = TextureRect.new()
	_detail_icon.custom_minimum_size = Vector2(120, 120)
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(_detail_icon)
	var nv := VBoxContainer.new()
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(nv)
	_detail_name = UIKit.label("", 36, UIKit.AMBER, "ui_bold")
	nv.add_child(_detail_name)
	var kind := UIKit.label("", 16, UIKit.DIM, "mono")
	kind.name = "Kind"
	nv.add_child(kind)
	det.add_child(UIKit.rule())
	_detail_desc = UIKit.label("", 25, UIKit.TEXT, "ui")
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.custom_minimum_size = Vector2(380, 0)
	det.add_child(_detail_desc)
	det.add_child(UIKit.expand())
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	det.add_child(btns)
	_use_btn = UIKit.button("Use", 24)
	_use_btn.pressed.connect(use_selected)
	btns.add_child(_use_btn)
	_drop_btn = UIKit.button("Drop", 24)
	_drop_btn.pressed.connect(drop_selected)
	btns.add_child(_drop_btn)
	var close := UIKit.button("Close", 24)
	close.name = "Close"
	close.pressed.connect(close_inventory)
	btns.add_child(close)
	for b in [_use_btn, _drop_btn, close]:
		b.focus_mode = Control.FOCUS_CLICK
	v.add_child(UIKit.rule())
	var foot := HBoxContainer.new()
	v.add_child(foot)
	_inv_hints = UIKit.hint_bar([["ui_use", "Use"], ["ui_drop", "Drop"], ["ui_cancel", "Close"]])
	foot.add_child(_inv_hints)
	foot.add_child(UIKit.expand())
	_inv_stats = UIKit.label("", 17, UIKit.DIM, "mono")
	foot.add_child(_inv_stats)
	# d-pad walks the 4 x 2 grid and wraps
	for i in SLOT_COUNT:
		var b := _slot_buttons[i]
		var r := i / 4
		var c := i % 4
		b.focus_neighbor_left = b.get_path_to(_slot_buttons[r * 4 + (c + 3) % 4])
		b.focus_neighbor_right = b.get_path_to(_slot_buttons[r * 4 + (c + 1) % 4])
		b.focus_neighbor_top = b.get_path_to(_slot_buttons[((r + 1) % 2) * 4 + c])
		b.focus_neighbor_bottom = b.get_path_to(_slot_buttons[((r + 1) % 2) * 4 + c])


func _build_note() -> void:
	var p := _modal_base(800, 680)
	note_panel = p.get_parent().get_parent()
	var paper := UIKit.panel_style(Color(0.85, 0.82, 0.73, 0.99), Color(0, 0, 0, 0.25), 1, 44)
	paper.shadow_color = Color(0, 0, 0, 0.6)
	paper.shadow_size = 18
	p.add_theme_stylebox_override("panel", paper)
	(p as TermPanel).brackets = false
	(p as TermPanel).scanlines = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	p.add_child(v)
	_note_title = UIKit.label("", 27, Color(0.15, 0.13, 0.1), "typed")
	v.add_child(_note_title)
	v.add_child(UIKit.rule(Color(0.2, 0.15, 0.1, 0.35), 2))
	_note_body = RichTextLabel.new()
	_note_body.bbcode_enabled = true
	_note_body.fit_content = false
	_note_body.focus_mode = Control.FOCUS_ALL
	_note_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_note_body.add_theme_font_override("normal_font", UIKit.font("mono"))
	_note_body.add_theme_font_override("bold_font", UIKit.font("mono_bold"))
	_note_body.add_theme_font_size_override("normal_font_size", 22)
	_note_body.add_theme_font_size_override("bold_font_size", 25)
	_note_body.add_theme_color_override("default_color", Color(0.12, 0.11, 0.1))
	v.add_child(_note_body)
	var row := HBoxContainer.new()
	v.add_child(row)
	var hb := UIKit.hint_bar([["ui_cancel", "Close"]])
	hb.modulate = Color(0.3, 0.27, 0.22)
	row.add_child(hb)
	row.add_child(UIKit.expand())
	var close := UIKit.button("Close", 24)
	close.add_theme_color_override("font_color", Color(0.15, 0.13, 0.1))
	close.pressed.connect(close_note)
	row.add_child(close)


func _build_keypad() -> void:
	var p := _modal_base(420, 600)
	keypad_panel = p.get_parent().get_parent()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	v.add_child(UIKit.label("LAB 3  ACCESS", 30, UIKit.TEXT, "title"))
	var disp_panel := UIKit.panel(Color(0.02, 0.06, 0.03, 1.0), 12)
	v.add_child(disp_panel)
	_keypad_display = UIKit.label("_ _ _ _", 48, UIKit.GREEN, "mono_bold")
	_keypad_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	disp_panel.add_child(_keypad_display)
	_keypad_msg = UIKit.label("Enter 4-digit code", 22, UIKit.DIM, "ui")
	_keypad_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_keypad_msg)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(grid)
	for k in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "CLR", "0", "ENT"]:
		var b := Button.new()
		b.text = k
		b.custom_minimum_size = Vector2(100, 70)
		b.add_theme_font_override("font", UIKit.font("mono_bold"))
		b.add_theme_font_size_override("font_size", 28)
		var kk: String = k
		b.pressed.connect(func(): _keypad_press(kk))
		grid.add_child(b)
	var close := UIKit.button("Step away", 22)   # Esc / B / BACK all close it; no single key name fits every device
	close.pressed.connect(close_keypad)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(close)


func _build_end() -> void:
	var p := _modal_base(820, 460)
	end_panel = p.get_parent().get_parent()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	p.add_child(v)
	_end_title = UIKit.label("", 54, UIKit.AMBER, "title")
	v.add_child(_end_title)
	_end_stats = UIKit.label("", 26, UIKit.TEXT, "ui")
	_end_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_end_stats)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var again := UIKit.button("New expedition", 28)
	again.name = "Again"
	_end_again = again
	again.pressed.connect(func():
		get_tree().paused = false
		Events.set_modal(false)
		if GameState.chapter_run != "":
			Progress.begin_chapter(GameState.chapter_run)   # v1.2: retry the same chapter
		else:
			GameState.expedition_number += 1
			GameState.new_expedition()
		get_tree().change_scene_to_file("res://scenes/game.tscn"))
	row.add_child(again)
	var menu := UIKit.button("Main menu", 28)
	menu.pressed.connect(func():
		get_tree().paused = false
		Events.set_modal(false)
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn"))
	row.add_child(menu)


# ------------------------------------------------------------------ live updates
## Keep the corner widgets out of a notch / rounded corner, and the toasts below the
## on-screen BAG / II buttons on a touchscreen.
var _safe_applied := Vector4(-1, -1, -1, -1)
func apply_safe_area() -> void:
	var m := Ux.safe_margins(get_viewport())
	_safe_applied = m
	if _obj_box:
		_obj_box.position = Vector2(48 + m.x, 38 + m.y)
	if _device:
		_device.offset_left = 40 + m.x
		_device.offset_top = -150 - m.w
		_device.offset_bottom = -36 - m.w
	if _toasts:
		_toasts.offset_right = -44 - m.z
		_toasts.offset_left = -600 - m.z
		_toasts.offset_top = 40 + m.y + (150.0 if touch != null else 0.0)
	if _area_box:
		_area_box.offset_left = 48 + m.x
		_area_box.offset_top = -290 - m.w


func _process(delta: float) -> void:
	if Ux.safe_margins(get_viewport()) != _safe_applied:
		apply_safe_area()
	_process_tape(delta)
	_process_vitals(delta)
	_process_fades(delta)
	if _refusal_t > 0.0:
		_refusal_t -= delta
		_refusal.modulate.a = clampf(_refusal_t / 0.4, 0.0, 1.0)
	if player and player.flashlight.battery.is_low():
		_battery_bar.modulate = Color(1, 0.3, 0.25) if fmod(Time.get_ticks_msec() / 400.0, 2.0) < 1.0 else Color(1, 1, 1)
	elif _battery_bar:
		_battery_bar.modulate = Color.WHITE


func _refresh_objective() -> void:
	var id := GameState.objectives.current_id()
	var t := "Get out." if id == "" else GameState.objectives.label(id)
	if t != _obj_text.text:
		_obj_text.text = t
		show_objective()


## Brings the objective up (it fades after a few seconds unless that's turned off).
func show_objective(hold := OBJ_SHOW) -> void:
	_obj_show_t = hold
	if _obj_box:
		create_tween().tween_property(_obj_box, "modulate:a", 1.0, 0.25)


func _on_obj_done(id: String) -> void:
	var o := GameState.objectives.get_objective(id)
	show_toast(("[ok]  " if Settings.get_value("access", "colorblind_prompts") else "") + "Objective complete: " + str(o.get("text", id)), UIKit.GREEN)
	Sfx.play("sting_discover", -14.0)
	_refresh_objective()
	show_objective()
	var t := create_tween()
	_obj_text.modulate = UIKit.AMBER
	t.tween_property(_obj_text, "modulate", Color.WHITE, 1.2)


func _refresh_battery() -> void:
	if player == null:
		return
	var b := player.flashlight.battery
	_battery_bar.value = b.charge
	_battery_pct.text = "%d%%%s" % [b.percent(), "" if player.flashlight.on else " OFF"]
	_battery_pct.add_theme_color_override("font_color", UIKit.TEXT if player.flashlight.on else UIKit.DIM)
	if absf(b.charge - _last_battery) > 0.04 or b.is_low():
		_wake_device()
	_last_battery = b.charge
	_refresh_cells()


func _refresh_cells() -> void:
	var n := GameState.inventory.count("battery")
	_cells.text = ("SPARE CELLS x%d   [%s] SWAP" % [n, Ux.glyph("reload_battery")]) if n > 0 else "NO SPARE CELLS"
	_cells.add_theme_color_override("font_color", UIKit.DIM if n > 0 else Color(0.75, 0.45, 0.35))


func _on_target(t: Node) -> void:
	if t == null:
		_prompt_box.visible = false
		_cross.size = Vector2(4, 4)
		_cross.color = Color(1, 1, 1, 0.55)
		return
	_prompt_box.visible = true
	var ok: bool = t.can_interact(player)
	var hold: float = t.get_hold_time(player)
	var cb := bool(Settings.get_value("access", "colorblind_prompts"))
	_prompt_glyph.refresh()
	if ok:
		_prompt_text.text = ("Hold  " if hold > 0.0 and not t.get_prompt(player).begins_with("Hold") else "") + t.get_prompt(player)
		_prompt_text.add_theme_color_override("font_color", UIKit.TEXT)
		_prompt_glyph.modulate = Color.WHITE
	else:
		_prompt_text.text = ("\u2715  " if cb else "") + t.get_prompt(player) + "   -   " + t.get_refusal(player)
		_prompt_text.add_theme_color_override("font_color", Color(1, 1, 1) if cb else Color(0.78, 0.62, 0.56))
		_prompt_glyph.modulate = Color(1, 1, 1, 0.45)
	_cross.color = UIKit.AMBER


func _on_hold(f: float) -> void:
	_hold_bar.visible = f >= 0.0
	_hold_bar.value = maxf(f, 0.0)


func show_toast(text: String, color := UIKit.TEXT) -> void:
	var p := PanelContainer.new()
	var sb := UIKit.panel_style(Color(0.02, 0.024, 0.027, 0.78), Color(0, 0, 0, 0), 0, 12)
	sb.border_color = color
	sb.border_width_left = 3
	sb.set_border_width_all(0)
	sb.border_width_left = 3
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UIKit.label(text, 23, color if color != UIKit.TEXT else UIKit.TEXT, "ui")
	p.add_child(l)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	_toasts.add_child(p)
	while _toasts.get_child_count() > 5:
		_toasts.get_child(0).free()
	var t := p.create_tween()
	p.modulate.a = 0.0
	t.tween_property(p, "modulate:a", 1.0, 0.2)
	t.tween_interval(3.4)
	t.tween_property(p, "modulate:a", 0.0, 0.6)
	t.tween_callback(p.queue_free)


## "B2 // SECURITY OFFICE": fades up when you walk into a new area.
func show_area(area: String) -> void:
	if _area_box == null or area == "":
		return
	var nm := Lore.depth_name(area)
	if nm == "Unknown":
		return
	_area_code.text = "HALDEN DEEP  //  B2  //  %02d" % maxi(0, Lore.depth_rank(area))
	_area_title.text = nm.to_upper()
	var tw := create_tween()
	tw.tween_property(_area_box, "modulate:a", 1.0, 0.6)
	tw.tween_interval(2.6)
	tw.tween_property(_area_box, "modulate:a", 0.0, 1.2)


func show_refusal(text: String) -> void:
	_refusal.text = text
	_refusal_t = 2.2


func _process_fades(delta: float) -> void:
	if _obj_box and bool(Settings.get_value("access", "objective_fade")):
		if _obj_show_t > 0.0:
			_obj_show_t -= delta
			if _obj_show_t <= 0.0:
				create_tween().tween_property(_obj_box, "modulate:a", 0.0, 1.4)
	elif _obj_box:
		_obj_box.modulate.a = 1.0
	if _device:
		_device_t -= delta
		var want := 1.0 if _device_t > 0.0 else 0.35
		_device.modulate.a = move_toward(_device.modulate.a, want, delta * 1.5)


func _wake_device(t := 5.0) -> void:
	_device_t = maxf(_device_t, t)


# ------------------------------------------------------------------ inventory
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("show_objective") and not Events.modal_open:
		show_objective(4.0)
		_wake_device(4.0)
		get_viewport().set_input_as_handled()
		return
	if end_panel.visible or (handoff != null and handoff.visible) or (end_card != null and end_card.visible):
		return
	if choice_panel.visible:
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
			close_choice(); get_viewport().set_input_as_handled()
		return
	if keypad_panel.visible:
		if event is InputEventKey and event.pressed and not event.echo:
			var k: int = event.keycode
			if k >= KEY_0 and k <= KEY_9:
				_keypad_press(str(k - KEY_0)); get_viewport().set_input_as_handled(); return
			if k >= KEY_KP_0 and k <= KEY_KP_9:
				_keypad_press(str(k - KEY_KP_0)); get_viewport().set_input_as_handled(); return
			if k == KEY_ENTER or k == KEY_KP_ENTER:
				_keypad_press("ENT"); get_viewport().set_input_as_handled(); return
			if k == KEY_BACKSPACE:
				_keypad_press("CLR"); get_viewport().set_input_as_handled(); return
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
			close_keypad(); get_viewport().set_input_as_handled()
		return
	if note_panel.visible:
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
			close_note(); get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("inventory"):
		if inventory_panel.visible:
			close_inventory()
		elif not get_tree().paused:
			open_inventory()
		get_viewport().set_input_as_handled()
	elif inventory_panel.visible:
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
			close_inventory(); get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_use"):
			use_selected(); get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_drop"):
			drop_selected(); get_viewport().set_input_as_handled()


func open_inventory() -> void:
	inventory_panel.visible = true
	Events.set_modal(true)
	Sfx.play("inv_open", -8.0)
	_refresh_inventory()
	Ux.quiet_focus()
	_slot_buttons[_sel].grab_focus()


func close_inventory() -> void:
	if inventory_panel.visible:
		Sfx.play("inv_close", -10.0)
	inventory_panel.visible = false
	Events.set_modal(false)


func _select(i: int) -> void:
	_sel = i
	_refresh_detail()


func _refresh_inventory() -> void:
	if _slot_buttons.is_empty():
		return
	for i in SLOT_COUNT:
		var s: Variant = GameState.inventory.get_slot(i)
		var b := _slot_buttons[i]
		if s == null:
			b.text = ""
			b.icon = null
			b.modulate = Color(1, 1, 1, 0.5)
		else:
			var def := ItemDB.get_def(s["id"])
			b.text = def["name"] + ("  x%d" % s["qty"] if s["qty"] > 1 else "")
			b.icon = item_icon(s["id"])
			b.modulate = Color.WHITE
	_refresh_detail()
	_refresh_cells()
	if _inv_stats and player:
		_inv_stats.text = "SLOTS %d/%d  //  LIGHT %d%%  //  %s" % [GameState.inventory.used_slots(), SLOT_COUNT,
			player.flashlight.battery.percent(), {"ok": "STEADY", "injured": "INJURED", "critical": "CRITICAL", "dead": "-"}.get(player.vitals.state(), "")]


func item_icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var path := "res://assets/ui/icons/%s.png" % id
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else _icon_for(ItemDB.get_def(id)["color"])
	_icons[id] = t
	return t


func _icon_for(c: Color) -> Texture2D:
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(10, 38):
		for x in range(10, 38):
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _refresh_detail() -> void:
	var s: Variant = GameState.inventory.get_slot(_sel)
	var kind: Label = inventory_panel.find_child("Kind", true, false) if inventory_panel else null
	if s == null:
		_detail_name.text = "Empty slot"
		_detail_desc.text = "%d of %d slots used. Whatever you are carrying when the run ends, you can leave one thing in the crate for the next member." % [GameState.inventory.used_slots(), SLOT_COUNT]
		_detail_icon.texture = null
		if kind:
			kind.text = ""
		_use_btn.disabled = true
		_drop_btn.disabled = true
		return
	var def := ItemDB.get_def(s["id"])
	_detail_name.text = def["name"] + ("  x%d" % s["qty"] if s["qty"] > 1 else "")
	_detail_desc.text = def["desc"]
	_detail_icon.texture = item_icon(s["id"])
	if kind:
		kind.text = {"battery": "POWER CELL", "part": "PART", "key": "KEY ITEM", "document": "DOCUMENT", "medkit": "MEDICAL"}.get(def["kind"], "ITEM")
	_use_btn.disabled = not def["kind"] in ["battery", "document", "medkit"]
	_use_btn.text = "Read" if def["kind"] == "document" else "Use"
	_drop_btn.disabled = def["kind"] == "key" and s["id"] == "research_drive"


func use_selected() -> void:
	var s: Variant = GameState.inventory.get_slot(_sel)
	if s == null or player == null:
		return
	var def := ItemDB.get_def(s["id"])
	match def["kind"]:
		"battery":
			player.flashlight.replace_battery()
		"medkit":
			if not player.use_medkit():
				show_refusal("Not hurt")
		"document":
			var n := Notes.get_note(s["id"])
			close_inventory()
			open_note(n["title"], n["body"])
	_refresh_inventory()


func drop_selected() -> void:
	var s: Variant = GameState.inventory.get_slot(_sel)
	if s == null or player == null:
		return
	if s["id"] == "research_drive":
		return
	var taken := GameState.inventory.take_from_slot(_sel, 1)
	if taken.is_empty():
		return
	var p := Pickup.new()
	p.item_id = taken["id"]
	p.quantity = 1
	var fwd := player.facing_dir()
	player.get_parent().add_child(p)
	p.global_position = player.global_position + fwd * 0.7 + Vector3.UP * 0.02
	Events.toast.emit("Dropped " + ItemDB.display_name(taken["id"]))
	_refresh_inventory()


# ------------------------------------------------------------------ note / keypad / end
func open_note(title: String, body: String) -> void:
	_note_title.text = title
	_note_body.text = body
	_note_body.scroll_to_line(0)
	note_panel.visible = true
	Events.set_modal(true)
	Sfx.play("pickup_paper", -8.0)
	_note_body.grab_focus()


func close_note() -> void:
	note_panel.visible = false
	Events.set_modal(false)


func open_keypad(k: Node) -> void:
	_keypad = k as Keypad
	_keypad_entry = ""
	_keypad_msg.text = "Enter 4-digit code"
	_keypad_msg.add_theme_color_override("font_color", UIKit.DIM)
	_update_keypad_display()
	keypad_panel.visible = true
	Events.set_modal(true)


func close_keypad() -> void:
	keypad_panel.visible = false
	_keypad = null
	Events.set_modal(false)


func _update_keypad_display() -> void:
	var s := ""
	for i in 4:
		s += (_keypad_entry[i] if i < _keypad_entry.length() else "_") + (" " if i < 3 else "")
	_keypad_display.text = s


func _keypad_press(k: String) -> void:
	if _keypad == null:
		return
	Sfx.play("beep", -6.0, 1.0 + randf() * 0.05)
	match k:
		"CLR":
			_keypad_entry = ""
		"ENT":
			if _keypad_entry.length() == 4:
				if _keypad.submit(_keypad_entry):
					Sfx.play("granted")
					_keypad_msg.text = "ACCESS GRANTED"
					_keypad_msg.add_theme_color_override("font_color", UIKit.GREEN)
					await get_tree().create_timer(0.6).timeout
					close_keypad()
					return
				else:
					Sfx.play("deny")
					_keypad_msg.text = "DENIED" if not _keypad.is_locked_out() else "LOCKED OUT"
					_keypad_msg.add_theme_color_override("font_color", UIKit.RED)
					_keypad_entry = ""
					if _keypad.is_locked_out():
						await get_tree().create_timer(0.8).timeout
						close_keypad()
						return
		_:
			if _keypad_entry.length() < 4:
				_keypad_entry += k
	_update_keypad_display()


func show_end(reason: String) -> void:
	var mins := int(GameState.elapsed) / 60
	var secs := int(GameState.elapsed) % 60
	_end_title.text = "EXPEDITION %d COMPLETE" % GameState.expedition_number if reason == "extracted" else "EXPEDITION LOST"
	_end_stats.text = "You rode the lift up with the Lab 3 research drive.\n\nTime underground: %d:%02d\nFlashlight charge left: %d%%\n\n(Prototype end. Phase 4 adds the handoff: what you leave behind for the next expedition.)" % [mins, secs, int(GameState.battery_charge * 100)]
	if GameState.chapter_run != "":
		var c: Dictionary = Progress.CHAPTERS[maxi(0, Progress.chapter_index(GameState.chapter_run))]
		_end_title.text = ("CHAPTER %s COMPLETE" if reason == "extracted" else "CHAPTER %s LOST") % c["num"]
		_end_stats.text = "%s\n\n%s\nTime: %d:%02d\n\nChapter runs are replays: nothing here is written to your chain." % [
			str(c["title"]).to_upper(), "You rode the lift up." if reason == "extracted" else "Taken in the dark.", mins, secs]
		if _end_again:
			_end_again.text = "Retry chapter"
	end_panel.visible = true
	Events.set_modal(true)
	get_tree().paused = true


# --- cassette "now playing" strip (bottom centre) -----------------------------
func _build_tape() -> void:
	var p := UIKit.panel(Color(0.03, 0.035, 0.04, 0.82), 14)
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = -300
	p.offset_right = 300
	p.offset_top = -150
	p.offset_bottom = -92
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	_tape_label = UIKit.label("", 22, UIKit.TEXT, "ui")
	_tape_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_tape_label)
	_tape_prog = ProgressBar.new()
	_tape_prog.show_percentage = false
	_tape_prog.custom_minimum_size = Vector2(0, 6)
	_tape_prog.max_value = 1.0
	v.add_child(_tape_prog)
	tape_bar = p
	tape_bar.visible = false


func _on_tape_started(title: String, length: float) -> void:
	_tape_label.text = "\u25B6  " + title
	_tape_len = maxf(length, 0.1)
	_tape_t = 0.0
	tape_bar.visible = true


func _process_tape(delta: float) -> void:
	if tape_bar and tape_bar.visible:
		_tape_t += delta
		_tape_prog.value = clampf(_tape_t / _tape_len, 0.0, 1.0)



# ============================================================ Phase 4: survival HUD
var _body_state: Label
var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _vignette: TextureRect
var _hurt_flash := 0.0
var _hide_overlay: Control
var _hide_label: Label

var choice_panel: Control
var _choice_title: Label
var _choice_body: RichTextLabel
var _choice_row: HBoxContainer
var _choice_cb: Callable

var handoff: HandoffScreen
var end_card: Control
var _letterbox: Array[ColorRect] = []
var _caption: Label
var _white: ColorRect
var _hud_items: Array[Control] = []


func _build_vitals() -> void:
	var box: VBoxContainer = _device.get_child(0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	box.move_child(row, 0)
	row.add_child(UIKit.label("PULSE", 16, UIKit.DIM, "mono_bold"))
	_ecg = EcgTrace.new()
	_ecg.custom_minimum_size = Vector2(200, 30)
	row.add_child(_ecg)
	_body_state = UIKit.label("STEADY", 17, UIKit.TEXT, "mono")
	_body_state.custom_minimum_size.x = 92
	row.add_child(_body_state)
	_health_bar = ProgressBar.new()
	_health_bar.visible = false
	_health_bar.max_value = 100.0
	_health_bar.value = 100.0
	box.add_child(_health_bar)
	_stamina_bar = ProgressBar.new()
	_stamina_bar.custom_minimum_size = Vector2(0, 3)
	_stamina_bar.show_percentage = false
	_stamina_bar.max_value = 1.0
	_stamina_bar.step = 0.001
	var sf := StyleBoxFlat.new()
	sf.bg_color = Color(0.9, 0.88, 0.8)
	_stamina_bar.add_theme_stylebox_override("fill", sf)
	box.add_child(_stamina_bar)
	_hud_items.append(_device)

	_vignette = TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.5, 0.0, 0.0, 0.0))
	g.add_point(0.55, Color(0.5, 0.0, 0.0, 0.0))
	g.set_color(g.get_point_count() - 1, Color(0.55, 0.02, 0.02, 0.9))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	gt.width = 256
	gt.height = 256
	_vignette.texture = gt
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	_root.add_child(_vignette)

	_hide_overlay = Control.new()
	_hide_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hide_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hide_overlay.visible = false
	_root.add_child(_hide_overlay)
	for k in 2:
		var bar := ColorRect.new()
		bar.color = Color(0.01, 0.01, 0.012, 0.97)
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if k == 0 else 0.62
		bar.anchor_bottom = 0.38 if k == 0 else 1.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hide_overlay.add_child(bar)
	for k in 4:
		var slat := ColorRect.new()
		slat.color = Color(0.01, 0.01, 0.012, 0.97)
		slat.anchor_right = 1.0
		slat.anchor_top = 0.38 + k * 0.06
		slat.anchor_bottom = slat.anchor_top + 0.022
		slat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hide_overlay.add_child(slat)
	_hide_label = UIKit.label("HIDING   -   E to come out", 26, UIKit.DIM, "ui_bold")
	_hide_label.anchor_left = 0.5
	_hide_label.anchor_right = 0.5
	_hide_label.anchor_top = 1.0
	_hide_label.anchor_bottom = 1.0
	_hide_label.offset_left = -200
	_hide_label.offset_top = -90
	_hide_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hide_label.custom_minimum_size.x = 400
	_hide_overlay.add_child(_hide_label)


func _process_vitals(delta: float) -> void:
	if player == null:
		return
	var v := player.vitals
	_health_bar.value = v.health
	_stamina_bar.value = v.stamina
	var tired := v.stamina < 0.999
	var show_bar := tired or touch != null   # v1.2: always shown with touch controls
	if touch != null and _stamina_bar.custom_minimum_size.y < 8.0:
		_stamina_bar.custom_minimum_size.y = 8.0
	_stamina_bar.modulate.a = move_toward(_stamina_bar.modulate.a, 1.0 if show_bar else 0.0, delta * 3.0)
	_stamina_bar.modulate = Color(1, 0.55, 0.2, _stamina_bar.modulate.a) if v.exhausted else Color(1, 1, 1, _stamina_bar.modulate.a)
	if tired:
		_wake_device(2.0)
	var st := v.state()
	_body_state.text = {"ok": "STEADY", "injured": "INJURED", "critical": "CRITICAL", "dead": "-"}[st]
	var col: Color = UIKit.GREEN if st == "ok" else (UIKit.AMBER if st == "injured" else UIKit.RED)
	_body_state.add_theme_color_override("font_color", col)
	if _ecg:
		_ecg.color = col
		var chased: bool = player.threat_near
		_ecg.bpm = {"ok": 68.0, "injured": 96.0, "critical": 132.0, "dead": 0.0}[st] + (1.0 - v.stamina) * 50.0 + (30.0 if chased else 0.0)
	if v.health != _last_health:
		if _last_health >= 0.0:
			_wake_device(6.0)
		_last_health = v.health
	if st != "ok":
		_wake_device(0.5)
	_hurt_flash = maxf(0.0, _hurt_flash - delta * 1.5)
	var base := 0.0
	if st == "injured":
		base = 0.18
	elif st == "critical":
		base = 0.42 + 0.12 * sin(Time.get_ticks_msec() / 260.0)
	_vignette.modulate.a = clampf(base + _hurt_flash * (0.5 if Settings.get_value("access", "reduce_flashes") else 1.0), 0.0, 1.0)
	_hide_overlay.visible = player.hidden_in != null
	if player.hidden_in != null:
		var cot: bool = player.hidden_in.get("kind") == "cot"
		_hide_label.text = "UNDER THE COT   -   E to come out" if cot else "IN THE LOCKER   -   E to come out"


func _on_hurt(amount: float, _cause: String) -> void:
	_hurt_flash = clampf(amount / 60.0, 0.3, 0.9)


# ------------------------------------------------------------ choice dialog
func _build_choice() -> void:
	var p := _modal_base(880, 560)
	choice_panel = p.get_parent().get_parent()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	p.add_child(v)
	_choice_title = UIKit.label("", 46, UIKit.AMBER, "title")
	v.add_child(_choice_title)
	_choice_body = RichTextLabel.new()
	_choice_body.bbcode_enabled = true
	_choice_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_choice_body.add_theme_font_override("normal_font", UIKit.font("ui"))
	_choice_body.add_theme_font_override("bold_font", UIKit.font("ui_bold"))
	_choice_body.add_theme_font_size_override("normal_font_size", 26)
	_choice_body.add_theme_font_size_override("bold_font_size", 26)
	_choice_body.add_theme_color_override("default_color", UIKit.TEXT)
	v.add_child(_choice_body)
	v.add_child(UIKit.label("This choice is permanent. Every later expedition inherits it.", 20, UIKit.DIM, "ui"))
	_choice_row = HBoxContainer.new()
	_choice_row.add_theme_constant_override("separation", 14)
	v.add_child(_choice_row)


func open_choice(title: String, body: String, options: Array, cb: Callable) -> void:
	_choice_title.text = title
	_choice_body.text = body
	_choice_cb = cb
	for c in _choice_row.get_children():
		c.queue_free()
	var first: Button = null
	for o in options:
		var b := UIKit.button(str(o[1]), 28)
		var id := str(o[0])
		b.pressed.connect(func(): choose(id))
		_choice_row.add_child(b)
		if first == null:
			first = b
	var cancel := UIKit.button("Not now", 24)
	cancel.pressed.connect(close_choice)
	_choice_row.add_child(cancel)
	choice_panel.visible = true
	Events.set_modal(true)
	if first:
		first.grab_focus()


func choose(id: String) -> void:
	close_choice()
	if _choice_cb.is_valid():
		_choice_cb.call(id)


func close_choice() -> void:
	choice_panel.visible = false
	Events.set_modal(false)


# ------------------------------------------------------------ end of an expedition
func fade_to_black(t: float) -> void:
	_fade.color.a = 0.0
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, maxf(0.05, t))
	await tw.finished


func fade_from_black(t: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, maxf(0.05, t))
	await tw.finished


func death_flash(cause: String) -> void:
	_hurt_flash = 1.0
	Sfx.play("keeper_grab" if cause == "keeper" else "heartbeat", 0.0)


func show_handoff() -> void:
	for c in [_obj_title, _prompt_box, tape_bar]:
		if c:
			c.visible = false
	if handoff == null:
		handoff = HandoffScreen.new()
		handoff.hud = self
		_root.add_child(handoff)
	handoff.open()
	handoff.modulate.a = 0.0
	create_tween().tween_property(handoff, "modulate:a", 1.0, 0.6)
	Events.set_modal(true)
	get_tree().paused = true


# ------------------------------------------------------------ cinematics + end card
func _build_cinematic() -> void:
	for k in 2:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if k == 0 else 1.0
		bar.anchor_bottom = 0.0 if k == 0 else 1.0
		bar.offset_bottom = 110 if k == 0 else 0
		bar.offset_top = 0 if k == 0 else -110
		bar.visible = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(bar)
		_letterbox.append(bar)
	_caption = UIKit.label("", 34, Color(0.92, 0.9, 0.85), "ui")
	_caption.anchor_left = 0.0
	_caption.anchor_right = 1.0
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.offset_top = -90
	_caption.offset_bottom = -30
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.visible = false
	_root.add_child(_caption)
	_white = ColorRect.new()
	_white.color = Color(1, 1, 1, 0)
	_white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_white)


func cinematic(on: bool) -> void:
	for b in _letterbox:
		b.visible = on
	_caption.visible = on
	_caption.text = ""
	for c in [_obj_box, _device, _area_box, _toasts, _cross, _vignette, _prompt_box.get_parent()]:
		if c:
			(c as CanvasItem).visible = not on
	if on:
		_fade.color.a = 0.0


func caption(text: String) -> void:
	_caption.text = text
	_caption.modulate.a = 0.0
	create_tween().tween_property(_caption, "modulate:a", 1.0, 0.5)


func flash_white() -> void:
	_white.color.a = 1.0
	create_tween().tween_property(_white, "color:a", 0.0, 2.5)


func show_end_card(id: String) -> void:
	if end_card == null:
		end_card = EndCard.new()
		_root.add_child(end_card)
	end_card.show_ending(id)
	Events.set_modal(true)
	get_tree().paused = true
