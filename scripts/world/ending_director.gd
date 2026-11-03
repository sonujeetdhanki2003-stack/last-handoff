class_name EndingDirector
extends Node
## Short in-engine sequences for the three endings (camera moves in the real
## station, lights and sound), then the HUD shows the end card.

static var time_scale := 1.0     ## tests speed the sequences up

var cam: Camera3D
var game: Node
var played := ""
var _sway_t := 0.0


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec / time_scale, true, false, true).timeout


func play(id: String, g: Node) -> void:
	game = g
	played = id
	var hud: Node = g.hud
	hud.cinematic(true)
	cam = Camera3D.new()
	cam.name = "EndingCam"
	cam.fov = 55
	g.add_child(cam)
	cam.current = true
	var k: Node = g.get("keeper")
	match id:
		"seal":
			await _seal(hud, k)
		"broadcast":
			await _broadcast(hud, k)
		"break":
			await _break(hud, k)
	await hud.fade_to_black(1.5 / time_scale)
	hud.cinematic(false)


func _lights_all(k: float) -> void:
	for l in get_tree().get_nodes_in_group("powered_lights"):
		(l as PoweredLight)._apply(k)


func _move_cam(from: Vector3, to: Vector3, look_a: Vector3, look_b: Vector3, dur: float) -> void:
	var steps := maxi(2, int(dur * 30.0 / time_scale))
	for i in steps + 1:
		var f := float(i) / steps
		var e := f * f * (3.0 - 2.0 * f)
		_sway_t += 1.0 / 30.0
		var sway := Vector3(sin(_sway_t * 1.7), sin(_sway_t * 2.3 + 1.0), 0.0) * 0.012
		cam.global_position = from.lerp(to, e) + sway
		cam.look_at(look_a.lerp(look_b, e), Vector3.UP)
		await get_tree().process_frame


func _seal(hud: Node, k: Node) -> void:
	if k:
		k.set("think", false)
		k.global_position = Vector3(-1.5, 0, -6.0)
	var p: Player = game.player
	p.global_position = Vector3(-2.3, 0.05, 4.2)
	p.face_yaw_degrees(-60.0)
	p.flashlight.set_on(true)
	hud.caption("You find the cable brake by touch.")
	Sfx.play("lever", -2.0)
	await _move_cam(Vector3(1.8, 1.4, 1.2), Vector3(1.2, 2.0, 2.8), Vector3(0, 2.5, 7.5), Vector3(0, 9.0, 7.6), 4.0)
	Sfx.play("lift_stop", 2.0)
	Sfx.play("breaker", 0.0, 0.7)
	p.cam.shake(0.6)
	hud.caption("The cable goes. Nobody is coming down after you.")
	for c in game.level.find_children("Cable*", "", true, false):
		var tw := create_tween()
		tw.tween_property(c, "position:y", (c as Node3D).position.y - 20.0, 1.2 / time_scale)
	await _wait(2.5)
	hud.caption("One by one, you turn the lights off.")
	var lights := get_tree().get_nodes_in_group("powered_lights")
	for l in lights:
		(l as PoweredLight)._apply(0.0)
		if randf() < 0.35:
			Sfx.play("breaker", -10.0, randf_range(0.9, 1.1))
		await _wait(0.12)
	await _move_cam(Vector3(0.4, 1.3, 1.6), Vector3(-0.6, 1.1, 2.6), Vector3(-2.3, 0.8, 4.2), Vector3(-2.3, 0.7, 4.3), 3.0)
	p.flashlight.set_on(false)
	Sfx.play("keeper_breath", -6.0)
	hud.caption("Someone has to keep it company.")
	await _wait(3.0)


func _broadcast(hud: Node, k: Node) -> void:
	var tx := game.level.find_child("Transmitter", true, false) as Node3D
	var at: Vector3 = tx.global_position if tx else Vector3(7.5, 1.0, -20.5)
	hud.caption("UPLOAD 0%")
	Sfx.play("pa_chime", -4.0)
	await _move_cam(at + Vector3(-2.6, 0.6, 2.2), at + Vector3(-1.6, 0.3, 1.4), at, at + Vector3(0, 0.2, 0), 2.0)
	for gid in ["aux", "corridor_lights", "lab"]:
		GameState.grid.set_on(gid, true)
	_lights_all(1.0)
	Sfx.play("gen_start", -2.0)
	if k:
		k.set("think", false)
		(k as Node3D).global_position = Vector3(4.0, 0.0, -14.5)
		(k as Keeper).set_state(Keeper.S.CHASE)
		(k as Keeper).look_at_flat(at)
	for pct in [12, 31, 47, 66, 84, 100]:
		hud.caption("UPLOAD %d%%   -   every light in Halden Deep is on" % pct)
		_lights_all(1.0 + pct / 40.0)
		await _wait(0.9)
	await _move_cam(cam.global_position, at + Vector3(-1.0, 0.5, 2.8), at, Vector3(4.0, 1.6, -15.0), 1.6)
	hud.caption("It heard all of it.")
	Sfx.play("keeper_scream", 2.0)
	await _wait(1.6)
	hud.flash_white()
	await _wait(1.0)


func _break(hud: Node, k: Node) -> void:
	if k:
		k.set("think", false)
		(k as Node3D).global_position = Vector3(0.4, 0.0, -8.0)
	var cd: Node = game.get("chain_director")
	if cd:
		for n in ["HandoffItem", "HandoffCrateNote"]:
			var x := cd.get_node_or_null(n)
			if x:
				x.queue_free()
	hud.caption("You leave the crate empty.")
	await _move_cam(Vector3(-1.2, 1.2, 2.6), Vector3(-1.6, 0.9, 3.6), Vector3(-3.0, 0.3, 4.65), Vector3(-3.0, 0.2, 4.65), 3.0)
	hud.caption("No note. No mark.")
	var marks := get_tree().get_nodes_in_group("chalk_marks")
	for m in marks:
		for d in (m as Node).get_children():
			if d is Decal:
				create_tween().tween_property(d, "modulate:a", 0.0, 2.0 / time_scale)
			elif d is Label3D:
				create_tween().tween_property(d, "modulate:a", 0.0, 2.0 / time_scale)
	await _wait(2.4)
	hud.caption("The cage goes up with nothing in it, and nobody waiting.")
	Sfx.play("lift_gate", -2.0)
	Sfx.play("lift_loop", -8.0)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.85, 0.6)
	lamp.light_energy = 2.0
	lamp.omni_range = 5.0
	game.add_child(lamp)
	lamp.global_position = Vector3(0, 1.5, 6.6)
	create_tween().tween_property(lamp, "global_position:y", 15.0, 4.0 / time_scale)
	await _move_cam(Vector3(0.0, 1.0, 2.0), Vector3(0.0, 1.2, 3.2), Vector3(0, 2.0, 6.6), Vector3(0, 14.0, 6.8), 4.0)
	hud.caption("The relay ends with you.")
	await _wait(2.5)
