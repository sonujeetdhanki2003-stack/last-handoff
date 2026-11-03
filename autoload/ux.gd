extends Node
## UX services shared by every screen: which input device is in use (for button
## prompts), UI sounds, scene transitions (fade out -> change -> fade in),
## subtitles/captions and the expedition title card.

signal device_changed(pad: bool)
signal app_backgrounded
signal app_foregrounded
signal subtitle_shown(kind: String, speaker: String, text: String)
signal title_card_done

var last_title := ""

var using_pad := false
var using_touch := false          ## last input was a finger (prompts show the on-screen button names)
var in_background := false        ## window lost focus / app paused (Android home, alt-tab)
var _bg_paused_tree := false
var _synthetic_esc := 0
var safe_override := Rect2()      ## tests: pretend the screen has this safe area (viewport units)
var _fade_layer: CanvasLayer
var _fade: ColorRect
var _sub_layer: CanvasLayer
var subtitles: SubtitleBox
var _card_layer: CanvasLayer
var title_card: Control
var _ui_players: Array[AudioStreamPlayer] = []
var _ui_streams := {}
var _quiet_until := 0
var transitioning := false
var log_subtitles: Array = []   ## every line shown, for tests ([kind, speaker, text])

const UI_SOUNDS := {
	"hover": ["res://audio/ui/ui_hover.ogg", -20.0],
	"click": ["res://audio/ui/ui_click.ogg", -10.0],
	"back": ["res://audio/ui/ui_back.ogg", -11.0],
	"tab": ["res://audio/ui/ui_tab.ogg", -12.0],
	"stamp": ["res://audio/ui/ui_stamp.ogg", -6.0],
	"type": ["res://audio/ui/ui_type.ogg", -14.0],
	"title": ["res://audio/stingers/sting_title.ogg", -6.0],
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.theme = UIKit.make_theme()
	Input.joy_connection_changed.connect(_on_joy_connection)
	# a phone starts with its fingers: show the touch button names from the first frame
	using_touch = (OS.has_feature("mobile") and DisplayServer.is_touchscreen_available()) or Harness.has("touch")
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_ui_players.append(p)
	for k in UI_SOUNDS:
		if ResourceLoader.exists(UI_SOUNDS[k][0]):
			_ui_streams[k] = load(UI_SOUNDS[k][0])
	_sub_layer = CanvasLayer.new()
	_sub_layer.layer = 60
	add_child(_sub_layer)
	subtitles = SubtitleBox.new()
	_sub_layer.add_child(subtitles)
	_card_layer = CanvasLayer.new()
	_card_layer.layer = 70
	add_child(_card_layer)
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade)


func _input(e: InputEvent) -> void:
	if _synthetic_esc > 0 and e is InputEventKey and e.keycode == KEY_ESCAPE:
		_synthetic_esc -= 1
		return
	var touch := using_touch
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		touch = true
	elif e is InputEventJoypadButton or (e is InputEventKey and e.pressed):
		touch = false
	elif e is InputEventMouseButton and e.pressed and e.device != InputEvent.DEVICE_ID_EMULATION:
		touch = false
	if touch != using_touch:
		using_touch = touch
		if touch:
			using_pad = false
		device_changed.emit(using_pad)
	if e.device == InputEvent.DEVICE_ID_EMULATION or e is InputEventScreenTouch or e is InputEventScreenDrag:
		return   # a finger (or the back button) posing as a mouse/key: not a keyboard/mouse player
	var pad := using_pad
	if e is InputEventJoypadButton and e.pressed:
		pad = true
	elif e is InputEventJoypadMotion and absf(e.axis_value) > 0.45:
		pad = true
	elif (e is InputEventKey and e.pressed) or (e is InputEventMouseButton and e.pressed):
		pad = false
	elif e is InputEventMouseMotion and e.relative.length() > 6.0:
		pad = false
	if pad != using_pad:
		using_pad = pad
		device_changed.emit(pad)


## Prompt text for an action on the current device, e.g. "E" or "A" (or "USE" on a touchscreen).
func glyph(action: String) -> String:
	if using_touch and TOUCH_LABELS.has(action):
		return TOUCH_LABELS[action]
	return Settings.action_label(action, using_pad)


## The on-screen button that does each action (TouchControls).
const TOUCH_LABELS := {"interact": "USE", "flashlight": "LIGHT", "crouch": "CROUCH", "sprint": "RUN",
	"inventory": "BAG", "pause": "II", "reload_battery": "CELL", "ui_cancel": "BACK", "ui_accept": "TAP",
	"ui_use": "USE", "ui_drop": "DROP", "show_objective": "OBJ", "skip": "TAP"}


# ------------------------------------------------------------------ safe area
## Screen-edge insets (notch, rounded corners, gesture bar) in viewport units:
## Vector4(left, top, right, bottom). Zero on desktop.
func safe_margins(vp: Viewport = null) -> Vector4:
	if vp == null:
		vp = get_viewport()
	var vs := vp.get_visible_rect().size
	if safe_override.size != Vector2.ZERO:
		var r := safe_override
		return Vector4(r.position.x, r.position.y, maxf(vs.x - r.end.x, 0.0), maxf(vs.y - r.end.y, 0.0))
	if DisplayServer.get_name() == "headless" or not OS.has_feature("mobile"):
		return Vector4.ZERO
	# polled by the HUD and touch overlay: re-read the display at most twice a second
	var now := Time.get_ticks_msec()
	if now - _safe_read_ms < 500 and vs == _safe_read_vs:
		return _safe_cached
	_safe_read_ms = now
	_safe_read_vs = vs
	_safe_cached = _read_safe(vs)
	return _safe_cached


var _safe_read_ms := -100000
var _safe_read_vs := Vector2.ZERO
var _safe_cached := Vector4.ZERO


func _read_safe(vs: Vector2) -> Vector4:
	var win := Vector2(DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0 or win.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	var k := vs / win
	var l := maxf(float(safe.position.x), 0.0) * k.x
	var t := maxf(float(safe.position.y), 0.0) * k.y
	var r2 := maxf(win.x - float(safe.end.x), 0.0) * k.x
	var b := maxf(win.y - float(safe.end.y), 0.0) * k.y
	return Vector4(minf(l, vs.x * 0.2), minf(t, vs.y * 0.2), minf(r2, vs.x * 0.2), minf(b, vs.y * 0.2))


## Fit a full-screen CanvasLayer inside the safe area (uniform scale, centred in it).
func fit_layer_to_safe_area(layer: CanvasLayer) -> void:
	var m := safe_margins(layer.get_viewport())
	var vs := layer.get_viewport().get_visible_rect().size
	if m == Vector4.ZERO or vs.x <= 0:
		layer.offset = Vector2.ZERO
		layer.scale = Vector2.ONE
		return
	var avail := Vector2(vs.x - m.x - m.z, vs.y - m.y - m.w)
	var s := minf(avail.x / vs.x, avail.y / vs.y)
	layer.scale = Vector2(s, s)
	layer.offset = Vector2(m.x, m.y) + (avail - vs * s) * 0.5


# ------------------------------------------------------------------ app lifecycle
## Focus lost / app sent to the background (Android home or recent apps, a call,
## alt-tab on desktop): pause the game, silence audio, save the run. The Android
## back button acts like Esc (closes the open panel, opens the pause menu).
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			app_background(what == NOTIFICATION_APPLICATION_PAUSED)
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			app_foreground()
		NOTIFICATION_WM_CLOSE_REQUEST:
			_autosave()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			go_back()


func _lifecycle_enabled() -> bool:
	# screenshot / benchmark automation under a virtual display must not pause itself
	return not (Harness.has("shot") or Harness.has("nolifecycle"))


func app_background(save := true) -> void:
	if not _lifecycle_enabled():
		return
	if save:
		_autosave()
	if in_background:
		return
	in_background = true
	AudioServer.set_bus_mute(0, true)
	if open_pause_menu():
		pass   # stays open when they come back; they choose when to resume
	elif not get_tree().paused:
		get_tree().paused = true
		_bg_paused_tree = true
	app_backgrounded.emit()


func _game() -> Node:
	var g := get_tree().get_first_node_in_group("game")
	return g if g else get_tree().current_scene


## Opens the in-game pause menu if an expedition is being played right now.
func open_pause_menu() -> bool:
	var sc := _game()
	var pm: Node = sc.get_node_or_null("PauseMenu") if sc else null
	var playing := pm != null and pm.has_method("open") and not get_tree().paused and not Events.modal_open \
			and not bool(sc.get("ended")) and sc.get("player") != null and bool(sc.player.control_enabled)
	if playing:
		pm.open()
	return playing


## A controller unplugged (or its battery died) mid-run: drop any held stick/trigger
## input so the member doesn't keep walking, and pause if it was the device in use.
func _on_joy_connection(device: int, connected: bool) -> void:
	if connected:
		return
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch", "interact"]:
		if InputMap.has_action(a):
			Input.action_release(a)
	if using_pad and Input.get_connected_joypads().is_empty():
		open_pause_menu()
		using_pad = false
		device_changed.emit(false)


func app_foreground() -> void:
	if not in_background:
		return
	in_background = false
	Settings._apply_one("audio", "master")   # restores the player's own mute/volume
	if _bg_paused_tree:
		_bg_paused_tree = false
		get_tree().paused = false
	app_foregrounded.emit()


func _autosave() -> void:
	var sc := _game()
	if sc and sc.has_method("autosave"):
		sc.autosave()


## Android back button = Esc: every screen already closes on Esc, and Esc in play opens the pause menu.
func go_back() -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = KEY_ESCAPE
		k.physical_keycode = KEY_ESCAPE
		k.pressed = pressed
		Input.parse_input_event(k)
	_synthetic_esc = 2   # the press and release above are not a real keyboard: keep touch prompts


# ------------------------------------------------------------------ sounds
## Programmatic focus changes (opening a screen) should not click.
func quiet_focus(ms := 120) -> void:
	_quiet_until = Time.get_ticks_msec() + ms


func ui_sound(id: String, pitch := 1.0) -> void:
	if id == "hover" and Time.get_ticks_msec() < _quiet_until:
		return
	if not _ui_streams.has(id):
		return
	for p in _ui_players:
		if not p.playing:
			p.stream = _ui_streams[id]
			p.volume_db = UI_SOUNDS[id][1]
			p.pitch_scale = pitch * randf_range(0.97, 1.03)
			p.play()
			return


# ------------------------------------------------------------------ transitions
func fade_out(t := 0.45) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, maxf(t, 0.01))
	await tw.finished


func fade_in(t := 0.6) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, maxf(t, 0.01))
	await tw.finished


func set_black(a: float) -> void:
	_fade.color.a = a


func fade_alpha() -> float:
	return _fade.color.a


## Fade to black, swap scenes, fade back in. Safe to call while paused.
func change_scene(path: String, out_t := 0.45, in_t := 0.7) -> void:
	if transitioning:
		return
	transitioning = true
	await fade_out(out_t)
	subtitles.clear()
	get_tree().paused = false
	Events.set_modal(false)
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	transitioning = false
	await fade_in(in_t)


# ------------------------------------------------------------------ subtitles
## kind: "speech" (tapes, voices), "pa" (station public address), "sound" ([captions]).
func subtitle(text: String, speaker := "", dur := 3.0, kind := "speech") -> void:
	if kind == "sound":
		if not bool(Settings.get_value("access", "captions")):
			return
	elif not bool(Settings.get_value("access", "subtitles")):
		return
	log_subtitles.append([kind, speaker, text])
	if log_subtitles.size() > 200:
		log_subtitles.pop_front()
	subtitles.show_line(text, speaker, dur, kind)
	subtitle_shown.emit(kind, speaker, text)


func clear_subtitles() -> void:
	subtitles.clear()


# ------------------------------------------------------------------ title card
## "EXPEDITION 11 - PRIYA RAO": types itself in over black, holds, fades.
func show_title_card(line1: String, line2: String, line3 := "", hold := 2.4, opaque := false) -> void:
	if is_instance_valid(title_card):
		title_card.queue_free()
	last_title = "%s  %s" % [line1.to_upper(), line2.to_upper()]
	var c := TitleCard.new()
	c.bg_alpha = 1.0 if opaque else 0.88
	title_card = c
	_card_layer.add_child(c)
	await c.play(line1, line2, line3, hold)
	if is_instance_valid(c):
		c.queue_free()
	title_card_done.emit()
