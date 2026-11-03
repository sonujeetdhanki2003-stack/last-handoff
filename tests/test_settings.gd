extends TestCase

func run() -> void:
	var path := "user://test_settings.cfg"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var old_path: String = Settings.path
	Settings.path = path
	Settings.load_settings()
	t.check(FileAccess.file_exists(path), "settings file created with defaults")
	t.near(Settings.get_value("controls", "mouse_sensitivity"), 0.25, 0.0001, "default sensitivity")
	Settings.set_value("controls", "mouse_sensitivity", 0.6)
	Settings.set_value("controls", "invert_y", true)
	Settings.set_value("audio", "master", 0.3)
	Settings.set_value("video", "quality", 1)
	Settings.set_value("video", "resolution_scale", 0.75)
	# reload from disk
	Settings.load_settings()
	t.near(Settings.get_value("controls", "mouse_sensitivity"), 0.6, 0.0001, "sensitivity persisted")
	t.eq(Settings.get_value("controls", "invert_y"), true, "invert persisted")
	t.eq(Settings.get_value("video", "quality"), 1, "quality persisted")
	Settings.apply_all()
	var bus := AudioServer.get_bus_index("Master")
	t.near(db_to_linear(AudioServer.get_bus_volume_db(bus)), 0.3, 0.01, "master volume applied to the audio bus")
	t.near(get_viewport_scale(), 0.75, 0.001, "resolution scale applied to the viewport")
	# corrupt / out of range values are sanitised
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "mouse_sensitivity", 50.0)
	cfg.set_value("video", "quality", "ultra")
	cfg.set_value("audio", "master", -3)
	cfg.save(path)
	Settings.load_settings()
	t.near(Settings.get_value("controls", "mouse_sensitivity"), 1.0, 0.0001, "out-of-range sensitivity clamped")
	t.eq(Settings.get_value("video", "quality"), 2, "wrong-type quality falls back to default")
	t.near(Settings.get_value("audio", "master"), 0.0, 0.0001, "negative volume clamped to 0")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("this is [[[ not a config")
	f.close()
	Settings.load_settings()
	t.near(Settings.get_value("audio", "master"), 0.9, 0.0001, "garbage file falls back to defaults")
	Settings.reset_to_defaults()
	t.eq(Settings.get_value("controls", "invert_y"), false, "reset to defaults")
	# Input map
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch", "interact", "flashlight", "reload_battery", "inventory", "pause", "look_left", "look_up"]:
		t.check(InputMap.has_action(a) and InputMap.action_get_events(a).size() > 0, "input action '%s' bound" % a)
	var pad := false
	for e in InputMap.action_get_events("interact"):
		if e is InputEventJoypadButton:
			pad = true
	t.check(pad, "interact has a gamepad binding")
	Settings.path = old_path
	Settings.load_settings()
	Settings.apply_all()


func get_viewport_scale() -> float:
	return t.get_viewport().scaling_3d_scale
