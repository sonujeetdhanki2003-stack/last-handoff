class_name TestCase
extends RefCounted
## Base class for system tests. Override run(); use t.check / t.eq / t.frames.

var t  # the runner (res://tests/run_tests.gd)


func run() -> void:
	pass


## Static floor so bodies have something to stand on.
func make_floor(size := 40.0) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = Vector3(size, 0.2, size)
	cs.shape = s
	cs.position.y = -0.1
	b.add_child(cs)
	t.sandbox.add_child(b)
	return b


func make_wall(center: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	b.add_child(cs)
	b.position = center
	t.sandbox.add_child(b)
	return b


func spawn_player(pos := Vector3.ZERO, yaw := 0.0) -> Player:
	var p: Player = load("res://scenes/player.tscn").instantiate()
	t.sandbox.add_child(p)
	p.global_position = pos
	p.cam.set_view(yaw, -10.0)
	p.cam.global_position = pos + Vector3.UP * 1.55
	return p


## Point the camera so its centre ray passes through `target`.
## Iterates because the camera orbits the pivot (its position depends on the view).
func aim_at(p: Player, target: Vector3) -> void:
	for i in 5:
		var cam_pos := p.cam.camera.global_position
		var d := target - cam_pos
		var yaw := rad_to_deg(atan2(-d.x, -d.z))
		var pitch := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
		p.cam.set_view(yaw, pitch)
		await t.physics(2)
