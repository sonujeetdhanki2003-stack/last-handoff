class_name SubtitleBox
extends Control
## Bottom-centre subtitles. Speech shows the speaker in amber, PA lines are
## marked, sound captions are [bracketed] and dimmer. Size and background
## opacity come from Settings > Accessibility. Several lines can stack.

var _box: VBoxContainer
var _lines: Array = []   ## [PanelContainer, time_left]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_box = VBoxContainer.new()
	_box.anchor_left = 0.5
	_box.anchor_right = 0.5
	_box.anchor_top = 1.0
	_box.anchor_bottom = 1.0
	_box.offset_left = -720
	_box.offset_right = 720
	_box.offset_bottom = -150
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.alignment = BoxContainer.ALIGNMENT_END
	_box.add_theme_constant_override("separation", 6)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)


func show_line(text: String, speaker: String, dur: float, kind: String) -> void:
	var fs: int = Settings.SUBTITLE_SIZES[int(Settings.get_value("access", "subtitle_size"))]
	var bga := float(Settings.get_value("access", "subtitle_bg"))
	# the same caption again just refreshes its timer
	for l in _lines:
		if l[2] == kind + speaker + text:
			l[1] = dur
			return
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, bga)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 4
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	rt.scroll_active = false
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.add_theme_font_override("normal_font", UIKit.font("ui"))
	rt.add_theme_font_override("bold_font", UIKit.font("ui_bold"))
	rt.add_theme_font_override("italics_font", UIKit.font("ui"))
	for k in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		rt.add_theme_font_size_override(k, fs)
	rt.add_theme_color_override("default_color", UIKit.TEXT)
	rt.add_theme_constant_override("outline_size", 0 if bga > 0.3 else 6)
	rt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	var t := text
	match kind:
		"sound":
			t = "[color=#b9bcb5][i][%s][/i][/color]" % text
		"pa":
			t = "[color=#7fd0e0][b]PA:[/b][/color] " + text
		_:
			if speaker != "":
				t = "[color=#f5a83d][b]%s:[/b][/color] %s" % [speaker.to_upper(), text]
	rt.text = t
	# wrap long lines at ~70% of the screen width
	var font := UIKit.font("ui")
	var w := font.get_string_size(text + speaker + "    ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var maxw := 1300.0
	if w > maxw:
		rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rt.custom_minimum_size.x = maxw
	p.add_child(rt)
	_box.add_child(p)
	_lines.append([p, dur, kind + speaker + text])
	while _lines.size() > 3:
		var old: Array = _lines.pop_front()
		if is_instance_valid(old[0]):
			old[0].queue_free()
	p.modulate.a = 0.0
	create_tween().tween_property(p, "modulate:a", 1.0, 0.15)


func _process(delta: float) -> void:
	for i in range(_lines.size() - 1, -1, -1):
		var l: Array = _lines[i]
		l[1] -= delta
		if l[1] <= 0.0:
			var p: Control = l[0]
			_lines.remove_at(i)
			if is_instance_valid(p):
				var tw := p.create_tween()
				tw.tween_property(p, "modulate:a", 0.0, 0.25)
				tw.tween_callback(p.queue_free)


func visible_lines() -> Array:
	var out := []
	for l in _lines:
		out.append(l[2])
	return out


func clear() -> void:
	for l in _lines:
		if is_instance_valid(l[0]):
			l[0].queue_free()
	_lines.clear()
