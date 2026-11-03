class_name IntroDirector
extends Node
## Cold open: the cage comes down the entrance shaft with the new member in it,
## the station PA reads the standing order, the cage slams down, the gate opens,
## and the camera finds the previous member's crate. Then the title card:
## "EXPEDITION 11 / PRIYA RAO". Skippable (Space / Esc / Start / A).
## The first member of a chain gets the long descent; later members a short one.

signal finished

static var time_scale := 1.0
const DROP := 12.0

var game: Node
var cam: Camera3D
var skipped := false
var done := false
var short := false
var _nodes: Array = []      ## [node, original global position]
var _loop: AudioStreamPlayer
var _lamp: OmniLight3D
var _skip_hint: Control
var _t := 0.0


func _w(sec: float) -> void:
	var left := sec / time_scale
	while left > 0.0 and not skipped:
		await get_tree().process_frame
		left -= get_process_delta_time()


func _unhandled_input(e: InputEvent) -> void:
	if not done and (e.is_action_pressed("skip") or e.is_action_pressed("pause")):
		skipped = true
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_t += delta


func play(g: Node, is_short := false) -> void:
	game = g
	short = is_short
	var hud: Node = g.hud
	var p: Player = g.player
	p.set_control(false)
	p.set_physics_process(false)
	hud.cinematic(true)
	Ux.set_black(1.0)
	# the cage and its platform ride down; everything else in the shaft stays
	for n in ["Lift", "LiftPlatform"]:
		var x := g.level.find_child(n, true, false) as Node3D
		if x:
			_nodes.append([x, x.global_position])
	var h := DROP if not short else DROP * 0.6
	var cage_floor := Vector3(-0.35, 0.25, 6.9)
	cam = Camera3D.new()
	cam.name = "IntroCam"
	cam.fov = 62
	g.add_child(cam)
	cam.current = true
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.72, 0.45)
	_lamp.light_energy = 1.6
	_lamp.omni_range = 6.0
	_lamp.shadow_enabled = false
	g.add_child(_lamp)
	_loop = AudioStreamPlayer.new()
	_loop.bus = &"SFX"
	var ls := Sfx.stream("res://audio/sfx2/lift_loop.ogg")
	if ls:
		_loop.stream = AudioLoop.make(ls)
	_loop.volume_db = -8.0
	add_child(_loop)
	_loop.play()
	_skip_hint = UIKit.hint_bar([["skip", "Skip"]])
	_skip_hint.anchor_left = 1.0
	_skip_hint.anchor_right = 1.0
	_skip_hint.anchor_top = 1.0
	_skip_hint.anchor_bottom = 1.0
	_skip_hint.offset_left = -220
	_skip_hint.offset_top = -70
	_skip_hint.modulate.a = 0.6
	hud._root.add_child(_skip_hint)
	_place(h, p, cage_floor)
	Ux.fade_in(1.2 if not short else 0.6)
	var dur := 10.0 if not short else 5.0
	if not short:
		get_tree().create_timer(1.6 / time_scale).timeout.connect(func(): if not skipped: Sfx.play_pa("pa_intro"))
		hud.caption("Halden Deep Research Station. Entrance shaft, going down.")
	else:
		hud.caption("The cage goes down again. One person per trip.")
	var k := 0.0
	while k < 1.0 and not skipped:
		await get_tree().process_frame
		k = minf(1.0, k + get_process_delta_time() * time_scale / dur)
		var e := 1.0 - pow(1.0 - k, 2.2)        # eases into the stop
		_place(h * (1.0 - e), p, cage_floor)
		if not short and k > 0.55 and k < 0.6:
			hud.caption(_line_two())
	_place(0.0, p, cage_floor)
	_loop.stop()
	if not skipped:
		Sfx.play("lift_stop")
		Sfx.caption_for("lift_stop")
		p.cam.shake(0.5)
		_jolt()
		await _w(0.9)
		Sfx.play("lift_gate")
		await _w(0.6)
	await Ux.fade_out(0.35 if not skipped else 0.15)
	# step out of the cage onto the shaft floor, facing the crate
	for pair in _nodes:
		(pair[0] as Node3D).global_position = pair[1]
	var sp: Transform3D = g.level.get_spawn()
	p.global_position = sp.origin
	p.velocity = Vector3.ZERO
	p.set_physics_process(true)
	var crate := g.level.find_child("HandoffCrateLatest", true, false) as Node3D
	var look_yaw := rad_to_deg(sp.basis.get_euler().y)
	if crate:
		var to := crate.global_position - sp.origin
		look_yaw = rad_to_deg(atan2(-to.x, -to.z))
	p.cam.set_view(look_yaw, -14.0)
	p.face_yaw_degrees(look_yaw)
	p.cam.global_position = p.global_position + Vector3.UP * 1.55
	p.cam.camera.current = true
	cam.queue_free()
	_lamp.queue_free()
	if is_instance_valid(_skip_hint):
		_skip_hint.queue_free()
	hud.cinematic(false)
	done = true
	# title card over black, then the world fades in on the crate
	await Ux.show_title_card("Expedition %d" % GameState.expedition_number, GameState.member_name if GameState.member_name != "" else "New member", "HALDEN DEEP  //  LEVEL B2", 1.6 if short else 2.2, true)
	Ux.fade_in(0.9)
	if GameState.chain_mode and GameState.expedition_number > Lore.FIRST_EXPEDITION:
		Ux.subtitle("Expedition %d left you something in the crate." % (GameState.expedition_number - 1), "", 3.5, "speech")
	p.set_control(true)
	finished.emit()


func _line_two() -> String:
	var n := GameState.expedition_number
	if n <= Lore.FIRST_EXPEDITION:
		return "Seven expeditions went down before you. None brought the drive up."
	return "Expedition %d is somewhere below. Their crate will be by the lift." % (n - 1)


func _place(off: float, p: Player, cage_floor: Vector3) -> void:
	for pair in _nodes:
		(pair[0] as Node3D).global_position = (pair[1] as Vector3) + Vector3.UP * off
	p.global_position = cage_floor + Vector3.UP * off
	p.face_yaw_degrees(15.0)
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.006 * (1.0 if off > 0.05 else 0.0)
	cam.global_position = Vector3(1.15, 1.7 + off, 7.45) + jitter
	cam.look_at(Vector3(-0.9, 1.15 + off, 4.2), Vector3.UP)
	_lamp.global_position = Vector3(0.0, 2.4 + off, 6.6)


func _jolt() -> void:
	var base := cam.global_position
	for i in 8:
		cam.global_position = base + Vector3(0, -0.04 * (1.0 - i / 8.0) * (1 if i % 2 == 0 else -1), 0)
		await get_tree().process_frame
	cam.global_position = base
