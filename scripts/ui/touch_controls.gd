class_name TouchControls
extends Control
## Phase 6 on-screen controls for touchscreens (Android). Shown only when the device
## has a touchscreen (or with --touch for testing):
##   * left side: a floating move stick (put a thumb down anywhere in the left 40 %)
##   * right half: swipe to look
##   * buttons: interact, flashlight, crouch, sprint, inventory, pause
##   * while a panel is open (inventory, note, keypad, choice): a single BACK button
## Every button feeds the same input actions the keyboard and pad use, so all the
## game logic (hold-to-interact, crouch/sprint modes, menus) is unchanged.

const BUTTONS := [
	# name, action, label, anchor (fraction of screen from bottom-right), radius px
	["Interact", "interact", "USE", Vector2(0.085, 0.20), 64.0],
	["Flashlight", "flashlight", "LIGHT", Vector2(0.185, 0.13), 50.0],
	["Crouch", "crouch", "CROUCH", Vector2(0.075, 0.42), 46.0],
	["Sprint", "sprint", "RUN", Vector2(0.175, 0.33), 58.0],   # v1.2: bigger (was 46), slide-on works
	["Inventory", "inventory", "BAG", Vector2(0.06, 0.86), 38.0],
	["Pause", "pause", "II", Vector2(0.135, 0.86), 38.0],
	["Cell", "reload_battery", "CELL", Vector2(0.27, 0.10), 38.0],   # shown only with a spare cell
]
const STICK_RADIUS := 110.0
const LOOK_GAIN := 0.55

var player: Node = null          # Player (camera rig via player.cam)
var run_ring: RunRing
var stick_vec := Vector2.ZERO
var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_finger := -1
var _buttons := {}               # name -> TouchScreenButton
var _back: TouchScreenButton
var _stick_base: Control
var _stick_knob: Control
var safe_rect := Rect2()         # the area the buttons live in (viewport units)
var _last_vs := Vector2.ZERO
var _last_safe := Vector4.ZERO


static func wanted() -> bool:
	return DisplayServer.is_touchscreen_available() or Harness.has("touch")


func _init() -> void:
	name = "TouchControls"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_stick_base = _disc(STICK_RADIUS, Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.35))
	_stick_base.name = "StickBase"
	add_child(_stick_base)
	_stick_knob = _disc(42.0, Color(0.96, 0.66, 0.24, 0.45), Color(1, 1, 1, 0.6))
	_stick_knob.name = "StickKnob"
	add_child(_stick_knob)
	for b in BUTTONS:
		var tsb := _make_button(b[0], b[1], b[2], b[4])
		_buttons[b[0]] = tsb
		add_child(tsb)
	# v1.2: a thumb sliding onto RUN presses it; a stamina ring around it
	_buttons["Sprint"].passby_press = true
	run_ring = RunRing.new()
	run_ring.name = "RunRing"
	_buttons["Sprint"].add_child(run_ring)
	_back = _make_button("Back", "ui_cancel", "BACK", 40.0)
	add_child(_back)
	_layout()
	get_viewport().size_changed.connect(_layout)


func button(n: String) -> TouchScreenButton:
	return _buttons.get(n)


func button_names() -> Array:
	return _buttons.keys()


func _make_button(n: String, action: String, text: String, r: float) -> TouchScreenButton:
	var tsb := TouchScreenButton.new()
	tsb.name = n
	tsb.action = action
	var sh := CircleShape2D.new()
	sh.radius = r
	tsb.shape = sh
	tsb.shape_centered = true
	tsb.texture_normal = _circle_tex(int(r), Color(0.06, 0.07, 0.07, 0.55), Color(0.85, 0.83, 0.78, 0.55))
	tsb.texture_pressed = _circle_tex(int(r), Color(0.96, 0.66, 0.24, 0.55), Color(1, 1, 1, 0.8))
	tsb.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	var l := UIKit.label(text, int(clampf(r * 0.36, 13, 22)), Color(0.93, 0.91, 0.86, 0.9), "mono_bold")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(r * 2, r * 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tsb.add_child(l)
	tsb.set_meta("radius", r)
	return tsb


func _circle_tex(r: int, fill: Color, ring: Color) -> ImageTexture:
	var s := r * 2
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(r, r)
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d <= r:
				img.set_pixel(x, y, ring if d > r - 3.0 else fill)
	return ImageTexture.create_from_image(img)


func _disc(r: float, fill: Color, ring: Color) -> Control:
	var t := TextureRect.new()
	t.texture = _circle_tex(int(r), fill, ring)
	t.size = Vector2(r * 2, r * 2)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.visible = false
	return t


## Buttons are placed in the safe area (notch / rounded corners / gesture bar excluded),
## by a height-based unit so 4:3 tablets and 20:9 phones keep the same thumb spacing.
func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var m := Ux.safe_margins(get_viewport())
	safe_rect = Rect2(m.x, m.y, vs.x - m.x - m.z, vs.y - m.y - m.w)
	var u := safe_rect.size.y   # 900 at the 1600x900 design size
	for b in BUTTONS:
		var tsb: TouchScreenButton = _buttons[b[0]]
		var r: float = b[4]
		# design positions were fractions of a 1600 x 900 screen: convert x to height units
		var off := Vector2(b[3].x * 1600.0 / 900.0, b[3].y) * u
		var c := safe_rect.end - off
		c.x = clampf(c.x, safe_rect.position.x + r, safe_rect.end.x - r)
		c.y = clampf(c.y, safe_rect.position.y + r, safe_rect.end.y - r)
		tsb.position = c - Vector2(r, r)
	_back.position = Vector2(safe_rect.end.x - 40.0 * 2 - 24.0, safe_rect.position.y + 24.0)


func _button_at(pos: Vector2) -> bool:
	for tsb in _buttons.values() + [_back]:
		if not tsb.visible:
			continue
		var r: float = tsb.get_meta("radius")
		# v1.2: exactly the button's own hit circle (r + 8 left a dead ring around each button
		# that swallowed the touch: no stick, no look, and the button never registered it)
		if pos.distance_to(tsb.position + Vector2(r, r)) <= r:
			return true
	return false


func _gameplay() -> bool:
	return not Events.modal_open and not get_tree().paused and player != null and is_instance_valid(player) and player.control_enabled


func _process(_d: float) -> void:
	var play := _gameplay()
	for tsb in _buttons.values():
		tsb.visible = play
	_buttons["Cell"].visible = play and GameState.inventory.count("battery") > 0
	if run_ring and play and player:
		run_ring.stamina = player.vitals.stamina
		run_ring.exhausted = player.vitals.exhausted
		run_ring.radius = float(_buttons["Sprint"].get_meta("radius"))
		run_ring.queue_redraw()
	# v1.2: RUN glows amber while you run (or it is latched), flashes red when it can't
	var run_b: TouchScreenButton = _buttons.get("Sprint")
	if run_b and play:
		if float(player.get("run_block_t")) > 0.0:
			var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 60.0)
			run_b.modulate = Color(1.0, 0.35 + 0.2 * k, 0.3, 1.0)
		elif player.get("running") or player.get("sprint_latched"):
			run_b.modulate = Color(1.0, 0.75, 0.3, 1.0)
		else:
			var why: String = player.call("run_blocked_reason_now") if player.has_method("run_blocked_reason_now") else ""
			run_b.modulate = Color(0.6, 0.6, 0.6, 0.6) if why != "" else Color(1, 1, 1, 1)
	# rotation (sensor landscape flips the notch side) or a cut-out change: re-place the buttons
	var vs := get_viewport().get_visible_rect().size
	var sm := Ux.safe_margins(get_viewport())
	if vs != _last_vs or sm != _last_safe:
		_last_vs = vs
		_last_safe = sm
		_layout()
	# BACK closes inventory / notes / keypad; the pause and handoff screens have their own buttons
	_back.visible = Events.modal_open and not get_tree().paused
	if not play and _stick_finger >= 0:
		_release_stick()
	_stick_base.visible = play and _stick_finger >= 0
	_stick_knob.visible = _stick_base.visible
	if _stick_base.visible:
		_stick_base.position = _stick_origin - Vector2(STICK_RADIUS, STICK_RADIUS)
		_stick_knob.position = _stick_origin + stick_vec * STICK_RADIUS - Vector2(42, 42)


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	var vs := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			if not _gameplay() or _button_at(e.position):
				return
			if e.position.x < vs.x * 0.4 and _stick_finger < 0 and e.position.x >= safe_rect.position.x * 0.5:
				_stick_finger = e.index
				_stick_origin = e.position
				_set_stick(Vector2.ZERO)
			elif e.position.x >= vs.x * 0.5 and _look_finger < 0:
				_look_finger = e.index
		else:
			if e.index == _stick_finger:
				_release_stick()
			elif e.index == _look_finger:
				_look_finger = -1
	else:
		var d := event as InputEventScreenDrag
		if d.index == _stick_finger:
			_set_stick((d.position - _stick_origin) / STICK_RADIUS)
		elif d.index == _look_finger and _gameplay():
			look(d.relative)


## Swipe-look: same feel as the mouse, scaled for a thumb.
func look(rel: Vector2) -> void:
	if player and player.cam:
		player.cam.apply_mouse_look(rel * LOOK_GAIN)


func _set_stick(v: Vector2) -> void:
	if v.length() > 1.0:
		v = v.normalized()
	stick_vec = v
	_axis("move_right", maxf(v.x, 0.0))
	_axis("move_left", maxf(-v.x, 0.0))
	_axis("move_back", maxf(v.y, 0.0))
	_axis("move_forward", maxf(-v.y, 0.0))


func _release_stick() -> void:
	_stick_finger = -1
	_set_stick(Vector2.ZERO)


func _axis(action: String, s: float) -> void:
	if s > 0.08:
		Input.action_press(action, s)
	elif Input.is_action_pressed(action):
		Input.action_release(action)



## v1.2: the stamina ring drawn around RUN (a thick arc: full = a full circle), orange and
## pulsing while you are out of breath.
class RunRing extends Control:
	var stamina := 1.0
	var exhausted := false
	var radius := 58.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(radius, radius)
		var r := radius + 7.0
		draw_arc(c, r, 0.0, TAU, 48, Color(0, 0, 0, 0.45), 9.0, true)
		var col := Color(1.0, 0.45, 0.15, 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() / 150.0))) if exhausted else Color(0.92, 0.9, 0.82, 0.9)
		if stamina > 0.005:
			draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * clampf(stamina, 0.0, 1.0), 48, col, 7.0, true)
