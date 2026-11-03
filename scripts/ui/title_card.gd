class_name TitleCard
extends Control
## "EXPEDITION 11" / "PRIYA RAO" typed in over black with a low hit, held, faded.

var done := false
static var time_scale := 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func _w(sec: float) -> void:
	await get_tree().create_timer(sec / time_scale, true, false, true).timeout


var bg_alpha := 0.88


func play(line1: String, line2: String, line3 := "", hold := 2.4) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(v)
	var l1 := UIKit.label("", 26, UIKit.AMBER, "mono")
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l1)
	var l2 := UIKit.label(line2.to_upper(), 92, UIKit.TEXT, "title")
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l2.modulate.a = 0.0
	v.add_child(l2)
	var r := UIKit.rule(UIKit.AMBER, 2, 0)
	r.custom_minimum_size = Vector2(0, 2)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(r)
	var l3 := UIKit.label(line3, 24, UIKit.DIM, "ui")
	l3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l3.modulate.a = 0.0
	v.add_child(l3)
	if bg_alpha >= 1.0:
		bg.color.a = 1.0
	else:
		create_tween().tween_property(bg, "color:a", bg_alpha, 0.4 / time_scale)
	Ux.ui_sound("title")
	await _w(0.35)
	var full := line1.to_upper()
	var tt := 0.0
	var shown := 0
	while shown < full.length():
		var n := mini(full.length(), int(tt * time_scale / 0.035) + 1)
		if n != shown:
			if n / 2 != shown / 2:
				Ux.ui_sound("hover", 1.4)
			shown = n
			l1.text = full.substr(0, n)
		if shown >= full.length():
			break
		await get_tree().process_frame
		tt += get_process_delta_time()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l2, "modulate:a", 1.0, 0.6 / time_scale)
	tw.tween_property(r, "custom_minimum_size:x", 420.0, 0.8 / time_scale).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l3, "modulate:a", 1.0, 0.9 / time_scale).set_delay(0.3 / time_scale)
	await _w(hold)
	var out := create_tween()
	out.tween_property(self, "modulate:a", 0.0, 0.9 / time_scale)
	await out.finished
	done = true
