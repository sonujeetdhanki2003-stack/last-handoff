class_name CameraRig
extends Node3D
## Third-person over-the-shoulder camera.
## Yaw -> Pitch -> SpringArm3D -> Camera3D. The spring arm sphere-casts so the
## camera never ends up inside walls; the shoulder offset is itself ray-checked
## so hugging a wall can't push the arm's origin through it; when the camera
## gets close to the head, the character mesh switches to shadow-only so the
## inside of the head is never shown.

signal too_close_changed(close: bool)

@export var target_path: NodePath
@export var height := 1.55
@export var crouch_height := 1.05
@export var distance := 2.8
@export var shoulder := 0.6
@export var min_pitch := -70.0
@export var max_pitch := 55.0
@export var follow_sharpness := 18.0
@export var hide_distance := 0.65

@onready var yaw_node: Node3D = $Yaw
@onready var pitch_node: Node3D = $Yaw/Pitch
@onready var arm: SpringArm3D = $Yaw/Pitch/SpringArm3D
@onready var camera: Camera3D = $Yaw/Pitch/SpringArm3D/Camera3D

var target: Node3D
var yaw := 0.0
var pitch := -12.0
var side := 1.0
var _side_lerp := 1.0
var _crouch_k := 0.0
var _too_close := false
var _excluded: Array[RID] = []
var input_enabled := true
var _shake := 0.0


func _ready() -> void:
	top_level = true
	target = get_node_or_null(target_path)
	if target is CollisionObject3D:
		_excluded.append((target as CollisionObject3D).get_rid())
		arm.add_excluded_object((target as CollisionObject3D).get_rid())
	arm.spring_length = distance
	camera.fov = Settings.get_value("video", "fov")
	side = float(Settings.get_value("controls", "camera_side"))
	_side_lerp = side
	Settings.changed.connect(_on_setting)
	if target:
		global_position = target.global_position + Vector3.UP * height
		yaw = target.rotation_degrees.y
	_apply_rotation()


func _on_setting(section: String, key: String, v: Variant) -> void:
	if section == "video" and key == "fov":
		camera.fov = float(v)
	elif section == "controls" and key == "camera_side":
		side = float(v)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_mouse_look(event.relative)
	elif event.is_action_pressed("switch_shoulder"):
		side = -side
		Settings.set_value("controls", "camera_side", int(side))


func apply_mouse_look(rel: Vector2) -> void:
	var s: float = Settings.get_value("controls", "mouse_sensitivity")
	var inv := -1.0 if Settings.get_value("controls", "invert_y") else 1.0
	yaw -= rel.x * s * 0.4
	pitch -= rel.y * s * 0.4 * inv
	_apply_rotation()


func set_view(p_yaw: float, p_pitch: float) -> void:
	yaw = p_yaw
	pitch = p_pitch
	_apply_rotation()


func _apply_rotation() -> void:
	pitch = clampf(pitch, min_pitch, max_pitch)
	yaw = fposmod(yaw, 360.0)
	if yaw_node:
		yaw_node.rotation_degrees.y = yaw
		pitch_node.rotation_degrees.x = pitch


func _physics_process(delta: float) -> void:
	if target == null:
		return
	if input_enabled:
		var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if look.length() > 0.0:
			var gs: float = Settings.get_value("controls", "gamepad_sensitivity")
			var inv := -1.0 if Settings.get_value("controls", "invert_y") else 1.0
			yaw -= look.x * gs * 60.0 * delta
			pitch -= look.y * gs * 40.0 * delta * inv
			_apply_rotation()
	var crouching: bool = target.get("crouching") == true
	_crouch_k = move_toward(_crouch_k, 1.0 if crouching else 0.0, delta * 4.0)
	var h := lerpf(height, crouch_height, _crouch_k)
	var goal := target.global_position + Vector3.UP * h
	global_position = global_position.lerp(goal, clampf(follow_sharpness * delta, 0.0, 1.0))
	# Never let the follow lag leave the pivot more than 0.3 m behind (teleports, lifts).
	if global_position.distance_to(goal) > 0.3:
		global_position = goal + (global_position - goal).limit_length(0.3)
	_update_shoulder(delta)
	_update_visibility()
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.6)
		camera.h_offset = randf_range(-1, 1) * _shake * 0.08
		camera.v_offset = randf_range(-1, 1) * _shake * 0.08
	elif camera.h_offset != 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func shake(amount: float) -> void:
	amount *= float(Settings.get_value("access", "camera_shake"))
	_shake = clampf(maxf(_shake, amount), 0.0, 1.0)


func yaw_degrees() -> float:
	return yaw


func _update_shoulder(delta: float) -> void:
	_side_lerp = move_toward(_side_lerp, side, delta * 5.0)
	var want := shoulder * _side_lerp
	# Ray from the pivot towards the shoulder point; shorten the offset on a hit.
	var space := get_world_3d().direct_space_state
	var right := yaw_node.global_transform.basis.x
	var from := global_position
	var to := from + right * (want + 0.25 * signf(want))
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, _excluded)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var d := from.distance_to(hit.position) - 0.25
		want = signf(want) * maxf(0.0, minf(absf(want), d))
	arm.position.x = lerpf(arm.position.x, want, clampf(delta * 12.0, 0.0, 1.0))


func _update_visibility() -> void:
	var head := target.global_position + Vector3.UP * (1.55 if target.get("crouching") != true else 1.05)
	var d := camera.global_position.distance_to(head)
	var close := d < hide_distance
	if close != _too_close:
		_too_close = close
		too_close_changed.emit(close)


func is_too_close() -> bool:
	return _too_close


## Horizontal forward/right of the camera, for camera-relative movement.
func flat_basis() -> Basis:
	return Basis(Vector3.UP, deg_to_rad(yaw))


func aim_ray(length := 30.0) -> Array:
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	return [from, from + dir * length]
