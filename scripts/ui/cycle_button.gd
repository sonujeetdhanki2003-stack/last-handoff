class_name CycleButton
extends TermButton
## A value picker for gamepad and keyboard: "<  Medium  >". Left/right (or a click
## / accept) steps through the options.

signal value_changed(index: int)

var options: Array = []
var index := 0


func _ready() -> void:
	super._ready()
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	pressed.connect(func(): step(1))
	_refresh()


func set_index(i: int, emit := false) -> void:
	if options.is_empty():
		return
	index = posmod(i, options.size())
	_refresh()
	if emit:
		value_changed.emit(index)


func step(d: int) -> void:
	set_index(index + d, true)
	Ux.ui_sound("tab")


func _refresh() -> void:
	if options.is_empty():
		return
	text = "<   %s   >" % str(options[index])


func _gui_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_left", true):
		step(-1)
		accept_event()
	elif e.is_action_pressed("ui_right", true):
		step(1)
		accept_event()
