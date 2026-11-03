extends TestCase
## Phase 6 touch controls (Android): the nodes exist, each button drives its action,
## the move stick and swipe-look work through real screen-touch events, buttons and
## sticks don't fight, the panel BACK button closes panels, and the Phone preset is
## what a phone starts on.

var g: Node
var p: Player
var tc: TouchControls


## Positions in the tests are in the game's 1600x900-style canvas; the OS sends touches
## in window pixels, so convert like a real screen would.
func _win(v: Vector2) -> Vector2:
	return tc.get_viewport().get_final_transform() * v


func _touch(i: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = _win(pos)
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _drag(i: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = _win(pos)
	e.relative = tc.get_viewport().get_final_transform().basis_xform(rel)
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _btn_center(n: String) -> Vector2:
	var b := tc.button(n)
	var r: float = b.get_meta("radius")
	return b.position + Vector2(r, r)


func run() -> void:
	t.check(TouchControls.wanted() == (DisplayServer.is_touchscreen_available() or Harness.has("touch")), "touch UI only when a touchscreen is present (or --touch)")
	Legacy.begin_expedition()
	g = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(g)
	p = g.player
	await t.physics(8)
	# on this desktop test box there is no touchscreen: build it the way the HUD does on a phone
	if g.hud.touch == null:
		var tl := CanvasLayer.new()
		tl.layer = 6
		g.hud.add_child(tl)
		tc = TouchControls.new()
		tc.player = p
		tl.add_child(tc)
	else:
		tc = g.hud.touch
	await t.physics(2)
	var expect := {"Interact": "interact", "Flashlight": "flashlight", "Crouch": "crouch", "Sprint": "sprint", "Inventory": "inventory", "Pause": "pause"}
	for n in expect:
		var b := tc.button(n)
		t.check(b != null and b is TouchScreenButton, "%s button exists" % n)
		if b:
			t.eq(b.action, expect[n], "%s button drives the '%s' action" % [n, expect[n]])
			t.check(b.visible, "%s button visible during play" % n)
			t.check(InputMap.has_action(b.action), "'%s' is a real input action" % b.action)
	var vs := tc.get_viewport().get_visible_rect().size
	for n in expect:
		var c := _btn_center(n)
		t.check(c.x > vs.x * 0.5 and c.x < vs.x and c.y > 0 and c.y < vs.y, "%s sits on screen, right side (%.0f, %.0f)" % [n, c.x, c.y])
	# buttons don't overlap each other
	var names := expect.keys()
	var overlap := false
	for i in names.size():
		for j in range(i + 1, names.size()):
			var ri: float = tc.button(names[i]).get_meta("radius")
			var rj: float = tc.button(names[j]).get_meta("radius")
			if _btn_center(names[i]).distance_to(_btn_center(names[j])) < ri + rj:
				overlap = true
	t.check(not overlap, "no two buttons overlap")

	# --- move stick (left side)
	var o := Vector2(vs.x * 0.18, vs.y * 0.7)
	_touch(0, o, true)
	_drag(0, o + Vector2(0, -90), Vector2(0, -90))
	await t.physics(2)
	t.check(Input.get_vector("move_left", "move_right", "move_forward", "move_back").y < -0.6, "dragging the left stick up = move forward (%.2f)" % Input.get_vector("move_left", "move_right", "move_forward", "move_back").y)
	var start := p.global_position
	await t.physics(30)
	t.check(p.global_position.distance_to(start) > 0.4, "the player walks (%.2f m)" % p.global_position.distance_to(start))
	_drag(0, o + Vector2(300, 0), Vector2(300, 90))
	await t.physics(1)
	t.near(tc.stick_vec.length(), 1.0, 0.01, "the stick clamps at full deflection")
	_touch(0, o, false)
	await t.physics(2)
	t.eq(Input.get_vector("move_left", "move_right", "move_forward", "move_back"), Vector2.ZERO, "lifting the thumb stops the player")

	# --- swipe look (right half), while the stick is held: two thumbs at once
	_touch(0, o, true)
	_drag(0, o + Vector2(-60, 0), Vector2(-60, 0))
	var yaw0: float = p.cam.yaw
	var lp := Vector2(vs.x * 0.62, vs.y * 0.45)
	_touch(1, lp, true)
	_drag(1, lp + Vector2(80, 0), Vector2(80, 0))
	await t.physics(1)
	t.check(absf(angle_difference(deg_to_rad(p.cam.yaw), deg_to_rad(yaw0))) > deg_to_rad(3.0), "swiping on the right turns the camera (%.1f -> %.1f)" % [yaw0, p.cam.yaw])
	t.check(Input.is_action_pressed("move_left"), "while the other thumb keeps moving")
	_touch(1, lp + Vector2(80, 0), false)
	_touch(0, o, false)
	await t.physics(1)
	# a finger-emulated mouse drag must not also turn the camera
	var yaw1: float = p.cam.yaw
	var mm := InputEventMouseMotion.new()
	mm.device = InputEvent.DEVICE_ID_EMULATION
	mm.relative = Vector2(200, 0)
	Input.parse_input_event(mm)
	Input.flush_buffered_events()
	await t.physics(1)
	t.near(p.cam.yaw, yaw1, 0.01, "touch-emulated mouse motion is ignored by the camera (no double look)")

	# --- buttons
	var lit := p.flashlight.on
	var fc := _btn_center("Flashlight")
	_touch(3, fc, true)
	await t.physics(2)
	t.check(Input.is_action_pressed("flashlight"), "pressing LIGHT presses the flashlight action")
	_touch(3, fc, false)
	await t.physics(2)
	t.check(p.flashlight.on != lit, "and toggles the torch")
	t.check(not Input.is_action_pressed("move_forward") and tc.stick_vec == Vector2.ZERO, "a button press never starts the stick or look")
	var sc := _btn_center("Sprint")
	_touch(4, sc, true)
	await t.physics(2)
	t.check(Input.is_action_pressed("sprint"), "holding RUN holds sprint")
	_touch(4, sc, false)
	await t.physics(2)
	t.check(not Input.is_action_pressed("sprint"), "releasing RUN releases it")
	var cc := _btn_center("Crouch")
	_touch(5, cc, true)
	await t.physics(2)
	_touch(5, cc, false)
	await t.physics(4)
	t.check(p.crouching, "CROUCH crouches")
	_touch(5, cc, true)
	await t.physics(2)
	_touch(5, cc, false)
	await t.physics(20)

	# --- inventory: BAG opens it, the touch BACK button closes it
	var ic := _btn_center("Inventory")
	_touch(6, ic, true)
	await t.physics(2)
	_touch(6, ic, false)
	await t.physics(3)
	t.check(Events.modal_open, "BAG opens the inventory")
	await t.physics(2)
	t.check(not tc.button("Interact").visible, "play buttons hide while a panel is open")
	t.check(tc._back.visible, "a BACK button shows instead")
	var bc: Vector2 = tc._back.position + Vector2(40, 40)
	_touch(7, bc, true)
	await t.physics(2)
	_touch(7, bc, false)
	await t.physics(4)
	t.check(not Events.modal_open, "BACK closes the inventory by touch")

	# --- pause by touch, and the pause menu is a tappable menu
	var pc := _btn_center("Pause")
	_touch(8, pc, true)
	await t.physics(2)
	_touch(8, pc, false)
	await t.physics(4)
	t.check(t.sandbox.get_tree().paused, "II pauses the game")
	var pm: Node = g.find_child("PauseMenu", true, false)
	var btns: Array = pm.find_children("*", "BaseButton", true, false).filter(func(b): return b.is_visible_in_tree()) if pm else []
	t.check(btns.size() >= 3, "the pause menu shows tappable buttons (%d)" % btns.size())
	t.check(btns.all(func(b): return b.mouse_filter != Control.MOUSE_FILTER_IGNORE), "and they take taps (emulated from touch)")
	t.check(bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch")), "taps reach every menu button (touch emulates the mouse)")
	_touch(8, pc, true)
	await t.physics(1)
	_touch(8, pc, false)
	var esc := InputEventAction.new()
	esc.action = "pause"
	esc.pressed = true
	Input.parse_input_event(esc)
	await t.physics(4)
	esc = InputEventAction.new()
	esc.action = "pause"
	esc.pressed = false
	Input.parse_input_event(esc)
	await t.physics(4)
	t.sandbox.get_tree().paused = false
	Events.set_modal(false)

	# --- phone settings
	t.eq(int(ProjectSettings.get_setting("display/window/handheld/orientation")), DisplayServer.SCREEN_SENSOR_LANDSCAPE, "landscape lock (either way up)")
	var ph := Quality.get_preset(Quality.PHONE)
	t.check(not ph.ssao and not ph.ssil and not ph.vol_fog, "Phone preset: no SSAO / SSIL / volumetric fog")
	t.check(ph.pos_atlas <= 1024 and ph.max_shadow_lights <= 3, "Phone preset: small shadow maps, few shadowed lamps")
	t.eq(Settings.QUALITY_NAMES[Quality.PHONE], "Phone", "the Settings menu lists the Phone preset")
	t.check(Quality.is_phone_platform() == OS.has_feature("android") or OS.has_feature("mobile"), "phone detection follows the platform")
	g.queue_free()
	await t.physics(3)
