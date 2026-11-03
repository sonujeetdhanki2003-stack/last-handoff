class_name GlyphBadge
extends Control
## Button prompt for an input action that follows the device in use and the
## player's bindings: a keycap for keyboard/mouse, a round face button for a
## gamepad. Colour-blind-safe mode drops the face-button colours for a uniform
## high-contrast badge (the letter carries the meaning).

var action := "interact"
var font_size := 20
var _text := ""
var _pad := false

const PAD_COLORS := {"A": Color(0.36, 0.75, 0.32), "B": Color(0.86, 0.3, 0.26), "X": Color(0.27, 0.52, 0.9), "Y": Color(0.93, 0.76, 0.2)}


func _init(a := "interact", fs := 20) -> void:
	action = a
	font_size = fs
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	Ux.device_changed.connect(func(_p): refresh())
	Settings.changed.connect(func(_s, _k, _v): refresh())
	refresh()


func set_action(a: String) -> void:
	action = a
	refresh()


func refresh() -> void:
	_pad = Ux.using_pad
	_text = Settings.action_label(action, _pad) if InputMap.has_action(action) else action
	if action == "ui_accept":
		_text = "A" if _pad else "Enter"
	elif action == "ui_cancel":
		_text = "B" if _pad else "Esc"
	if Ux.using_touch and Ux.TOUCH_LABELS.has(action):
		_pad = false
		_text = Ux.TOUCH_LABELS[action]
	var f := UIKit.font("mono_bold")
	var w := f.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var h := font_size * 1.45
	custom_minimum_size = Vector2(maxf(h, w + font_size * 0.9), h)
	queue_redraw()


func _draw() -> void:
	var f := UIKit.font("mono_bold")
	var h := size.y
	var cb := bool(Settings.get_value("access", "colorblind_prompts"))
	var round_btn := _pad and _text.length() == 1
	var fill := Color(0.9, 0.89, 0.85)
	var ink := Color(0.05, 0.05, 0.05)
	if round_btn and not cb:
		fill = PAD_COLORS.get(_text, fill)
		ink = Color(0.02, 0.02, 0.02)
	if cb:
		fill = Color(1, 1, 1)
		ink = Color(0, 0, 0)
	if round_btn:
		var c := size * 0.5
		draw_circle(c, h * 0.5, Color(0, 0, 0, 0.6))
		draw_circle(c, h * 0.5 - 2.0, fill)
	else:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.55))
		draw_rect(r.grow(-2), fill)
		draw_rect(Rect2(2, size.y - 5, size.x - 4, 3), fill.darkened(0.25))
	var tw := f.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var asc := f.get_ascent(font_size)
	var desc := f.get_descent(font_size)
	draw_string(f, Vector2((size.x - tw) * 0.5, (h + asc - desc) * 0.5 - 1.0), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
