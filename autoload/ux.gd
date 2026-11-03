extends Node
## UX services shared by every screen: which input device is in use (for button
## prompts), UI sounds, scene transitions (fade out -> change -> fade in),
## subtitles/captions and the expedition title card.

signal device_changed(pad: bool)
signal subtitle_shown(kind: String, speaker: String, text: String)
signal title_card_done

var last_title := ""

var using_pad := false
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


## Prompt text for an action on the current device, e.g. "E" or "A".
func glyph(action: String) -> String:
	return Settings.action_label(action, using_pad)


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
