extends CanvasLayer
## Esc / Start: the pause screen. Resume, inventory, settings, or leave the
## expedition. The right card shows the member's field status.

var _root: Control
var _main: VBoxContainer
var _settings: SettingsMenu
var _card: TermPanel
var _status: RichTextLabel
var _sub: Label
var _bright: BrightnessScreen
var buttons := {}
var _give_up_armed := false
var _foot: Control


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	_root.add_child(UIKit.backdrop(0.72))
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.add_theme_constant_override("margin_left", 112)
	mc.add_theme_constant_override("margin_right", 110)
	mc.add_theme_constant_override("margin_top", 120)
	mc.add_theme_constant_override("margin_bottom", 110)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(mc)
	var cols := HBoxContainer.new()
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(cols)
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 6)
	_main.custom_minimum_size.x = 560
	cols.add_child(_main)
	cols.add_child(UIKit.expand())
	_main.add_child(UIKit.label("HALDEN DEEP  //  LEVEL B2  //  EXPEDITION SUSPENDED", 17, UIKit.AMBER_DIM, "mono"))
	_main.add_child(UIKit.shadowed(UIKit.label("PAUSED", 88, UIKit.TEXT, "title")))
	_main.add_child(UIKit.rule(UIKit.AMBER, 3, 140))
	_sub = UIKit.label("", 24, UIKit.DIM, "ui")
	_sub.name = "Sub"
	_main.add_child(_sub)
	_main.add_child(UIKit.spacer(26))
	for pair in [["Resume", "RESUME", resume], ["Inventory", "INVENTORY", _open_inventory], ["Settings", "SETTINGS", _open_settings],
			["Menu", "SAVE AND QUIT TO MENU", _to_menu], ["GiveUp", "GIVE UP THIS EXPEDITION", _give_up], ["Quit", "SAVE AND QUIT TO DESKTOP", _quit]]:
		var b := UIKit.button(pair[1], 32)
		b.name = pair[0]
		b.pressed.connect(pair[2])
		_main.add_child(b)
		buttons[pair[0]] = b
	buttons["GiveUp"].focus_exited.connect(_disarm)

	_card = UIKit.term_panel("FIELD STATUS", 28)
	_card.custom_minimum_size = Vector2(530, 0)
	_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cols.add_child(_card)
	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.scroll_active = false
	_status.custom_minimum_size.x = 470
	_status.add_theme_font_override("normal_font", UIKit.font("mono"))
	_status.add_theme_font_override("bold_font", UIKit.font("mono_bold"))
	_status.add_theme_font_size_override("normal_font_size", 19)
	_status.add_theme_font_size_override("bold_font_size", 19)
	_status.add_theme_color_override("default_color", UIKit.TEXT)
	_status.add_theme_constant_override("line_separation", 6)
	_card.add_child(_status)

	var foot := UIKit.hint_bar([["ui_accept", "Select"], ["ui_cancel", "Resume"]])
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(112, 900 - 74)
	_root.add_child(foot)
	_foot = foot

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_settings = SettingsMenu.new()
	_settings.visible = false
	_settings.back.connect(_close_settings)
	_settings.calibrate = _open_brightness
	center.add_child(_settings)
	_bright = BrightnessScreen.new()
	_bright.done.connect(func():
		_settings.visible = true
		Ux.quiet_focus()
		(_settings.find_child("Calibrate", true, false) as Control).grab_focus())
	_root.add_child(_bright)
	UIKit.chain_focus(_main.get_children().filter(func(c): return c is Button))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or (_root.visible and event.is_action_pressed("ui_cancel")):
		if Events.modal_open and not _root.visible:
			return
		if _bright.visible or _settings.visible:
			return   # those screens handle their own back
		if _root.visible:
			resume()
		elif event.is_action_pressed("pause"):
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	_root.visible = true
	_main.visible = true
	_card.visible = true
	_foot.visible = true
	_settings.visible = false
	_disarm()
	var who := ("  -  " + GameState.member_name) if GameState.member_name != "" else ""
	_sub.text = "Expedition %d%s" % [GameState.expedition_number, who]
	_refresh_status()
	get_tree().paused = true
	Events.set_modal(true)
	_set_hud(false)
	Ux.ui_sound("back")
	Ux.quiet_focus()
	buttons["Resume"].grab_focus()


func _set_hud(v: bool) -> void:
	var hud := get_parent().get_node_or_null("HUD") as CanvasLayer if get_parent() else null
	if hud:
		hud.visible = v


func _refresh_status() -> void:
	var g := get_parent()
	var p: Node = g.get("player") if g else null
	var lines := []
	var t := int(GameState.elapsed)
	var obj := GameState.objectives.current_id()
	lines.append("[color=#f5a83d]OBJECTIVE[/color]  %s" % (GameState.objectives.label(obj) if obj != "" else "Get out."))
	lines.append("")
	lines.append("[color=#8a8d88]UNDERGROUND[/color]   %d:%02d" % [t / 60, t % 60])
	lines.append("[color=#8a8d88]DEEPEST[/color]       %s" % Lore.depth_name(GameState.deepest))
	if p and p.get("vitals"):
		var st: String = p.vitals.state()
		lines.append("[color=#8a8d88]CONDITION[/color]     %s" % {"ok": "Steady", "injured": "Injured, limping", "critical": "Critical", "dead": "-"}.get(st, st))
		lines.append("[color=#8a8d88]LIGHT[/color]         %d%%   + %d spare cell(s)" % [p.flashlight.battery.percent(), GameState.inventory.count("battery")])
	if GameState.chain_mode:
		lines.append("[color=#8a8d88]MARA'S TAPES[/color]  %d / 4" % Legacy.mara_tapes_found())
		lines.append("[color=#8a8d88]RELAY[/color]         member %d of the chain" % (Legacy.expeditions_done() + 1))
	_status.text = "\n".join(lines)


func resume() -> void:
	if not _root.visible:
		return
	_root.visible = false
	get_tree().paused = false
	Events.set_modal(false)
	_set_hud(true)
	Ux.ui_sound("back")


func is_open() -> bool:
	return _root.visible


func current_screen() -> String:
	if not _root.visible:
		return ""
	if _bright.visible:
		return "brightness"
	return "settings" if _settings.visible else "main"


func _open_inventory() -> void:
	resume()
	var hud: Node = get_parent().get_node_or_null("HUD")
	if hud and hud.has_method("open_inventory"):
		hud.open_inventory()


func _open_settings() -> void:
	_main.visible = false
	_card.visible = false
	_foot.visible = false
	_settings.visible = true
	_settings.set_tab(0, false)
	_settings.focus_first()


func _open_brightness() -> void:
	_settings.visible = false
	_bright.open()


func _close_settings() -> void:
	_settings.visible = false
	_main.visible = true
	_card.visible = true
	_foot.visible = true
	Ux.quiet_focus()
	buttons["Settings"].grab_focus()


func _save_run() -> void:
	var g := get_parent()
	if g and g.has_method("autosave"):
		g.autosave()


func _quit() -> void:
	_save_run()
	await Ux.fade_out(0.3)
	get_tree().quit()


func _disarm() -> void:
	_give_up_armed = false
	if buttons.has("GiveUp"):
		buttons["GiveUp"].text = "GIVE UP THIS EXPEDITION"
		buttons["GiveUp"].remove_theme_color_override("font_color")
		buttons["GiveUp"].remove_theme_color_override("font_focus_color")


func _give_up() -> void:
	var b: Button = buttons["GiveUp"]
	if not _give_up_armed:
		_give_up_armed = true
		b.text = "SURE? SIT DOWN IN THE DARK AND WAIT  (PRESS AGAIN)"
		b.add_theme_color_override("font_color", UIKit.RED)
		b.add_theme_color_override("font_focus_color", UIKit.RED)
		return
	_disarm()
	resume()
	GameState.active = false
	Events.expedition_ended.emit("gave_up")


func _to_menu() -> void:
	_save_run()
	Ux.change_scene("res://scenes/ui/main_menu.tscn")
