extends Node
## Persistent player settings, stored in user://settings.cfg.
## Other systems read values with Settings.get_value("section", "key")
## and listen to `changed` to re-apply.

signal changed(section: String, key: String, value: Variant)

const PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Low", "Medium", "High", "Phone"]

const DEFAULTS := {
	"audio": {"master": 0.9, "music": 0.8, "sfx": 0.9, "ambience": 0.8, "heartbeat": true},
	"controls": {"mouse_sensitivity": 0.25, "gamepad_sensitivity": 2.6, "invert_y": false, "camera_side": 1,
		"sprint_mode": 0, "crouch_mode": 1, "vibration": true},
	"video": {"fullscreen": false, "resolution_scale": 1.0, "quality": 2, "vsync": true, "fov": 72.0, "brightness": 1.0,
		"calibrated": false},
	"access": {"subtitles": true, "captions": true, "subtitle_size": 1, "subtitle_bg": 0.55,
		"colorblind_prompts": false, "camera_shake": 1.0, "objective_fade": true, "reduce_flashes": false},
}
const HOLD := 0
const TOGGLE := 1
const SUBTITLE_SIZES := [24, 30, 38, 48]

## Actions the player can rebind, in the order the Controls tab lists them.
const REBINDABLE := ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch",
	"interact", "flashlight", "reload_battery", "inventory", "show_objective", "switch_shoulder"]
const ACTION_NAMES := {
	"move_forward": "Move forward", "move_back": "Move back", "move_left": "Move left",
	"move_right": "Move right", "sprint": "Sprint", "crouch": "Crouch", "interact": "Interact",
	"flashlight": "Flashlight", "reload_battery": "Swap battery cell", "inventory": "Inventory",
	"show_objective": "Show objective", "switch_shoulder": "Switch shoulder", "pause": "Pause",
}

var _default_binds := {}   ## action -> Array[String] codes, captured at start

var _cfg := ConfigFile.new()
var path := PATH  # tests point this elsewhere


func _ready() -> void:
	_ensure_input_actions()
	for a in REBINDABLE + ["pause"]:
		_default_binds[a] = codes_of(a)
	load_settings()
	apply_all()


## Phone platforms start on the Phone preset at 75 % resolution (Phase 6).
func default_of(section: String, key: String) -> Variant:
	if Quality.is_phone_platform() or Harness.has("phone"):
		if section == "video" and key == "quality":
			return Quality.PHONE
		if section == "video" and key == "resolution_scale":
			return 0.75
		if section == "video" and key == "fullscreen":
			return true
	# v1.2: on a touchscreen RUN is a tap (toggle), not a button to keep holding
	if section == "controls" and key == "sprint_mode" and is_touch_device():
		return TOGGLE
	return DEFAULTS.get(section, {}).get(key)


var force_touch := false   ## tests: behave like a touchscreen device
func is_touch_device() -> bool:
	return force_touch or Quality.is_phone_platform() or DisplayServer.is_touchscreen_available() or Harness.has("touch")


func get_value(section: String, key: String) -> Variant:
	var def: Variant = default_of(section, key)
	return _cfg.get_value(section, key, def)


func set_value(section: String, key: String, value: Variant, save := true) -> void:
	_cfg.set_value(section, key, value)
	if section == "controls" and key == "sprint_mode":
		_cfg.set_value("meta", "sprint_mode_chosen", true)   # the player picked it: never migrate it
	_apply_one(section, key)
	changed.emit(section, key, value)
	if save:
		save_settings()


func reset_to_defaults() -> void:
	var cal: bool = bool(get_value("video", "calibrated"))
	_cfg = ConfigFile.new()
	for s in DEFAULTS:
		for k in DEFAULTS[s]:
			_cfg.set_value(s, k, default_of(s, k))
	_cfg.set_value("video", "calibrated", cal)
	reset_binds(false)
	save_settings()
	apply_all()
	for s in DEFAULTS:
		for k in DEFAULTS[s]:
			changed.emit(s, k, default_of(s, k))


func load_settings() -> void:
	_cfg = ConfigFile.new()
	var err := _cfg.load(path)
	# Fill any missing keys with defaults and sanitise types/ranges.
	for s in DEFAULTS:
		for k in DEFAULTS[s]:
			var d: Variant = default_of(s, k)
			var v: Variant = _cfg.get_value(s, k, d)
			if typeof(v) != typeof(d) and not (typeof(d) == TYPE_FLOAT and typeof(v) == TYPE_INT):
				v = d
			_cfg.set_value(s, k, _clamp(s, k, v))
	_load_binds()
	# v1.2 migration: a 1.0/1.1 phone save holds RUN = Hold only because that was the old
	# default. If the player never chose it, move it to the new touch default (Toggle) once.
	var migrated := false
	if is_touch_device() and not bool(_cfg.get_value("meta", "sprint_mode_chosen", false)) \
			and not bool(_cfg.get_value("meta", "sprint_v12", false)):
		_cfg.set_value("controls", "sprint_mode", TOGGLE)
		_cfg.set_value("meta", "sprint_v12", true)
		migrated = true
	if err != OK or migrated:
		save_settings()


func save_settings() -> Error:
	return _cfg.save(path)


func _clamp(section: String, key: String, v: Variant) -> Variant:
	match key:
		"master", "music", "sfx", "ambience":
			return clampf(float(v), 0.0, 1.0)
		"mouse_sensitivity":
			return clampf(float(v), 0.02, 1.0)
		"gamepad_sensitivity":
			return clampf(float(v), 0.5, 6.0)
		"resolution_scale":
			return clampf(float(v), 0.5, 1.0)
		"quality":
			return clampi(int(v), 0, 3)
		"fov":
			return clampf(float(v), 55.0, 95.0)
		"brightness":
			return clampf(float(v), 0.6, 1.6)
		"camera_side":
			return -1 if int(v) < 0 else 1
		"sprint_mode", "crouch_mode":
			return clampi(int(v), 0, 1)
		"subtitle_size":
			return clampi(int(v), 0, SUBTITLE_SIZES.size() - 1)
		"subtitle_bg", "camera_shake":
			return clampf(float(v), 0.0, 1.0)
	return v


func apply_all() -> void:
	for s in DEFAULTS:
		for k in DEFAULTS[s]:
			_apply_one(s, k)


func _apply_one(section: String, key: String) -> void:
	var v: Variant = get_value(section, key)
	match [section, key]:
		["audio", "master"]:
			_set_bus("Master", v)
		["audio", "music"]:
			_set_bus("Music", v)
		["audio", "sfx"]:
			_set_bus("SFX", v)
		["audio", "ambience"]:
			_set_bus("Ambience", v)
		["video", "fullscreen"]:
			if DisplayServer.get_name() != "headless":
				# on a phone "windowed" means the status + navigation bars cover the game: always immersive
				var fs: bool = v or Quality.is_phone_platform()
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED)
		["video", "vsync"]:
			if DisplayServer.get_name() != "headless":
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if v else DisplayServer.VSYNC_DISABLED)
		["video", "resolution_scale"]:
			var vp := get_viewport()
			if vp:
				vp.scaling_3d_scale = float(v)
				# FSR 1 upscaling looks better than bilinear below 100 %.
				vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if float(v) < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
		["video", "quality"]:
			_apply_quality(int(v))


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


func _apply_quality(q: int) -> void:
	# Global, renderer-level quality (Quality.P is the one table). Per-scene effects are
	# applied by WorldEnv; per-node draw distances and the shadow budget by Level.
	Quality.apply_viewport(get_viewport(), q)


# --- Input map ---------------------------------------------------------------
# Defined in code so the project file stays readable; rebinding UI is Phase 5.

func _ensure_input_actions() -> void:
	_action("move_forward", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_action("move_back", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_action("move_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("move_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("look_up", [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_action("look_down", [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_action("look_left", [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_action("look_right", [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_action("sprint", [KEY_SHIFT], [JOY_BUTTON_LEFT_STICK, JOY_BUTTON_LEFT_SHOULDER])
	_action("crouch", [KEY_C, KEY_CTRL], [JOY_BUTTON_B])
	_action("interact", [KEY_E], [JOY_BUTTON_A])
	_action("flashlight", [KEY_F], [JOY_BUTTON_Y])
	_action("reload_battery", [KEY_R], [JOY_BUTTON_X])
	_action("inventory", [KEY_TAB, KEY_I], [JOY_BUTTON_BACK])
	_action("pause", [KEY_ESCAPE], [JOY_BUTTON_START])
	_action("switch_shoulder", [KEY_V], [JOY_BUTTON_RIGHT_STICK])
	_action("ui_use", [KEY_U], [JOY_BUTTON_X])
	_action("ui_drop", [KEY_G], [JOY_BUTTON_Y])
	_action("show_objective", [KEY_J], [JOY_BUTTON_DPAD_UP])
	_action("ui_tab_prev", [KEY_Q, KEY_PAGEUP], [JOY_BUTTON_LEFT_SHOULDER])
	_action("ui_tab_next", [KEY_E, KEY_PAGEDOWN], [JOY_BUTTON_RIGHT_SHOULDER])
	_action("debug_overlay", [KEY_F3], [])
	_action("skip", [KEY_SPACE, KEY_ESCAPE, KEY_ENTER], [JOY_BUTTON_START, JOY_BUTTON_A])
	# menus: the left stick and the d-pad both navigate
	_action("ui_up", [], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_action("ui_down", [], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	_action("ui_left", [], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("ui_right", [], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("ui_accept", [], [JOY_BUTTON_A])
	_action("ui_cancel", [], [JOY_BUTTON_B])


func _action(action_name: String, keys: Array, buttons: Array = [], axes: Array = []) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		_add_unique(action_name, e)
	for b in buttons:
		var j := InputEventJoypadButton.new()
		j.button_index = b
		_add_unique(action_name, j)
	for a in axes:
		var m := InputEventJoypadMotion.new()
		m.axis = a[0]
		m.axis_value = a[1]
		_add_unique(action_name, m)


func _add_unique(action_name: String, e: InputEvent) -> void:
	var code := event_code(e)
	for x in InputMap.action_get_events(action_name):
		if event_code(x) == code:
			return
	InputMap.action_add_event(action_name, e)


# --- Rebinding -----------------------------------------------------------------
# Each action has a keyboard/mouse binding and a gamepad binding. Rebinding a slot
# replaces that family of events (the stick axes on the move actions stay). A key
# already used by another rebindable action is swapped onto it, so nothing is left
# unbound. Bindings are stored in [binds] as short codes ("k:69", "j:0", "m:1").

static func event_code(e: InputEvent) -> String:
	if e is InputEventKey:
		var k: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		return "k:%d" % k
	if e is InputEventMouseButton:
		return "m:%d" % e.button_index
	if e is InputEventJoypadButton:
		return "j:%d" % e.button_index
	if e is InputEventJoypadMotion:
		return "a:%d:%d" % [e.axis, 1 if e.axis_value > 0 else -1]
	return ""


static func code_event(code: String) -> InputEvent:
	var p := code.split(":")
	if p.size() < 2:
		return null
	match p[0]:
		"k":
			var e := InputEventKey.new()
			e.physical_keycode = int(p[1]) as Key
			return e
		"m":
			var m := InputEventMouseButton.new()
			m.button_index = int(p[1]) as MouseButton
			return m
		"j":
			var j := InputEventJoypadButton.new()
			j.button_index = int(p[1]) as JoyButton
			return j
		"a":
			if p.size() < 3:
				return null
			var a := InputEventJoypadMotion.new()
			a.axis = int(p[1]) as JoyAxis
			a.axis_value = float(p[2])
			return a
	return null


static func is_pad_code(code: String) -> bool:
	return code.begins_with("j:") or code.begins_with("a:")


func codes_of(action: String) -> Array:
	var out := []
	if InputMap.has_action(action):
		for e in InputMap.action_get_events(action):
			var c := event_code(e)
			if c != "":
				out.append(c)
	return out


func _set_codes(action: String, codes: Array) -> void:
	InputMap.action_erase_events(action)
	for c in codes:
		var e := code_event(str(c))
		if e:
			InputMap.action_add_event(action, e)


## The first binding of the given family ("kb" or "pad"), or "".
func binding(action: String, slot: String) -> String:
	for c in codes_of(action):
		if (slot == "pad") == is_pad_code(c) and not c.begins_with("a:"):
			return c
	if slot == "pad":
		for c in codes_of(action):
			if c.begins_with("a:"):
				return c
	return ""


## Rebind `action`'s keyboard or gamepad slot to `e`. Returns the action that lost
## the key in a swap ("" when there was no conflict).
func rebind(action: String, e: InputEvent, save := true) -> String:
	var code := event_code(e)
	if code == "" or not REBINDABLE.has(action) or code.begins_with("a:"):
		return ""
	var slot := "pad" if is_pad_code(code) else "kb"
	var old := binding(action, slot)
	var swapped := ""
	for other in REBINDABLE:
		if other != action and codes_of(other).has(code):
			var oc := codes_of(other).filter(func(c): return c != code)
			if old != "" and not oc.has(old):
				oc.append(old)
			_set_codes(other, oc)
			swapped = other
	var codes := codes_of(action).filter(func(c): return (slot == "pad") != is_pad_code(c) or c.begins_with("a:"))
	codes.insert(0 if slot == "kb" else codes.size(), code)
	_set_codes(action, codes)
	_store_binds()
	if save:
		save_settings()
	changed.emit("binds", action, code)
	return swapped


func reset_binds(save := true) -> void:
	for a in _default_binds:
		_set_codes(a, _default_binds[a])
	if _cfg.has_section("binds"):
		_cfg.erase_section("binds")
	if save:
		save_settings()
	changed.emit("binds", "", "")


func _store_binds() -> void:
	for a in REBINDABLE:
		if codes_of(a) != _default_binds.get(a, []):
			_cfg.set_value("binds", a, codes_of(a))
		elif _cfg.has_section_key("binds", a):
			_cfg.erase_section_key("binds", a)


func _load_binds() -> void:
	for a in _default_binds:
		_set_codes(a, _default_binds[a])
	if not _cfg.has_section("binds"):
		return
	for a in _cfg.get_section_keys("binds"):
		var v: Variant = _cfg.get_value("binds", a)
		if not REBINDABLE.has(a) or typeof(v) != TYPE_ARRAY:
			_cfg.erase_section_key("binds", a)
			continue
		var good := (v as Array).filter(func(c): return typeof(c) == TYPE_STRING and code_event(c) != null)
		if good.is_empty():
			continue
		_set_codes(a, good)


## Human label for a binding code, e.g. "E", "Shift", "Mouse 1", "A", "LB".
static func code_label(code: String) -> String:
	if code == "":
		return "-"
	var p := code.split(":")
	match p[0]:
		"k":
			var k := int(p[1])
			var special := {KEY_SHIFT: "Shift", KEY_CTRL: "Ctrl", KEY_ALT: "Alt", KEY_SPACE: "Space", KEY_TAB: "Tab",
				KEY_ESCAPE: "Esc", KEY_ENTER: "Enter", KEY_BACKSPACE: "Bksp", KEY_UP: "Up", KEY_DOWN: "Down",
				KEY_LEFT: "Left", KEY_RIGHT: "Right", KEY_CAPSLOCK: "Caps"}
			if special.has(k):
				return special[k]
			return OS.get_keycode_string(k)
		"m":
			return {1: "LMB", 2: "RMB", 3: "MMB", 4: "Wheel up", 5: "Wheel down", 8: "Mouse 4", 9: "Mouse 5"}.get(int(p[1]), "Mouse %s" % p[1])
		"j":
			return {0: "A", 1: "B", 2: "X", 3: "Y", 4: "View", 5: "Guide", 6: "Menu", 7: "LS", 8: "RS", 9: "LB", 10: "RB",
				11: "D-pad up", 12: "D-pad down", 13: "D-pad left", 14: "D-pad right"}.get(int(p[1]), "Pad %s" % p[1])
		"a":
			var ax := int(p[1])
			if ax == JOY_AXIS_TRIGGER_LEFT:
				return "LT"
			if ax == JOY_AXIS_TRIGGER_RIGHT:
				return "RT"
			return ("L-stick" if ax < 2 else "R-stick") + " " + (("left" if int(p[2]) < 0 else "right") if ax % 2 == 0 else ("up" if int(p[2]) < 0 else "down"))
	return code


func action_label(action: String, pad: bool) -> String:
	return code_label(binding(action, "pad" if pad else "kb"))
