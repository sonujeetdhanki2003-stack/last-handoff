class_name EndCard
extends Control
## Full-screen card after an ending sequence: the ending's name, what it means,
## and the chain's record (members, losses, decisions, tapes, time underground).

signal shown

var fully_shown := false
var _title: Label
var _sub: Label
var _text: Label
var _stats: RichTextLabel
var _code: Label
var _menu: Button


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	add_child(UIKit.backdrop(0.0))
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 60)
	c.add_child(h)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size.x = 760
	h.add_child(v)
	_code = UIKit.label("", 17, UIKit.AMBER_DIM, "mono")
	v.add_child(_code)
	_title = UIKit.label("", 104, UIKit.TEXT, "title")
	v.add_child(_title)
	v.add_child(UIKit.rule(UIKit.AMBER, 3, 180))
	_sub = UIKit.label("", 30, UIKit.AMBER, "ui_bold")
	v.add_child(_sub)
	v.add_child(UIKit.spacer(8))
	_text = UIKit.label("", 26, Color(0.82, 0.81, 0.77), "ui")
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_text)
	v.add_child(UIKit.spacer(18))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	_menu = UIKit.button("MAIN MENU", 30)
	_menu.name = "Menu"
	_menu.custom_minimum_size.x = 260
	_menu.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.pressed.connect(func(): Ux.change_scene("res://scenes/ui/main_menu.tscn", 0.8, 0.8))
	row.add_child(_menu)
	var card := UIKit.term_panel("CHAIN RECORD", 28)
	card.custom_minimum_size = Vector2(470, 0)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(card)
	_stats = RichTextLabel.new()
	_stats.bbcode_enabled = true
	_stats.fit_content = true
	_stats.scroll_active = false
	_stats.custom_minimum_size.x = 410
	_stats.add_theme_font_override("normal_font", UIKit.font("mono"))
	_stats.add_theme_font_override("bold_font", UIKit.font("mono_bold"))
	_stats.add_theme_font_size_override("normal_font_size", 19)
	_stats.add_theme_font_size_override("bold_font_size", 19)
	_stats.add_theme_color_override("default_color", UIKit.TEXT)
	_stats.add_theme_constant_override("line_separation", 7)
	card.add_child(_stats)


func stats_text() -> String:
	return _stats.text


func show_ending(id: String) -> void:
	var e: Dictionary = Lore.ENDINGS.get(id, {"title": id.to_upper(), "sub": "", "text": ""})
	var order := ["seal", "broadcast", "break"]
	_code.text = "HALDEN DEEP  //  ENDING %02d / 03" % (order.find(id) + 1)
	_title.text = str(e["title"])
	_sub.text = e["sub"]
	_text.text = e["text"]
	var hist: Array = Legacy.chain.get("history", [])
	var lost := 0
	var total_t := 0
	for hh in hist:
		total_t += int(hh.get("time", 0))
		if str(hh.get("end", "")) in ["died", "injured"]:
			lost += 1
	var lines := []
	lines.append("[color=#8a8d88]MEMBERS SENT[/color]    %d   [color=#5c605d](+%d before them)[/color]" % [hist.size(), Lore.GHOSTS.size()])
	lines.append("[color=#8a8d88]LOST IN THE DARK[/color] %d" % lost)
	lines.append("[color=#8a8d88]TIME UNDERGROUND[/color] %d:%02d" % [total_t / 60, total_t % 60])
	lines.append("[color=#8a8d88]MARA'S TAPES[/color]     %d / 4" % Legacy.mara_tapes_found())
	lines.append("")
	lines.append("[color=#f5a83d]DECISIONS[/color]")
	var any := false
	for d in Lore.DECISIONS:
		var ch := Legacy.decision(d)
		if ch != "":
			lines.append("- " + Lore.decision_label(d, ch))
			any = true
	if not any:
		lines.append("- none taken")
	_stats.text = "\n".join(lines)
	visible = true
	fully_shown = false
	Ux.clear_subtitles()
	Sfx.stop_pa()
	modulate.a = 0.0
	Sfx.play("sting_ending", -4.0)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 1.2)
	tw.tween_callback(func():
		fully_shown = true
		shown.emit())
	Ux.quiet_focus(1500)
	_menu.grab_focus()


func _unhandled_input(e: InputEvent) -> void:
	if visible and fully_shown and (e.is_action_pressed("ui_cancel") or e.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		_menu.grab_focus()
