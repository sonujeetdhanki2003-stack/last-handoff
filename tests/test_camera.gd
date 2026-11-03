extends TestCase
## Camera collision sweep: put the player against walls / in corners / in a
## narrow corridor at many yaw + pitch combinations; the camera must never be
## inside geometry and must hide the body (shadow-only) when it gets within
## the hide distance of the head.

func _inside_geometry(space: PhysicsDirectSpaceState3D, pos: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = pos
	q.collision_mask = 1
	return not space.intersect_point(q, 1).is_empty()


func run() -> void:
	make_floor(60)
	# a room 6 x 6 with 3 m walls and a 1.4 m wide corridor leading out
	make_wall(Vector3(0, 1.5, -3), Vector3(6, 3, 0.3))
	make_wall(Vector3(-3, 1.5, 0), Vector3(0.3, 3, 6))
	make_wall(Vector3(3, 1.5, 0), Vector3(0.3, 3, 6))
	make_wall(Vector3(-1.9, 1.5, 3), Vector3(2.2, 3, 0.3))
	make_wall(Vector3(1.9, 1.5, 3), Vector3(2.2, 3, 0.3))
	make_wall(Vector3(-0.85, 1.5, 6), Vector3(0.3, 3, 6))
	make_wall(Vector3(0.85, 1.5, 6), Vector3(0.3, 3, 6))
	make_wall(Vector3(0, 3.1, 0), Vector3(6, 0.2, 6))  # ceiling
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await t.physics(5)
	var space := p.get_world_3d().direct_space_state
	var spots := [Vector3(0, 0.05, 0), Vector3(2.55, 0.05, 0), Vector3(-2.55, 0.05, -2.55), Vector3(2.55, 0.05, 2.5), Vector3(0, 0.05, -2.55), Vector3(0, 0.05, 5.0), Vector3(0.4, 0.05, 7.5)]
	var samples := 0
	var bad_inside := 0
	var bad_head := 0
	var min_d := 99.0
	for s in spots:
		for yaw in range(0, 360, 30):
			for pitch in [-65.0, -30.0, -10.0, 15.0, 45.0]:
				p.global_position = s
				p.velocity = Vector3.ZERO
				p.cam.set_view(float(yaw), pitch)
				p.cam.global_position = s + Vector3.UP * 1.55
				await t.physics(4)
				samples += 1
				var cp := p.cam.camera.global_position
				if _inside_geometry(space, cp):
					bad_inside += 1
					if bad_inside < 6:
						print("    camera inside geometry at ", s, " yaw ", yaw, " pitch ", pitch, " cam ", cp)
				var head := p.global_position + Vector3.UP * 1.55
				var d := cp.distance_to(head)
				min_d = minf(min_d, d)
				if d < p.cam.hide_distance and not p.is_model_hidden():
					bad_head += 1
	t.eq(bad_inside, 0, "camera never inside walls (%d samples)" % samples)
	t.eq(bad_head, 0, "body hidden whenever the camera is within %.2f m of the head (closest %.2f m)" % [p.cam.hide_distance, min_d])
	# wide open: full distance, body visible
	p.global_position = Vector3(20, 0.05, 20)
	p.cam.set_view(0.0, -10.0)
	p.cam.global_position = p.global_position + Vector3.UP * 1.55
	await t.physics(10)
	t.near(p.cam.camera.global_position.distance_to(p.cam.global_position), Vector3(p.cam.shoulder, 0, p.cam.distance).length(), 0.35, "in the open the arm extends to full length")
	t.check(not p.is_model_hidden(), "body visible in the open")
	# settings: invert + sensitivity
	Settings.set_value("controls", "invert_y", false, false)
	p.cam.set_view(0.0, 0.0)
	p.cam.apply_mouse_look(Vector2(0, 10))
	var normal_delta := p.cam.pitch
	Settings.set_value("controls", "invert_y", true, false)
	p.cam.set_view(0.0, 0.0)
	p.cam.apply_mouse_look(Vector2(0, 10))
	var inv_delta := p.cam.pitch
	t.check(normal_delta < 0.0 and inv_delta > 0.0, "mouse down looks down; invert Y flips it")
	Settings.set_value("controls", "mouse_sensitivity", 0.5, false)
	p.cam.set_view(0.0, 0.0)
	p.cam.apply_mouse_look(Vector2(10, 0))
	var fast := absf(angle_difference(0.0, deg_to_rad(p.cam.yaw)))
	Settings.set_value("controls", "mouse_sensitivity", 0.1, false)
	p.cam.set_view(0.0, 0.0)
	p.cam.apply_mouse_look(Vector2(10, 0))
	var slow := absf(angle_difference(0.0, deg_to_rad(p.cam.yaw)))
	t.check(fast > slow * 4.0, "sensitivity scales mouse look")
	Settings.load_settings()
	Settings.set_value("controls", "invert_y", false, false)
	p.cam.set_view(0.0, -200.0)
	t.near(p.cam.pitch, p.cam.min_pitch, 0.01, "pitch clamped")
