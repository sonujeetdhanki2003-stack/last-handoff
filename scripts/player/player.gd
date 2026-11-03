class_name Player
extends CharacterBody3D
## Third-person explorer: camera-relative movement, walk / run / crouch,
## aim-based interaction (tap or hold), flashlight, inventory shortcuts.

signal interaction_target_changed(target: Node)
signal hold_progress(fraction: float)

const INTERACT_RANGE := 2.3

@export var walk_speed := 1.9
@export var run_speed := 4.4
@export var crouch_speed := 1.15
@export var acceleration := 10.0
@export var turn_speed := 10.0
@export var stand_height := 1.8
@export var crouch_height := 1.15

@onready var cam: CameraRig = $CameraRig
@onready var flashlight: Flashlight = $Flashlight
@onready var model: Node3D = $Model
@onready var animator: PlayerAnimator = $AnimationTree
@onready var collider: CollisionShape3D = $CollisionShape3D
@onready var footsteps: AudioStreamPlayer3D = $Footsteps

var crouching := false
var running := false
var control_enabled := true
var current_target: Node = null
var _hold_t := 0.0
var _holding_target: Node = null
var _step_t := 0.0
var _action_lock := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _mesh_instances: Array[MeshInstance3D] = []

# --- Phase 4: survival -----------------------------------------------------------
const NOISE_WALK := 4.5        ## radius (m) the Keeper hears a footstep from
const NOISE_RUN := 13.0
const NOISE_CROUCH := 0.0      ## crouch-walking is silent
var vitals := Vitals.new()
var hidden_in: Node = null     ## a HidingSpot while hiding
var dead := false
var grabbed := false
var _breath_t := 0.0
var _air_t := 0.0


func _ready() -> void:
	add_to_group("player")
	for m in model.find_children("*", "MeshInstance3D", true, false):
		_mesh_instances.append(m)
		m.layers = 2  # visual layer 2: excluded from the flashlight (no self-shadow blob)
	_apply_outfit()
	cam.too_close_changed.connect(_on_cam_close)
	Events.ui_modal_changed.connect(func(open): _update_mouse())
	flashlight.toggled.connect(func(on): animator.set_torch(on))
	flashlight.set_on(GameState.battery_charge > 0.0)  # start with the light on
	vitals.died.connect(_on_died)
	vitals.health_changed.connect(func(_h): pass)
	vitals.winded.connect(func():
		Events.noise.emit(global_position, 6.0, "winded")
		Sfx.play("gasp", -2.0)   # v1.2: you hear it, the RUN ring flashes, and the hint says why
		_block_run("Out of breath"))
	_update_mouse()
	Events.player_spawned.emit(self)


## Dress the CC0 Universal Base Character as an expedition member: painted
## jumpsuit textures, helmet with headlamp, backpack with a bedroll, chest strap.
## Every surface gets a faint cool rim pass so the explorer never reads as a
## black silhouette against the dark.
const RIM_SHADER := preload("res://assets/shaders/rim.gdshader")
var _lamp_lens: StandardMaterial3D
const PACK_Z := -0.15


func _rim_pass(strength := 1.0) -> ShaderMaterial:
	var r := ShaderMaterial.new()
	r.shader = RIM_SHADER
	r.set_shader_parameter("strength", 0.13 * strength)
	return r


func _mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.next_pass = _rim_pass()
	return m


func _gear_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.layers = 2
	parent.add_child(mi)
	_mesh_instances.append(mi)
	return mi


func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


func _cyl(r: float, h: float, r2 := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r if r2 < 0.0 else r2
	c.height = h
	c.radial_segments = 20
	return c


## A node pinned to `bone`, whose local space is the character's model space
## (metres, +Z forward) at rest, so gear can be placed with plain coordinates.
func _pin(skel: Skeleton3D, bone: String) -> Node3D:
	var idx := skel.find_bone(bone)
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skel.add_child(ba)
	var holder := Node3D.new()
	holder.transform = skel.get_bone_global_rest(idx).affine_inverse()
	ba.add_child(holder)
	return holder


func _apply_outfit() -> void:
	var tex := "res://assets/characters/explorer/"
	var body := StandardMaterial3D.new()
	body.albedo_texture = load(tex + "T_Explorer_BaseColor.png")
	body.normal_enabled = true
	body.normal_texture = load(tex + "T_Explorer_Normal.png")
	body.roughness_texture = load(tex + "T_Explorer_Roughness.png")
	body.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	body.next_pass = _rim_pass()
	for m in _mesh_instances:
		if m.mesh == null:
			continue
		if m.name.begins_with("SuperHero"):
			m.material_override = body
		else:
			var src := m.mesh.surface_get_material(0)
			if src:
				var d: Material = src.duplicate()
				d.next_pass = _rim_pass(0.5)
				m.material_override = d
	var skel := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	if skel == null:
		return
	# ---- helmet (model space: head spans y 1.60..1.81, z -0.11..0.12)
	var head := _pin(skel, "Head")
	var shell_mat := _mat(Color(0.78, 0.74, 0.62), 0.45, 0.0)
	var dark := _mat(Color(0.05, 0.05, 0.055), 0.55, 0.4)
	var strap_m := _mat(Color(0.09, 0.085, 0.08), 0.85)
	var shell := SphereMesh.new()
	shell.radius = 0.135
	shell.height = 0.19
	shell.is_hemisphere = true
	shell.radial_segments = 28
	shell.rings = 10
	_gear_mesh(head, shell, shell_mat, Vector3(0, 1.725, -0.005), Vector3.ZERO, Vector3(0.93, 1.0, 1.08))
	_gear_mesh(head, _cyl(0.142, 0.018, 0.146), dark, Vector3(0, 1.727, -0.005), Vector3.ZERO, Vector3(0.93, 1.0, 1.08))
	_gear_mesh(head, _box(Vector3(0.026, 0.02, 0.27)), shell_mat, Vector3(0, 1.855, -0.005))  # crest ridge
	# headlamp: housing, glowing lens, mount strap
	_gear_mesh(head, _box(Vector3(0.07, 0.05, 0.03)), dark, Vector3(0, 1.79, 0.14))
	_gear_mesh(head, _cyl(0.024, 0.04), dark, Vector3(0, 1.79, 0.16), Vector3(PI / 2, 0, 0))
	_lamp_lens = StandardMaterial3D.new()
	_lamp_lens.albedo_color = Color(1.0, 0.95, 0.82)
	_lamp_lens.emission_enabled = true
	_lamp_lens.emission = Color(1.0, 0.93, 0.78)
	_lamp_lens.emission_energy_multiplier = 6.0
	_gear_mesh(head, _cyl(0.019, 0.006), _lamp_lens, Vector3(0, 1.79, 0.181), Vector3(PI / 2, 0, 0))
	# chin strap
	for sx in [-1.0, 1.0]:
		_gear_mesh(head, _box(Vector3(0.008, 0.11, 0.016)), strap_m, Vector3(0.118 * sx, 1.675, 0.0), Vector3(0, 0, 0.12 * sx))
	# ---- backpack on the upper chest bone (back is -Z in model space; the back
	# surface sits at about z -0.17 between y 1.15 and 1.35)
	var chest := _pin(skel, "UpperChest")
	var pack_m := _mat(Color(0.26, 0.27, 0.19), 0.9)
	var pack_d := _mat(Color(0.08, 0.09, 0.08), 0.85)
	var roll_m := _mat(Color(0.55, 0.12, 0.08), 0.8)
	var metal := _mat(Color(0.45, 0.45, 0.43), 0.35, 0.8)
	var pz := PACK_Z
	# rounded expedition pack on a light external frame (Phase 4 art pass)
	var cap := CapsuleMesh.new()
	cap.radius = 0.145
	cap.height = 0.46
	cap.radial_segments = 20
	cap.rings = 6
	_gear_mesh(chest, cap, pack_m, Vector3(0, 1.21, pz), Vector3.ZERO, Vector3(1.0, 1.0, 0.55))
	var bulge := SphereMesh.new()
	bulge.radius = 0.15
	bulge.height = 0.3
	bulge.radial_segments = 20
	bulge.rings = 8
	_gear_mesh(chest, bulge, pack_m, Vector3(0, 1.06, pz - 0.01), Vector3.ZERO, Vector3(1.02, 0.55, 0.62))
	var lid := SphereMesh.new()
	lid.radius = 0.15
	lid.height = 0.15
	lid.is_hemisphere = true
	lid.radial_segments = 20
	lid.rings = 5
	_gear_mesh(chest, lid, pack_d, Vector3(0, 1.385, pz), Vector3.ZERO, Vector3(1.0, 0.5, 0.6))
	var pocket := CapsuleMesh.new()
	pocket.radius = 0.075
	pocket.height = 0.22
	pocket.radial_segments = 14
	pocket.rings = 4
	_gear_mesh(chest, pocket, pack_d, Vector3(0, 1.13, pz - 0.07), Vector3.ZERO, Vector3(1.35, 1.0, 0.45))
	_gear_mesh(chest, _box(Vector3(0.07, 0.022, 0.012)), metal, Vector3(0, 1.2, pz - 0.105))  # pocket buckle
	_gear_mesh(chest, _cyl(0.05, 0.34), roll_m, Vector3(0, 1.455, pz + 0.005), Vector3(0, 0, PI / 2))  # bedroll
	for sx in [-1.0, 1.0]:
		# frame tubes along the sides + hip-belt stubs
		_gear_mesh(chest, _cyl(0.008, 0.56), metal, Vector3(0.155 * sx, 1.2, pz + 0.05))
		_gear_mesh(chest, _cyl(0.03, 0.17), pack_d, Vector3(0.165 * sx, 1.08, pz - 0.02))  # side bottle
		_gear_mesh(chest, _box(Vector3(0.012, 0.12, 0.12)), strap_m, Vector3(0.1 * sx, 1.455, pz + 0.005))  # roll straps
		# compression straps on the sides
		_gear_mesh(chest, _box(Vector3(0.014, 0.018, 0.1)), strap_m, Vector3(0.142 * sx, 1.27, pz - 0.02))
		# shoulder straps: over the top of the shoulder and down the chest
		_gear_mesh(chest, _box(Vector3(0.052, 0.016, 0.2)), strap_m, Vector3(0.1 * sx, 1.47, -0.03), Vector3(0.12, 0, 0))
		_gear_mesh(chest, _box(Vector3(0.05, 0.26, 0.014)), strap_m, Vector3(0.11 * sx, 1.33, 0.162), Vector3(-0.15, 0, 0.0))
	_gear_mesh(chest, _cyl(0.008, 0.31), metal, Vector3(0, 1.49, pz + 0.05), Vector3(0, 0, PI / 2))  # frame top bar
	# chest strap with a buckle, and a small radio on it
	_gear_mesh(chest, _box(Vector3(0.25, 0.03, 0.016)), strap_m, Vector3(0, 1.30, 0.172))
	_gear_mesh(chest, _box(Vector3(0.04, 0.04, 0.02)), metal, Vector3(0, 1.30, 0.178))
	_gear_mesh(chest, _box(Vector3(0.05, 0.08, 0.03)), dark, Vector3(-0.115, 1.38, 0.185))
	_gear_mesh(chest, _cyl(0.005, 0.07), dark, Vector3(-0.13, 1.45, 0.185))
	# ---- utility belt with pouches (waist ring y 1.0, ellipse 0.19 x 0.145)
	var hips := _pin(skel, "Hips")
	var web := _mat(Color(0.07, 0.07, 0.065), 0.85)
	var pouch_m := _mat(Color(0.14, 0.15, 0.12), 0.9)
	_gear_mesh(hips, _cyl(1.0, 0.055), web, Vector3(0, 1.0, -0.022), Vector3.ZERO, Vector3(0.198, 1.0, 0.152))
	_gear_mesh(hips, _box(Vector3(0.06, 0.045, 0.02)), metal, Vector3(0, 1.0, 0.132))
	for sx in [-1.0, 1.0]:
		_gear_mesh(hips, _box(Vector3(0.05, 0.085, 0.075)), pouch_m, Vector3(0.19 * sx, 0.975, -0.01), Vector3(0, 0, 0.06 * sx))
		_gear_mesh(hips, _box(Vector3(0.075, 0.075, 0.045)), pouch_m, Vector3(0.1 * sx, 0.98, -0.17))
	# ---- knee pads + boot cuffs on the shins (legs centred x 0.126; knee front z 0.04)
	for bone in ["LeftLowerLeg", "RightLowerLeg"]:
		var bi := skel.find_bone(bone)
		if bi < 0:
			continue
		var lx := skel.get_bone_global_rest(bi).origin.x
		var sx := signf(lx) if absf(lx) > 0.01 else 1.0
		var shin := _pin(skel, bone)
		var pad := SphereMesh.new()
		pad.radius = 0.062
		pad.height = 0.124
		_gear_mesh(shin, pad, pouch_m, Vector3(0.126 * sx, 0.49, 0.03), Vector3.ZERO, Vector3(1.0, 1.15, 0.45))
		_gear_mesh(shin, _cyl(0.079, 0.11, 0.072), dark, Vector3(0.13 * sx, 0.235, -0.085))
	flashlight.toggled.connect(_on_lamp)
	_on_lamp(flashlight.on)


func _on_lamp(on: bool) -> void:
	if _lamp_lens:
		_lamp_lens.emission_energy_multiplier = 6.0 if on else 0.0


func _update_mouse() -> void:
	if DisplayServer.get_name() == "headless" or Quality.is_phone_platform():
		return   # phones: no pointer capture (touch look is TouchControls)
	var free := Events.modal_open or get_tree().paused or not control_enabled
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if free else Input.MOUSE_MODE_CAPTURED


func set_control(enabled: bool) -> void:
	control_enabled = enabled
	_update_mouse()


func can_act() -> bool:
	return control_enabled and not Events.modal_open and not get_tree().paused


func _unhandled_input(event: InputEvent) -> void:
	if hidden_in and control_enabled and not Events.modal_open and not get_tree().paused:
		if event.is_action_pressed("interact"):
			hidden_in.leave(self)
			get_viewport().set_input_as_handled()
		return
	if not can_act():
		return
	if event.is_action_pressed("flashlight"):
		flashlight.toggle()
		Events.noise.emit(global_position, 1.5, "click")
	elif event.is_action_pressed("reload_battery"):
		flashlight.replace_battery()
	elif event.is_action_pressed("crouch"):
		if int(Settings.get_value("controls", "crouch_mode")) == Settings.TOGGLE:
			toggle_crouch()
		elif not crouching:
			_set_crouch(true)
	elif event.is_action_released("crouch"):
		if int(Settings.get_value("controls", "crouch_mode")) == Settings.HOLD and crouching:
			_want_stand = true
	elif event.is_action_pressed("sprint"):
		_on_sprint_pressed()
	elif event.is_action_pressed("interact"):
		_begin_interact()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_update_mouse()


var sprint_latched := false
signal run_blocked(reason: String)
var run_block_reason := ""      ## v1.2: why the last RUN press could not run ("" = it could)
var run_block_t := 0.0          ## seconds the RUN button stays red
var _latch_idle := 0.0
var _run_check_t := -1.0
var _run_hint_ms := -100000
const RUN_LATCH_GRACE := 0.45   ## a latched run survives this long without stick input (tap RUN, then push)


## v1.2: RUN pressed. Toggle mode latches (and stands you up from a crouch); either mode
## says why when running is not possible right now.
func _on_sprint_pressed() -> void:
	var toggle := int(Settings.get_value("controls", "sprint_mode")) == Settings.TOGGLE
	if toggle and sprint_latched:
		sprint_latched = false
		return
	if crouching:
		if _can_stand():
			_set_crouch(false)
		else:
			_block_run("No room to stand up")
			return
	if not vitals.can_sprint():
		_block_run("Too hurt to run" if vitals.health < Vitals.CRITICAL else "Too tired to run")
		return
	if toggle:
		sprint_latched = true
		_latch_idle = 0.0
	_run_check_t = 0.6   # still not moving after this: tell them to push the stick


func run_blocked_reason_now() -> String:
	if hidden_in or dead:
		return ""
	if crouching and not _can_stand():
		return "No room to stand up"
	if not vitals.can_sprint():
		return "Too hurt to run" if vitals.health < Vitals.CRITICAL else "Too tired to run"
	return ""


func _block_run(reason: String) -> void:
	run_block_reason = reason
	run_block_t = 0.8
	run_blocked.emit(reason)
	var now := Time.get_ticks_msec()
	if now - _run_hint_ms > 2500:
		_run_hint_ms = now
		Events.interaction_feedback.emit(reason)
var _want_stand := false
var threat_near := false     ## the HUD pulse quickens; set by the Keeper while it hunts you
var _breath: AudioStreamPlayer
var _breath_level := 0.0
var _cloth_n := 0


func _process_breath(delta: float) -> void:
	if _breath == null:
		_breath = AudioStreamPlayer.new()
		_breath.bus = &"SFX"
		var s := Sfx.stream("res://audio/sfx2/breath_run.ogg")
		if s:
			_breath.stream = AudioLoop.make(s)
		add_child(_breath)
	var want := clampf((1.0 - vitals.stamina) * 1.3, 0.0, 1.0)
	if vitals.exhausted:
		want = 1.0
	if dead or hidden_in:
		want = want * 0.25
	_breath_level = move_toward(_breath_level, want, delta * 0.7)
	if _breath_level > 0.03 and _breath.stream:
		if not _breath.playing:
			_breath.play()
		_breath.volume_db = linear_to_db(_breath_level) - 9.0
	elif _breath.playing:
		_breath.stop()


## Floor material under the player, for footstep sounds.
func surface() -> String:
	var a := Zones.area_at(global_position)
	for lw in get_tree().get_nodes_in_group("puddles"):
		if (lw as Node3D).global_position.distance_to(global_position) < 1.6:
			return "water"
	match a:
		"lab", "archive":
			return "tile"
		"crawlspace":
			return "metal"
		"shaft":
			return "metal" if absf(global_position.x) < 1.6 and global_position.z > 5.0 else "concrete"
	return "concrete"


func toggle_crouch() -> void:
	if crouching:
		if _can_stand():
			_set_crouch(false)
	else:
		_set_crouch(true)


func _set_crouch(c: bool) -> void:
	crouching = c
	var cap := collider.shape as CapsuleShape3D
	cap.height = crouch_height if c else stand_height
	collider.position.y = cap.height / 2.0


func _can_stand() -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := CapsuleShape3D.new()
	s.radius = 0.33
	s.height = stand_height
	q.shape = s
	q.transform = Transform3D(Basis(), global_position + Vector3.UP * (stand_height / 2.0 + 0.05))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return space.intersect_shape(q, 1).is_empty()


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if can_act() and _action_lock <= 0.0:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_action_lock = maxf(0.0, _action_lock - delta)
	if hidden_in or dead or grabbed:
		input = Vector2.ZERO
	if _want_stand and crouching and _can_stand():
		_want_stand = false
		_set_crouch(false)
	elif _want_stand and not crouching:
		_want_stand = false
	var sprint_held := Input.is_action_pressed("sprint")
	if int(Settings.get_value("controls", "sprint_mode")) == Settings.TOGGLE:
		# v1.2: a short grace, so tap RUN then push the stick works; stops when you let go
		_latch_idle = _latch_idle + delta if input.length() < 0.1 else 0.0
		if _latch_idle > RUN_LATCH_GRACE or not vitals.can_sprint() or crouching:
			sprint_latched = false
		sprint_held = sprint_latched
	run_block_t = maxf(0.0, run_block_t - delta)
	if _run_check_t > 0.0:
		_run_check_t -= delta
		if _run_check_t <= 0.0 and input.length() < 0.1 and can_act() and not hidden_in \
				and (Input.is_action_pressed("sprint") or sprint_latched or int(Settings.get_value("controls", "sprint_mode")) == Settings.TOGGLE):
			_block_run("Push the stick to run" if Ux.using_touch else "Move to run")
	running = sprint_held and not crouching and input.length() > 0.1 and can_act() and vitals.can_sprint() and not hidden_in
	vitals.step(delta, running)
	_process_breath(delta)
	var speed := crouch_speed if crouching else (run_speed if running else walk_speed)
	speed *= vitals.speed_mult()
	if hidden_in or dead or grabbed:
		velocity = Vector3.ZERO
		animator.update_locomotion(0.0, crouching, false)
		return
	var basis_flat := cam.flat_basis()
	var dir := (basis_flat * Vector3(input.x, 0, input.y))
	dir.y = 0
	if dir.length() > 1.0:
		dir = dir.normalized()
	var target_vel := dir * speed
	var hv := Vector3(velocity.x, 0, velocity.z)
	hv = hv.lerp(target_vel, clampf(acceleration * delta, 0.0, 1.0))
	velocity.x = hv.x
	velocity.z = hv.z
	if not is_on_floor():
		velocity.y -= _gravity * delta
		_air_t += delta
	else:
		if _air_t > 0.45:
			Events.noise.emit(global_position, 7.0, "land")
		_air_t = 0.0
		velocity.y = -0.5
	move_and_slide()
	if vitals.exhausted:
		_breath_t -= delta
		if _breath_t <= 0.0:
			_breath_t = 1.2
			Events.noise.emit(global_position, 4.0, "breath")

	# Face the movement direction; when idle with the light on, turn toward the aim.
	var face_dir := Vector3.ZERO
	if hv.length() > 0.3:
		face_dir = hv
	elif flashlight.on:
		var fwd := -basis_flat.z
		if facing_dir().angle_to(fwd) > deg_to_rad(70):
			face_dir = fwd
	if face_dir != Vector3.ZERO:
		var want := yaw_for_dir(face_dir)
		model.rotation.y = lerp_angle(model.rotation.y, want, clampf(turn_speed * delta, 0.0, 1.0))

	animator.update_locomotion(Vector3(velocity.x, 0, velocity.z).length(), crouching, running)
	_update_footsteps(delta, hv.length())
	_update_flashlight_aim()
	_update_interaction(delta)


## The imported model faces +Z, so its rotation is offset by PI from Godot's -Z forward.
func facing_dir() -> Vector3:
	var f := model.global_transform.basis.z
	f.y = 0
	return f.normalized()


func yaw_for_dir(d: Vector3) -> float:
	return atan2(d.x, d.z)


func face_yaw_degrees(deg: float) -> void:
	## Face the same way a camera with this yaw looks.
	model.rotation.y = deg_to_rad(deg) + PI


func _update_flashlight_aim() -> void:
	var ray := cam.aim_ray(40.0)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(ray[0], ray[1], 1, [get_rid()])
	var hit := space.intersect_ray(q)
	var aim_point: Vector3 = hit.position if not hit.is_empty() else ray[1]
	var basis_flat := cam.flat_basis()
	var mount := global_position + Vector3.UP * (1.0 if crouching else 1.45) + basis_flat.x * 0.22 * cam.side + (-basis_flat.z) * 0.35
	flashlight.aim(mount, aim_point)


# --- Interaction ----------------------------------------------------------------
func find_target() -> Node:
	var ray := cam.aim_ray(cam.arm.spring_length + INTERACT_RANGE + 1.0)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(ray[0], ray[1], 1 | 4, [get_rid()])
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	var chest := global_position + Vector3.UP * (0.8 if crouching else 1.2)
	var hit_point := Vector3.INF
	if not hit.is_empty():
		var c: Object = hit.collider
		if c and c.has_method("interact") and chest.distance_to(hit.position) <= INTERACT_RANGE:
			return c
		hit_point = hit.position
	# Assist: nearest interactable in a cone in front of the camera, within reach
	# and in line of sight (helps with small items on the floor).
	var best: Node = null
	var best_score := -INF
	var fwd := -cam.camera.global_transform.basis.z
	for n in get_tree().get_nodes_in_group("interactable"):
		if not (n is Node3D) or not n.is_inside_tree() or not n.has_method("interact"):
			continue
		var p: Vector3 = (n as Node3D).global_position
		var d := chest.distance_to(p)
		if d > INTERACT_RANGE * 0.85:
			continue
		var to := (p - cam.camera.global_position).normalized()
		var dot := fwd.dot(to)
		# Small items resting on a shelf: the ray lands on the board right under them.
		var near_hit := hit_point != Vector3.INF and hit_point.distance_to(p) < 0.3
		if dot < 0.86 and not near_hit:
			continue
		var centre := p + Vector3.UP * 0.1
		var los := PhysicsRayQueryParameters3D.create(chest, centre, 1, [get_rid(), (n as CollisionObject3D).get_rid() if n is CollisionObject3D else RID()])
		var block := space.intersect_ray(los)
		if not block.is_empty() and block.collider != n and block.position.distance_to(centre) > 0.2:
			continue
		var score := dot * 2.0 - d + (1.5 if near_hit else 0.0)
		if score > best_score:
			best_score = score
			best = n
	return best


func _update_interaction(delta: float) -> void:
	var t: Node = find_target() if can_act() else null
	if t != current_target:
		current_target = t
		interaction_target_changed.emit(t)
	if _holding_target:
		if _holding_target != current_target or not Input.is_action_pressed("interact") or not can_act():
			_cancel_hold()
		else:
			_hold_t += delta
			var need: float = _holding_target.get_hold_time(self)
			hold_progress.emit(clampf(_hold_t / need, 0.0, 1.0))
			if _hold_t >= need:
				var tgt := _holding_target
				_cancel_hold()
				_do_interact(tgt)


func _begin_interact() -> void:
	var t := current_target if current_target else find_target()
	if t == null:
		return
	if not t.can_interact(self):
		var r: String = t.get_refusal(self)
		if r != "":
			Events.interaction_feedback.emit(r)
		if t is Door:
			Sfx.play_at("door_locked", (t as Node3D).global_position, 0.0, 1.0, false)
		return
	if t.get_hold_time(self) > 0.0:
		_holding_target = t
		_hold_t = 0.0
		hold_progress.emit(0.0)
		animator.play_action("fix")
	else:
		_do_interact(t)


func _cancel_hold() -> void:
	_holding_target = null
	_hold_t = 0.0
	hold_progress.emit(-1.0)
	animator.stop_action()


func _do_interact(t: Node) -> void:
	if not is_instance_valid(t) or not t.can_interact(self):
		return
	if not (t is Pickup):
		animator.play_action("interact")
	t.interact(self)


## Immediate interaction, bypassing hold timers (tests / debug).
func try_interact(t: Node = null) -> bool:
	if t == null:
		t = find_target()
	if t == null or not t.can_interact(self):
		return false
	t.interact(self)
	return true


func play_pickup(_at: Vector3) -> void:
	animator.play_action("pickup")
	_action_lock = 0.45


func _update_footsteps(delta: float, speed: float) -> void:
	if speed < 0.4 or not is_on_floor():
		_step_t = 0.0
		return
	var interval := 0.32 if running else (0.62 if crouching else 0.5)
	_step_t += delta
	if _step_t >= interval:
		_step_t = 0.0
		var fs := Sfx.footstep_stream(surface())
		if fs:
			footsteps.stream = fs
		if footsteps.stream:
			footsteps.pitch_scale = randf_range(0.92, 1.08)
			footsteps.volume_db = -19.0 if crouching else (-6.0 if running else -11.0)
			footsteps.play()
		_cloth_n += 1
		if running or (crouching and _cloth_n % 2 == 0) or _cloth_n % 3 == 0:
			Sfx.play_at("cloth", self, -4.0 if running else -8.0, randf_range(0.95, 1.1), false)
		var r := NOISE_CROUCH if crouching else (NOISE_RUN if running else NOISE_WALK)
		if r > 0.0:
			Events.noise.emit(global_position, r, "run" if running else "step")


func _on_cam_close(close: bool) -> void:
	for m in _mesh_instances:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if close else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func is_model_hidden() -> bool:
	return _mesh_instances.size() > 0 and _mesh_instances[0].cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY



# --- Phase 4: survival, hiding, death -------------------------------------------
func hurt(amount: float, cause: String) -> void:
	if dead or hidden_in:
		return
	vitals.damage(amount, cause)
	Events.player_hurt.emit(amount, cause)
	Sfx.play("hurt_1" if amount < 40.0 else "hurt_2", -2.0, randf_range(0.95, 1.05))
	rumble(0.5 + amount / 100.0, 0.35)
	if not dead:
		cam.shake(0.25 + amount / 120.0)


func rumble(strength: float, dur: float) -> void:
	if not bool(Settings.get_value("controls", "vibration")):
		return
	for d in Input.get_connected_joypads():
		Input.start_joy_vibration(d, clampf(strength * 0.6, 0.0, 1.0), clampf(strength, 0.0, 1.0), dur)
	# v1.2: phones buzz too (hits, grabs), short so it stays battery-friendly
	if Quality.is_phone_platform():
		Input.vibrate_handheld(int(clampf(dur, 0.05, 0.4) * 1000.0), clampf(strength, 0.1, 1.0))


func use_medkit() -> bool:
	if vitals.health >= 100.0 or not GameState.inventory.has("medkit"):
		return false
	GameState.inventory.remove("medkit")
	vitals.heal(Vitals.MEDKIT)
	Sfx.play("medkit")
	Events.toast.emit("Wound dressed")
	return true


func _on_died(cause: String) -> void:
	if dead:
		return
	dead = true
	set_control(false)
	flashlight.set_on(false)
	Events.player_died.emit(cause)


## The Keeper has its hands on you: no control, face it, the game fades out.
func grab(by: Node3D) -> void:
	if dead:
		return
	grabbed = true
	set_control(false)
	if hidden_in:
		hidden_in.force_out(self)
	var to := by.global_position - global_position
	to.y = 0
	if to.length() > 0.01:
		model.rotation.y = yaw_for_dir(to)
		cam.set_view(rad_to_deg(atan2(-to.x, -to.z)), 4.0)
	vitals.damage(1000.0, "keeper")


func is_hidden() -> bool:
	return hidden_in != null


## Hiding: the body goes into the spot; the spot's own camera takes over.
func enter_hiding(spot: Node) -> void:
	hidden_in = spot
	crouching = false
	collider.disabled = true
	model.visible = false
	flashlight.set_on(false)
	_cancel_hold()
	current_target = null
	interaction_target_changed.emit(null)


func exit_hiding(exit_pos: Vector3) -> void:
	hidden_in = null
	global_position = exit_pos
	velocity = Vector3.ZERO
	collider.disabled = false
	model.visible = true
	cam.camera.current = true


## Snapshot for Continue (Legacy.save_run).
func to_state() -> Dictionary:
	return {"pos": [global_position.x, global_position.y, global_position.z], "yaw": cam.yaw_degrees(),
		"vitals": vitals.to_dict(), "light": flashlight.on, "battery": flashlight.battery.charge}


func from_state(d: Dictionary) -> void:
	var p: Array = d.get("pos", [])
	if p.size() == 3:
		global_position = Vector3(p[0], p[1], p[2])
		cam.global_position = global_position + Vector3.UP * 1.55
	cam.set_view(float(d.get("yaw", 0.0)), -10.0)
	vitals.from_dict(d.get("vitals", {}))
	if d.has("battery"):
		flashlight.battery.charge = float(d["battery"])
	flashlight.set_on(bool(d.get("light", true)) and flashlight.battery.charge > 0.0)
