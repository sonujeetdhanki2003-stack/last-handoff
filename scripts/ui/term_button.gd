class_name TermButton
extends Button
## Menu button in the field-terminal style: the mouse hovering it takes focus (so
## mouse, keyboard and gamepad share one highlight), a caret marks the focused
## item, and it clicks.

var _caret := 0.0


func _ready() -> void:
	mouse_entered.connect(func():
		if not disabled and focus_mode != FOCUS_NONE and is_visible_in_tree():
			grab_focus())
	focus_entered.connect(func():
		Ux.ui_sound("hover")
		queue_redraw())
	focus_exited.connect(queue_redraw)
	pressed.connect(func(): Ux.ui_sound("click"))
	add_theme_font_override("font", UIKit.font("ui_bold") if get_theme_font_size("font_size") >= 28 else UIKit.font("ui"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW and has_focus():
		pass


func _draw() -> void:
	if has_focus() and not disabled:
		var h := size.y
		var x := 7.0
		var cy := h * 0.5
		draw_colored_polygon(PackedVector2Array([Vector2(x, cy - 6), Vector2(x + 7, cy), Vector2(x, cy + 6)]), UIKit.AMBER)
		draw_rect(Rect2(0, 0, 4, h), UIKit.AMBER)


func _gui_input(e: InputEvent) -> void:
	# a focused, enabled button also accepts the gamepad's A via ui_accept (Godot
	# default); nothing else to do here.
	pass
