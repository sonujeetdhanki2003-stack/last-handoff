class_name FocusRow
extends PanelContainer
## A list row the d-pad can land on (so long lists scroll with a gamepad). Focus
## draws the same amber bar as a menu button.

signal activated


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(func(): grab_focus())
	focus_entered.connect(func():
		Ux.ui_sound("hover")
		queue_redraw())
	focus_exited.connect(queue_redraw)


func _gui_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_accept") or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		activated.emit()


func _draw() -> void:
	if has_focus():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.96, 0.66, 0.24, 0.07))
		draw_rect(Rect2(0, 0, 4, size.y), UIKit.AMBER)
