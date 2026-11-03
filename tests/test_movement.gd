extends TestCase

func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	for i in frames:
		await t.physics(1)
	Input.action_release(action)


func run() -> void:
	make_floor()
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await t.physics(10)
	t.check(p.is_on_floor(), "player lands on the floor")
	var start := p.global_position
	await _hold("move_forward", 60)
	var moved := p.global_position - start
	t.check(moved.z < -1.4 and absf(moved.x) < 0.2, "W walks forward along the camera direction (moved %.2f m)" % -moved.z)
	t.near(Vector2(p.velocity.x, p.velocity.z).length(), p.walk_speed, 0.25, "walk speed reached")
	t.check(p.facing_dir().dot(Vector3.FORWARD) > 0.9, "character turns to face where it walks")
	var at: AnimationTree = p.animator
	t.check(float(at.get("parameters/loco/blend_position")) > 1.2, "locomotion blend follows speed (walk)")
	await t.physics(30)
	t.check(float(at.get("parameters/loco/blend_position")) < 0.3, "blend returns to idle when stopped")

	# camera-relative: turn the camera 90 degrees right, W now moves along -X
	p.cam.set_view(-90.0, -10.0)
	start = p.global_position
	await _hold("move_forward", 40)
	moved = p.global_position - start
	t.check(moved.x > 0.8 and absf(moved.z) < 0.3, "movement is camera-relative (moved x %.2f)" % moved.x)

	# run
	p.cam.set_view(0.0, -10.0)
	Input.action_press("sprint")
	await _hold("move_forward", 60)
	Input.action_release("sprint")
	t.check(float(at.get("parameters/loco/blend_position")) > 3.5, "sprint blends to the jog/run clip")
	await t.physics(30)

	# crouch
	p.toggle_crouch()
	t.check(p.crouching, "crouch toggles on")
	t.near((p.collider.shape as CapsuleShape3D).height, p.crouch_height, 0.001, "capsule shrinks")
	start = p.global_position
	await _hold("move_forward", 60)
	t.check(Vector2(p.velocity.x, p.velocity.z).length() < p.crouch_speed + 0.1, "crouch walk is slower")
	await t.physics(10)
	t.check(float(at.get("parameters/stance/blend_amount")) > 0.9, "animation blends to crouch")
	# can't stand up under a low ceiling
	make_wall(p.global_position + Vector3(0, 1.45, 0), Vector3(2, 0.2, 2))
	await t.physics(3)
	p.toggle_crouch()
	t.check(p.crouching, "cannot stand up under a 1.35 m ceiling")
	p.global_position += Vector3(3, 0, 0)
	await t.physics(3)
	p.toggle_crouch()
	t.check(not p.crouching, "stands once there is headroom")

	# walls stop the player
	var wall := make_wall(p.global_position + Vector3(0, 1, -1.5), Vector3(4, 2, 0.3))
	await t.physics(3)
	await _hold("move_forward", 120)
	t.check(p.global_position.z > wall.position.z + 0.3, "player is stopped by walls")

	# modal UI freezes movement
	Events.set_modal(true)
	start = p.global_position
	p.cam.set_view(180.0, -10.0)
	await _hold("move_forward", 30)
	t.check(p.global_position.distance_to(start) < 0.05, "no movement while a menu/modal is open")
	Events.set_modal(false)

	# flashlight toggle via action
	var was: bool = p.flashlight.on
	var ev := InputEventAction.new()
	ev.action = "flashlight"
	ev.pressed = true
	p._unhandled_input(ev)
	t.check(p.flashlight.on != was, "F toggles the flashlight")
	await t.physics(20)
	t.check(float(at.get("parameters/torch/blend_amount")) > 0.0 or not p.flashlight.on, "torch-holding arm pose blends in with the light on")
