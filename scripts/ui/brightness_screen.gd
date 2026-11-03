class_name BrightnessScreen
extends Control
## First-launch brightness calibration (also reachable from Settings > Graphics).
## Three marks on black at rising darkness; the player raises or lowers brightness
## until the faintest one is only just visible. Left/right adjust, A/Enter accepts.

signal done

var from_settings := false
var _marks: Array[TextureRect] = []
var _val: Label
var _slider: HSlider
var _accept: Button
const BASE := [0.028, 0.07, 0.17]


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	v.custom_minimum_size.x = 1100
	c.add_child(v)
	var hd := UIKit.header("Calibrate brightness", "HD-B2 // DISPLAY CHECK", 50)
	v.add_child(hd)
	var tx := UIKit.label("The station is dark on purpose. Adjust until the left mark is barely visible and the right one is clear.", 25, UIKit.DIM, "ui")
	tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tx)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 90)
	v.add_child(row)
	var tex: Texture2D = load("res://assets/decals/mark_eye.png")
	for i in 3:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		row.add_child(col)
		var t := TextureRect.new()
		t.texture = tex
		t.custom_minimum_size = Vector2(230, 230)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		col.add_child(t)
		_marks.append(t)
		var l := UIKit.label(["BARELY VISIBLE", "FAINT", "CLEAR"][i], 18, UIKit.FAINT, "mono")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.add_theme_constant_override("separation", 18)
	v.add_child(srow)
	srow.add_child(UIKit.label("BRIGHTNESS", 22, UIKit.TEXT, "ui_bold"))
	_slider = HSlider.new()
	_slider.min_value = 0.6
	_slider.max_value = 1.6
	_slider.step = 0.05
	_slider.custom_minimum_size = Vector2(520, 40)
	_slider.focus_mode = Control.FOCUS_ALL
	_slider.value_changed.connect(_on_value)
	srow.add_child(_slider)
	_val = UIKit.label("", 22, UIKit.AMBER, "mono")
	_val.custom_minimum_size.x = 80
	srow.add_child(_val)
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 20)
	v.add_child(brow)
	brow.add_child(UIKit.hint_bar([["ui_left", "Adjust"], ["ui_accept", "Accept"]]))
	_accept = UIKit.button("Accept", 26)
	_accept.name = "Accept"
	_accept.custom_minimum_size.x = 180
	_accept.pressed.connect(accept)
	brow.add_child(_accept)
	var dflt := UIKit.button("Default", 26)
	dflt.name = "Default"
	dflt.pressed.connect(func(): _slider.value = 1.0)
	brow.add_child(dflt)
	visible = false


func _ready() -> void:
	_slider.focus_neighbor_bottom = _slider.get_path_to(_accept)
	_accept.focus_neighbor_top = _accept.get_path_to(_slider)


func open() -> void:
	visible = true
	_slider.set_value_no_signal(float(Settings.get_value("video", "brightness")))
	_on_value(_slider.value)
	Ux.quiet_focus()
	_slider.grab_focus()


func _on_value(x: float) -> void:
	_val.text = "%d%%" % roundi(x * 100.0)
	for i in 3:
		var b: float = BASE[i] * x
		_marks[i].modulate = Color(b, b, b * 0.97)
	Settings.set_value("video", "brightness", x, false)


func adjust(d: float) -> void:
	_slider.value = clampf(_slider.value + d, 0.6, 1.6)


func accept() -> void:
	Settings.set_value("video", "brightness", _slider.value, false)
	Settings.set_value("video", "calibrated", true)
	visible = false
	done.emit()


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		accept()
	elif e.is_action_pressed("ui_accept") and _slider.has_focus():
		get_viewport().set_input_as_handled()
		accept()
