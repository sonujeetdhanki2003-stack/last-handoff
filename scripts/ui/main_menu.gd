extends Node3D
## Title screen over a live view of the station's entrance shaft.

var _ui: Control
var _main: VBoxContainer
var _left: Control
var _settings: SettingsMenu
var _credits: TermPanel
var _history: HistoryScreen
var _howto: HowToPlayScreen
var _achieve: AchievementsScreen
var _chapters: ChaptersScreen
var _bright: BrightnessScreen
var _dim: ScreenBackdrop
var _notice: Label
var _status: RichTextLabel
var _cam: Camera3D
var _t := 0.0
var _return_focus: Control
var buttons := {}
var _top: Control


func _ready() -> void:
	get_tree().paused = false
	Events.set_modal(false)
	GameState.active = false
	var lvl: Node3D = load("res://scenes/levels/facility_greybox.tscn").instantiate()
	add_child(lvl)
	_cam = Camera3D.new()
	_cam.fov = 60
	_cam.position = Vector3(-3.3, 1.7, 5.0)
	add_child(_cam)
	_cam.look_at(Vector3(0.6, 1.1, 0.5))
	_cam.current = true
	var spot := SpotLight3D.new()
	spot.light_energy = 4.0
	spot.spot_range = 14.0
	spot.spot_angle = 22.0
	spot.shadow_enabled = true
	spot.light_color = Color(1, 0.95, 0.85)
	spot.position = Vector3(0.3, -0.2, 0)
	_cam.add_child(spot)
	_build_ui()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	_t += delta
	_cam.position = Vector3(-3.3 + sin(_t * 0.15) * 0.15, 1.7 + sin(_t * 0.23) * 0.05, 5.0 - minf(_t, 40.0) * 0.006)
	_cam.look_at(Vector3(0.6 + sin(_t * 0.11) * 0.5, 1.1, 0.5))


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_ui)
	var grad := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.01, 0.012, 0.014, 0.94))
	g.add_point(0.55, Color(0.01, 0.012, 0.014, 0.7))
	g.set_color(g.get_point_count() - 1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	gt.width = 256
	gt.height = 8
	grad.texture = gt
	grad.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	grad.offset_right = 1050
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(grad)
	var over := UIKit.backdrop(0.0)
	_ui.add_child(over)

	_left = Control.new()
	_left.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_left)
	var top := VBoxContainer.new()
	_top = top
	top.position = Vector2(112, 70)
	top.add_theme_constant_override("separation", 0)
	top.custom_minimum_size.x = 640
	_left.add_child(top)
	top.add_child(UIKit.label("HALDEN DEEP RESEARCH STATION  //  LEVEL B2", 18, UIKit.AMBER_DIM, "mono"))
	var title := UIKit.shadowed(UIKit.label("LAST HANDOFF", 120, UIKit.TEXT, "title"))
	title.name = "Title"
	top.add_child(title)
	top.add_child(UIKit.rule(UIKit.AMBER, 3, 160))
	top.add_child(UIKit.spacer(12))
	top.add_child(UIKit.shadowed(UIKit.label("Every expedition hands off to the next.", 27, Color(0.7, 0.71, 0.68), "ui")))
	top.add_child(UIKit.spacer(16))
	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.scroll_active = false
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.custom_minimum_size.x = 700
	_status.add_theme_font_override("normal_font", UIKit.font("mono"))
	_status.add_theme_font_override("bold_font", UIKit.font("mono_bold"))
	_status.add_theme_font_size_override("normal_font_size", 17)
	_status.add_theme_font_size_override("bold_font_size", 17)
	_status.add_theme_color_override("default_color", Color(0.62, 0.64, 0.61))
	_status.add_theme_constant_override("line_separation", 4)
	top.add_child(_status)
	_notice = UIKit.label(Legacy.load_notice, 20, UIKit.RED, "ui")
	top.add_child(_notice)
	top.add_child(UIKit.spacer(18))

	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 2)
	_main.custom_minimum_size.x = 560
	_main.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	top.add_child(_main)
	for pair in [["Continue", "CONTINUE", _continue], ["Start", "NEW EXPEDITION", _start],
			["Chapters", "CHAPTERS", open_chapters], ["History", "EXPEDITION HISTORY", open_history],
			["Achievements", "ACHIEVEMENTS", open_achievements], ["HowTo", "HOW TO PLAY", open_howto],
			["Settings", "SETTINGS", open_settings], ["Credits", "CREDITS", open_credits], ["Quit", "QUIT", _quit]]:
		var b := UIKit.button(pair[1], 29)
		b.name = pair[0]
		b.pressed.connect(pair[2])
		_main.add_child(b)
		buttons[pair[0]] = b

	var foot := HBoxContainer.new()
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.anchor_right = 1.0
	foot.offset_left = 112
	foot.offset_right = -60
	foot.offset_top = -74
	foot.offset_bottom = -40
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left.add_child(foot)
	foot.add_child(UIKit.hint_bar([["ui_accept", "Select"], ["ui_cancel", "Back"]]))
	foot.add_child(UIKit.expand())
	foot.add_child(UIKit.label("v%s  //  OFFLINE  //  SINGLE PLAYER" % ProjectSettings.get_setting("application/config/version"), 16, UIKit.FAINT, "mono"))


	_dim = UIKit.backdrop(0.78) as ScreenBackdrop
	_dim.visible = false
	_ui.add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(center)
	_settings = SettingsMenu.new()
	_settings.visible = false
	_settings.calibrate = func(): open_brightness(true)
	_settings.back.connect(_close_sub)
	center.add_child(_settings)
	_credits = _build_credits()
	_credits.visible = false
	center.add_child(_credits)
	_history = HistoryScreen.new()
	_history.visible = false
	_history.back.connect(_close_sub)
	center.add_child(_history)
	_howto = HowToPlayScreen.new()
	_howto.visible = false
	_howto.back.connect(_close_sub)
	center.add_child(_howto)
	_achieve = AchievementsScreen.new()
	_achieve.visible = false
	_achieve.back.connect(_close_sub)
	center.add_child(_achieve)
	_chapters = ChaptersScreen.new()
	_chapters.visible = false
	_chapters.back.connect(_close_sub)
	_chapters.start.connect(start_chapter)
	center.add_child(_chapters)
	_bright = BrightnessScreen.new()
	_bright.visible = false
	_bright.done.connect(_on_bright_done)
	_ui.add_child(_bright)

	_refresh_buttons()
	get_viewport().size_changed.connect(fit_column)
	if not bool(Settings.get_value("video", "calibrated")) and not Harness.has("shot") and DisplayServer.get_name() != "headless":
		open_brightness(false)
	else:
		focus_default()


func _build_credits() -> TermPanel:
	var p := UIKit.term_panel("HD-B2 // ACKNOWLEDGEMENTS", 34)
	p.custom_minimum_size = Vector2(1060, 720)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 12)
	p.add_child(cv)
	cv.add_child(UIKit.header("Credits", "", 50))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cv.add_child(sc)
	var rt := RichTextLabel.new()
	rt.name = "Text"
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.focus_mode = Control.FOCUS_ALL
	rt.add_theme_font_override("normal_font", UIKit.font("ui"))
	rt.add_theme_font_override("bold_font", UIKit.font("ui_bold"))
	rt.add_theme_font_size_override("normal_font_size", 23)
	rt.add_theme_font_size_override("bold_font_size", 23)
	rt.add_theme_color_override("default_color", UIKit.TEXT)
	rt.text = CREDITS_TEXT
	sc.add_child(rt)
	cv.add_child(UIKit.rule())
	var row := HBoxContainer.new()
	cv.add_child(row)
	row.add_child(UIKit.hint_bar([["ui_cancel", "Back"]]))
	row.add_child(UIKit.expand())
	var back := UIKit.button("Back", 24)
	back.name = "Back"
	back.custom_minimum_size.x = 140
	back.pressed.connect(_close_sub)
	row.add_child(back)
	return p


const CREDITS_TEXT := """[color=#f5a83d][b]A GAME BY SONUJEET[/b][/color]

[b]Characters and animation[/b]
Universal Base Characters and Universal Animation Library by Quaternius (CC0). The Keeper is built on the same rig.

[b]Props and textures[/b]
Poly Haven (CC0): 54 props and 19 surface sets.

[b]Type[/b]
Oswald, Barlow Condensed, IBM Plex Mono, Caveat (SIL Open Font License). Special Elite, Permanent Marker (Apache 2.0).

[b]Sound[/b]
Sound effects, Keeper voice, stingers and UI sounds generated for this project. Room tones, drones and machinery synthesised in code. Tape and PA voices: text-to-speech recorded for this project.

[b]Engine[/b]
Godot Engine 4.7 (MIT licence). 3D props, the Keeper's animations and sculpt, and the v1.2 lift and winch room were made for this project in Blender. The v1.2 heartbeat, locker rattle and vent creak are synthesised in code.

[color=#8a8d88]Fully offline. No accounts, no purchases, no telemetry.
The full list of assets and licences is in CREDITS.md.[/color]"""


func focus_default() -> void:
	Ux.quiet_focus()
	var cont: Button = buttons["Continue"]
	(cont if cont.visible else buttons["Start"]).grab_focus()


func _open_sub(c: Control, from: Control) -> void:
	_return_focus = from
	_left.visible = false
	_dim.visible = true
	c.visible = true


func _close_sub() -> void:
	for c in [_settings, _credits, _history, _howto, _achieve, _chapters]:
		c.visible = false
	_dim.visible = false
	_left.visible = true
	_refresh_buttons()
	Ux.quiet_focus()
	if _return_focus and _return_focus.visible:
		_return_focus.grab_focus()
	else:
		focus_default()


func open_settings() -> void:
	_open_sub(_settings, buttons["Settings"])
	_settings.set_tab(0, false)
	_settings.focus_first()


func open_credits() -> void:
	_open_sub(_credits, buttons["Credits"])
	Ux.quiet_focus()
	(_credits.find_child("Back", true, false) as Button).grab_focus()


func open_history() -> void:
	_open_sub(_history, buttons["History"])
	_history.refresh()
	_history.focus_first()


func open_howto() -> void:
	_open_sub(_howto, buttons["HowTo"])
	_howto.open()


func open_achievements() -> void:
	_open_sub(_achieve, buttons["Achievements"])
	_achieve.open()


func open_chapters() -> void:
	_open_sub(_chapters, buttons["Chapters"])
	_chapters.open()


## v1.2: a chapter replay (never touches the chain or the Continue slot).
func start_chapter(id: String) -> void:
	if Progress.begin_chapter(id):
		Ux.change_scene("res://scenes/game.tscn", 0.8, 0.01 if GameState.play_intro else 0.9)


func open_brightness(from_settings: bool) -> void:
	_bright.from_settings = from_settings
	_settings.visible = false if from_settings else _settings.visible
	_left.visible = false
	_bright.open()


func _on_bright_done() -> void:
	if _bright.from_settings:
		_settings.visible = true
		_dim.visible = true
		Ux.quiet_focus()
		(_settings.find_child("Calibrate", true, false) as Control).grab_focus()
	else:
		_left.visible = true
		focus_default()


## Which screen is up: "main", "settings", "credits", "history", "brightness".
func current_screen() -> String:
	if _bright.visible:
		return "brightness"
	for pair in [[_settings, "settings"], [_credits, "credits"], [_history, "history"], [_howto, "howto"],
			[_achieve, "achievements"], [_chapters, "chapters"]]:
		if (pair[0] as Control).visible:
			return pair[1]
	return "main"


## The menu column must clear the footer (hint bar + version) at every aspect ratio,
## with CONTINUE and a save-repair notice showing: lift it when it would collide.
func fit_column() -> void:
	if _top == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var h := _top.get_combined_minimum_size().y
	# v1.2: nine entries now; on a short (wide) screen the column shrinks a little to fit
	var avail := vs.y - 84.0 - 16.0
	var s := clampf(avail / h, 0.8, 1.0)
	_top.scale = Vector2(s, s)
	_top.position.y = clampf(vs.y - 84.0 - h * s, 16.0, 70.0)
	_top.size.y = h


func column_bottom() -> float:
	return _top.position.y + _top.get_combined_minimum_size().y * _top.scale.y


func _refresh_buttons() -> void:
	fit_column.call_deferred()
	var cont: Button = buttons["Continue"]
	var start: Button = buttons["Start"]
	cont.visible = Legacy.has_run_in_progress()
	if cont.visible:
		var r: Dictionary = Legacy.chain["run"]
		cont.text = "CONTINUE  -  EXP. %d, %s" % [int(r.get("expedition", 0)), str(r.get("member", "")).to_upper()]
	if Legacy.ending_reached() != "":
		start.text = "START A NEW CHAIN"
	elif Legacy.expeditions_done() == 0 and not Legacy.has_run_in_progress():
		start.text = "NEW EXPEDITION"
	else:
		start.text = "SEND THE NEXT MEMBER  -  EXP. %d" % Legacy.next_expedition()
	var lost := 0
	for h in Legacy.chain.get("history", []):
		if str(h.get("end", "")) in ["died", "injured"]:
			lost += 1
	var done := Legacy.expeditions_done()
	var nxt := Legacy.next_expedition()
	var lines := []
	if Legacy.ending_reached() != "":
		lines.append("[color=#f5a83d]>[/color] CHAIN CLOSED: %s" % str(Lore.ENDINGS.get(Legacy.ending_reached(), {}).get("title", "")).to_upper())
	elif done == 0 and not Legacy.has_run_in_progress():
		lines.append("[color=#f5a83d]>[/color] RELAY STATUS: 7 EXPEDITIONS BEFORE YOU. NONE RETURNED THE DRIVE.")
	else:
		lines.append("[color=#f5a83d]>[/color] RELAY STATUS: %d SENT  //  %d LOST IN THE DARK  //  TAPES %d/4" % [done, lost, Legacy.mara_tapes_found()])
	if Legacy.ending_reached() == "" and not Legacy.has_run_in_progress():
		lines.append("[color=#f5a83d]>[/color] NEXT ON THE ROSTER: EXP. %d  //  %s" % [nxt, Lore.member_name(int(Legacy.chain.get("chain_id", 0)), nxt).to_upper()])
	_status.text = "\n".join(lines)


func _continue() -> void:
	if Legacy.resume_expedition():
		Ux.change_scene("res://scenes/game.tscn", 0.6, 0.9)


func _start() -> void:
	if Legacy.ending_reached() != "":
		Legacy.reset_chain()
	if Legacy.has_run_in_progress():
		# the member in progress is lost in the dark: abandoned runs end as "did not return"
		Legacy.chain["run"] = null
	Legacy.begin_expedition()
	GameState.play_intro = true
	Ux.change_scene("res://scenes/game.tscn", 0.8, 0.01)


func _quit() -> void:
	await Ux.fade_out(0.3)
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if _credits.visible:
			get_viewport().set_input_as_handled()
			Ux.ui_sound("back")
			_close_sub()
		elif _left.visible and not _settings.visible and not _history.visible and not _howto.visible and not _achieve.visible and not _chapters.visible and is_visible_in_tree():
			# top level (the Android back button lands here too): first press goes to QUIT,
			# a second one on QUIT leaves the game, like most phone games
			get_viewport().set_input_as_handled()
			var q: Button = buttons["Quit"]
			if q.has_focus():
				_quit()
			else:
				Ux.ui_sound("back")
				q.grab_focus()
