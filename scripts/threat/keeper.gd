class_name Keeper
extends CharacterBody3D
## THE KEEPER - what is left of a member who stayed. It hunts by sound, sees
## your light from far away, and hates light pointed at it.
##
## Rules the player can learn (and the tests check):
##   * It sleeps until the power comes on ("it hears the power come on"), or
##     until the expedition has been down here too long, or a very loud noise.
##   * Footsteps: walking is heard at 4.5 m, running at 13 m, crouching is silent.
##   * It sees 7 m in the dark, 18 m when your flashlight is on, 4.5 m if you're
##     crouched in the dark. It needs a moment to notice you unless you're close.
##   * Holding the flashlight on its face for half a second drives it back
##     (and drinks 12% of your battery).
##   * White working light keeps it out. It can smother a light, but the light
##     stutters first. Red emergency light does not count.
##   * Closed doors slow it down; locked doors stop it.
##   * Hide (locker, under the cot) where it can't see you go in and it loses you.
##     If it watched you go in, it will pull you out.
##   * The first time it catches you it strikes and lets go (you are injured).
##     Injured, the next catch is the end.

signal state_changed(state: int)
signal caught_player(fatal: bool)

enum S { DORMANT, PATROL, INVESTIGATE, CHASE, SEARCH, REPELLED, RETREAT, WAIT_LIGHT, GRAB }
const NAMES := ["dormant", "patrol", "investigate", "chase", "search", "repelled", "retreat", "wait_light", "grab"]

const SPEED := {S.PATROL: 1.25, S.INVESTIGATE: 2.0, S.CHASE: 3.6, S.SEARCH: 1.6, S.RETREAT: 3.2}
const SIGHT_DARK := 7.0
const SIGHT_LIGHT := 18.0
const SIGHT_CROUCH := 4.5
const SIGHT_POOL := 14.0
const FOV_DEG := 75.0
const CATCH_RANGE := 1.15
const LOSE_AFTER := 2.6
const SEARCH_TIME := 6.0
const REPEL_BEAM_TIME := 0.6
const REPEL_RANGE := 10.0
const REPEL_COST := 0.12
const WAKE_AFTER := 240.0
const SEEN_HIDING_RANGE := 7.0   ## balance pass (was 10): it has to be close to see which locker
const CHASE_WINDUP := 0.55     ## balance pass: a head start the moment it spots you
var _windup := 0.0

var state := S.DORMANT
var player: Player
var agent: NavigationAgent3D
var awareness := 0.0
var last_seen := Vector3.ZERO
var investigate_pos := Vector3.ZERO
var state_t := 0.0
var lost_t := 0.0
var beam_t := 0.0
var repel_cooldown := 0.0
var seen_hiding: Node = null
var speed_scale := 1.0
var think := true                 ## tests can freeze the brain and drive states directly
var lair := Vector3.ZERO
var patrol_points: Array[Vector3] = []
var blocked_until := {}           ## patrol point index -> time
var _blocked_door_t := 0.0
var _door_pause := 0.0
var _repath_t := 0.0
var _rng := RandomNumberGenerator.new()
var _model: Node3D
var _anim: AnimationPlayer
var _eyes: Array[MeshInstance3D] = []
var _eye_mat: StandardMaterial3D
var _breath: AudioStreamPlayer3D
var _voice: AudioStreamPlayer3D
var _steps: AudioStreamPlayer3D
var _step_t := 0.0
var _gravity := 9.8
var _time := 0.0
var _flicker_t := 0.0


func _ready() -> void:
	add_to_group("keeper")
	_rng.randomize()
	collision_layer = 16
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 2.1
	cs.shape = cap
	cs.position.y = 1.05
	add_child(cs)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 0.6
	agent.path_max_distance = 3.0
	agent.radius = 0.35
	agent.height = 2.1
	add_child(agent)
	_build_visual()
	_build_audio()
	lair = global_position
	speed_scale = GameState.difficulty
	if not Engine.is_editor_hint():
		Events.noise.connect(_on_noise)
		GameState.grid.circuit_changed.connect(_on_circuit)


func setup(p: Player, points: Array) -> void:
	player = p
	patrol_points.clear()
	for v in points:
		patrol_points.append(v)


func _build_visual() -> void:
	_model = load("res://assets/characters/explorer/Explorer.gltf").instantiate()
	_model.name = "Model"
	_model.rotation = Vector3(0.0, PI, 0.0)
	add_child(_model)
	var skel := _model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	_anim = AnimationPlayer.new()
	_anim.name = "AnimationPlayer"
	_model.add_child(_anim)
	_anim.add_animation_library("", load("res://assets/characters/ual_animations.res"))
	if skel == null:
		return
	KeeperBody.stretch(skel)
	var built := KeeperBody.build(skel, _skin_material(), _rag_material())
	for idx in 2:
		var mi := MeshInstance3D.new()
		mi.name = "Body" if idx == 0 else "Rags"
		mi.mesh = built[idx]
		mi.skin = built[2]
		skel.add_child(mi)
		mi.skeleton = mi.get_path_to(skel)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	poser = KeeperPoser.new()
	poser.name = "Poser"
	skel.add_child(poser)
	# the helmet it came down in, fused to the skull: cracked shell, dead lamp
	var ba := BoneAttachment3D.new()
	ba.bone_name = "Head"
	skel.add_child(ba)
	var hm := Node3D.new()
	hm.name = "FusedHelmet"
	hm.position = Vector3(0.0, 0.2, -0.01)
	hm.rotation = Vector3(-0.5, 0.0, 0.32)
	ba.add_child(hm)
	var shell_m := StandardMaterial3D.new()
	shell_m.albedo_color = Color(0.42, 0.37, 0.28)
	shell_m.roughness = 0.7
	shell_m.albedo_texture = _noise_tex(0.09, false)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.04, 0.035, 0.03)
	dark.roughness = 0.6
	var shell := SphereMesh.new()
	shell.radius = 0.13
	shell.height = 0.17
	shell.is_hemisphere = true
	shell.radial_segments = 24
	shell.rings = 8
	_part(hm, shell, shell_m, Vector3.ZERO, Vector3(0.95, 1.0, 1.1))
	var brim := CylinderMesh.new()
	brim.top_radius = 0.138
	brim.bottom_radius = 0.138
	brim.height = 0.016
	brim.radial_segments = 24
	_part(hm, brim, dark, Vector3(0, 0.002, 0), Vector3(0.95, 1.0, 1.1))
	var lamp := CylinderMesh.new()
	lamp.top_radius = 0.022
	lamp.bottom_radius = 0.024
	lamp.height = 0.04
	var lamp_mi := _part(hm, lamp, dark, Vector3(0.0, 0.06, 0.14), Vector3.ONE)
	lamp_mi.rotation.x = PI / 2
	var crack := BoxMesh.new()
	crack.size = Vector3(0.012, 0.004, 0.16)
	var crack_mi := _part(hm, crack, dark, Vector3(0.05, 0.115, 0.0), Vector3.ONE)
	crack_mi.rotation = Vector3(0.0, 0.5, -0.4)
	# where it grew into the skin: lumps of flesh over the brim
	for kk in 5:
		var lump := SphereMesh.new()
		lump.radius = 0.03
		lump.height = 0.05
		var a := -0.9 + kk * 0.45
		_part(hm, lump, _skin_material(), Vector3(sin(a) * 0.125, -0.005, cos(a) * 0.135 - 0.02), Vector3(1.4, 0.8, 1.0))
	# pale glints under the brim: the fair warning. No face to go with them.
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(0.7, 0.8, 0.85)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(0.75, 0.88, 1.0)
	_eye_mat.emission_energy_multiplier = 3.0
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for sx in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.011
		sm.height = 0.016
		e.mesh = sm
		e.material_override = _eye_mat
		e.position = Vector3(0.03 * sx, 0.12, 0.1)
		ba.add_child(e)
		_eyes.append(e)


var poser: KeeperPoser
static var _skin_mat: StandardMaterial3D
static var _rag_mat: StandardMaterial3D


static func _noise_tex(freq: float, normal: bool) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = freq
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	t.as_normal_map = normal
	t.bump_strength = 6.0
	return t


static func _skin_material() -> StandardMaterial3D:
	if _skin_mat == null:
		_skin_mat = StandardMaterial3D.new()
		_skin_mat.albedo_color = Color(0.2, 0.185, 0.165)
		_skin_mat.albedo_texture = _noise_tex(0.05, false)
		_skin_mat.roughness = 0.58          # damp skin, like something that came out of the tank
		_skin_mat.metallic_specular = 0.35
		_skin_mat.roughness_texture = _noise_tex(0.11, false)
		_skin_mat.normal_enabled = false
		_skin_mat.normal_texture = _noise_tex(0.08, true)
		_skin_mat.normal_scale = 0.45
		_skin_mat.uv1_scale = Vector3(1.5, 1.5, 1.5)
		_skin_mat.rim_enabled = true
		_skin_mat.rim = 0.45
		_skin_mat.rim_tint = 0.5
		_skin_mat.emission_enabled = true
		_skin_mat.emission = Color(0.03, 0.045, 0.05)
		_skin_mat.emission_energy_multiplier = 0.3
	return _skin_mat


static func _rag_material() -> StandardMaterial3D:
	if _rag_mat == null:
		_rag_mat = StandardMaterial3D.new()
		_rag_mat.albedo_color = Color(0.36, 0.17, 0.08)   # what is left of a field coverall
		_rag_mat.albedo_texture = _noise_tex(0.12, false)
		_rag_mat.roughness = 0.92
		_rag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _rag_mat


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _build_audio() -> void:
	_breath = AudioStreamPlayer3D.new()
	_breath.bus = &"SFX"
	_breath.unit_size = 3.0
	_breath.max_distance = 22.0
	_breath.position.y = 1.9
	var b: AudioStream = load("res://audio/keeper/keeper_breath.ogg")
	if b:
		_breath.stream = AudioLoop.make(b)
	add_child(_breath)
	_voice = AudioStreamPlayer3D.new()
	_voice.bus = &"SFX"
	_voice.unit_size = 8.0
	_voice.max_distance = 60.0
	_voice.position.y = 1.9
	add_child(_voice)
	_steps = AudioStreamPlayer3D.new()
	_steps.bus = &"SFX"
	_steps.unit_size = 4.0
	_steps.max_distance = 30.0
	_steps.stream = load("res://audio/keeper/keeper_step_1.ogg")
	_steps.volume_db = -2.0
	add_child(_steps)


const VOICE := {"keeper_alert": "keeper_alert", "keeper_shriek": "keeper_hurt", "keeper_wake": "keeper_scream",
	"keeper_grab": "keeper_grab", "keeper_strike": "keeper_lunge", "keeper_click": "keeper_click",
	"keeper_sniff": "keeper_sniff", "keeper_crawl": "keeper_crawl", "keeper_drag": "keeper_drag"}
var _vocal_t := 6.0


func _play_voice(id: String, vol := 0.0) -> void:
	var f: String = VOICE.get(id, id)
	var s: AudioStream = Sfx.stream("res://audio/keeper/%s.ogg" % f)
	if s:
		_voice.stream = s
		_voice.volume_db = vol - 2.0
		_voice.pitch_scale = _rng.randf_range(0.92, 1.04)
		_voice.play()
		Sfx.caption_for(f, global_position)


# ------------------------------------------------------------------ state machine
func set_state(s: int, keep_target := false) -> void:
	if s == state:
		return
	var prev := state
	state = s
	state_t = 0.0
	if player and is_instance_valid(player):
		player.threat_near = s in [S.CHASE, S.WAIT_LIGHT, S.GRAB]
	match s:
		S.CHASE:
			lost_t = 0.0
			if prev in [S.PATROL, S.INVESTIGATE, S.SEARCH, S.DORMANT]:
				_windup = CHASE_WINDUP
			if prev != S.WAIT_LIGHT:
				_play_voice("keeper_alert", 2.0)
				if prev != S.REPELLED:
					Sfx.play("sting_spotted", -4.0)
				if player:
					player.rumble(0.35, 0.3)
		S.REPELLED:
			_play_voice("keeper_shriek", 3.0)
		S.SEARCH:
			agent.target_position = last_seen
		S.PATROL:
			if not keep_target:
				_pick_patrol()
	if _breath and _breath.stream:
		if s == S.DORMANT:
			_breath.stop()
		elif not _breath.playing:
			_breath.play()
	state_changed.emit(s)
	Events.keeper_state.emit(state_name())


func state_name() -> String:
	return NAMES[state]


const VENT_EXIT := Vector3(0.0, 0.05, -19.6)   ## corridor ceiling vent by the lab door


func wake() -> void:
	if state == S.DORMANT:
		set_state(S.PATROL)
		_play_voice("keeper_wake", -4.0)
		# shut in Lab 3 behind the coded door: it takes the ceiling ducts instead
		var lab := get_tree().get_first_node_in_group("doors") as Door
		for dn in get_tree().get_nodes_in_group("doors"):
			if (dn as Door).persist_id == "door_lab":
				lab = dn
		if lab and lab.persist_id == "door_lab" and not lab.keeper_can_open() and global_position.z < -22.0:
			get_tree().create_timer(2.0).timeout.connect(_vent_out)


func _vent_out() -> void:
	if state in [S.DORMANT, S.GRAB] or in_vent:
		return
	in_vent = true
	var was_think := think
	think = false
	velocity = Vector3.ZERO
	# up into the Lab 3 ceiling duct: it climbs, reaching up, and is gone
	_play_voice("keeper_crawl", -2.0)
	var start := global_position
	var ok := await _vent_phase(0.8, func(x: float):
		global_position = start + Vector3.UP * 2.9 * x
		_model.rotation.x = -x * 1.2
		if poser:
			poser.crawl = x * 0.6
			poser.reach = x)
	if ok:
		visible = false
		# it moves through the duct over your head: you hear it before it drops
		var duct := AudioStreamPlayer3D.new()
		duct.bus = &"SFX"
		duct.stream = Sfx.stream("res://audio/keeper/keeper_crawl.ogg")
		duct.max_distance = 30.0
		get_parent().add_child(duct)
		duct.global_position = start + Vector3.UP * 3.0
		duct.play()
		var top := start + Vector3.UP * 2.9
		ok = await _vent_phase(1.0, func(x: float):
			duct.global_position = (start + Vector3.UP * 3.0).lerp(VENT_EXIT + Vector3.UP * 3.1, x)
			global_position = top)
		duct.queue_free()
	if ok:
		Sfx.play_at("vent_bang", VENT_EXIT + Vector3.UP * 3.0)
		# head first out of the corridor vent, arms down to the floor, then it unfolds
		global_position = VENT_EXIT + Vector3.UP * 2.6
		visible = true
		_model.rotation.x = 1.25
		ok = await _vent_phase(0.6, func(x: float):
			global_position = VENT_EXIT + Vector3.UP * 2.6 * (1.0 - x * x)
			if poser:
				poser.crawl = 0.8
				poser.reach = 1.0)
	visible = true
	if ok:
		Sfx.play_at("keeper_drag", VENT_EXIT, -2.0)
		Events.noise.emit(VENT_EXIT, 0.0, "vent")
		global_position = VENT_EXIT
	# from here it is back in the world: it unfolds while it starts to move
	in_vent = false
	think = was_think
	if state == S.PATROL or not ok:
		set_state(state if not ok else S.PATROL)
	var tw := create_tween()
	tw.tween_method(func(x: float):
		_model.rotation.x = _model.rotation.x * (1.0 - x)
		if poser:
			poser.crawl = poser.crawl * (1.0 - x), 0.0, 1.0, 0.7 / vent_speed)
	tw.tween_callback(func(): _model.rotation.x = 0.0)
	vent_done.emit()


## One step of the vent sequence; returns false (and stops) if something else moved
## the Keeper meanwhile (a test, a debug teleport, the game ending).
func _vent_phase(dur: float, f: Callable) -> bool:
	var x := 0.0
	var expect := global_position
	while x < 1.0:
		await get_tree().physics_frame
		if not is_inside_tree():
			return false
		if global_position.distance_to(expect) > 0.3:
			return false
		x = minf(1.0, x + get_physics_process_delta_time() * vent_speed / dur)
		f.call(x)
		expect = global_position
	return true


signal vent_done
var in_vent := false
static var vent_speed := 1.0


func _on_circuit(id: String, powered: bool) -> void:
	# "Whatever's in that lab, it hears the power come on."
	if id == "aux" and powered and state == S.DORMANT and GameState.threat_enabled:
		get_tree().create_timer(6.0).timeout.connect(wake)


func _on_noise(pos: Vector3, radius: float, source: String) -> void:
	if not GameState.threat_enabled or not think:
		return
	var d := pos.distance_to(global_position)
	if d > radius:
		return
	match state:
		S.DORMANT:
			if radius >= 9.0:
				wake()
				_investigate(pos)
		S.PATROL, S.SEARCH:
			_investigate(pos)
		S.INVESTIGATE:
			# already on its way to something: the station's own hiss and clank
			# doesn't pull it off; anything you make does
			if not source in ["steam", "vent", "door"]:
				_investigate(pos)
		S.CHASE:
			if source in ["run", "step", "land", "breath", "winded"]:
				last_seen = pos
				lost_t = minf(lost_t, LOSE_AFTER * 0.5)


func _investigate(pos: Vector3) -> void:
	investigate_pos = pos
	agent.target_position = pos
	if state != S.INVESTIGATE:
		set_state(S.INVESTIGATE)
	else:
		state_t = 0.0


func _physics_process(delta: float) -> void:
	_time += delta
	state_t += delta
	repel_cooldown = maxf(0.0, repel_cooldown - delta)
	if not GameState.threat_enabled:
		return
	if in_vent:
		_animate()
		return
	if think:
		_think(delta)
	_move(delta)
	_animate()
	_presence(delta)


func _think(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.dead and state != S.GRAB:
		set_state(S.PATROL)
		return
	match state:
		S.DORMANT:
			if GameState.elapsed > WAKE_AFTER:
				wake()
		S.PATROL:
			if _notice(delta):
				return
			if agent.is_navigation_finished() or state_t > 25.0:
				state_t = 0.0
				_pick_patrol()
		S.INVESTIGATE:
			if _notice(delta):
				return
			if agent.is_navigation_finished():
				if state_t > 3.5 + _arrive_t():
					set_state(S.SEARCH)
			elif state_t > 20.0:
				set_state(S.PATROL)
		S.SEARCH:
			if _notice(delta):
				return
			if agent.is_navigation_finished() and state_t > 1.5:
				# look around the last place it knew about
				var off := Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3))
				agent.target_position = last_seen + off
			if state_t > SEARCH_TIME:
				seen_hiding = null
				set_state(S.PATROL)
		S.CHASE:
			_chase(delta)
		S.WAIT_LIGHT:
			_wait_light(delta)
		S.REPELLED:
			if state_t > 1.2:
				_retreat()
		S.RETREAT:
			if agent.is_navigation_finished() or state_t > 10.0:
				set_state(S.PATROL)
		S.GRAB:
			pass
	_check_beam(delta)


func _arrive_t() -> float:
	return 0.0


## Build awareness while it can see the player; returns true when it starts a chase.
func _notice(delta: float) -> bool:
	if can_see_player():
		var d := global_position.distance_to(player.global_position)
		var rate := 3.0 if d < 4.0 else lerpf(2.0, 0.9, clampf(d / sight_range(), 0.0, 1.0))
		awareness = minf(1.0, awareness + rate * delta)
		if awareness >= 1.0:
			last_seen = player.global_position
			set_state(S.CHASE)
			return true
	else:
		awareness = maxf(0.0, awareness - 0.5 * delta)
	return false


func _chase(delta: float) -> void:
	if seen_hiding and is_instance_valid(seen_hiding) and player.hidden_in == seen_hiding:
		# it watched you go in
		var spot_pos: Vector3 = seen_hiding.call("outside_point")
		agent.target_position = spot_pos
		if global_position.distance_to(spot_pos) < 1.4:
			_catch(true)
		return
	if can_see_player():
		last_seen = player.global_position
		lost_t = 0.0
	else:
		lost_t += delta
		if lost_t > LOSE_AFTER:
			set_state(S.SEARCH)
			return
	_repath_t -= delta
	if _repath_t <= 0.0:
		_repath_t = 0.2
		agent.target_position = last_seen
	var d := global_position.distance_to(player.global_position)
	var pool := PoweredLight.pool_at(get_tree(), player.global_position)
	if pool and d < 4.0 and not PoweredLight.pool_at(get_tree(), global_position):
		_block_on(pool)
		return
	if d < CATCH_RANGE and can_see_player():
		_catch(false)


var _blocking_pool: PoweredLight
var _resume_state := S.PATROL


## A lit pool is in the way: stop at its edge and wait / smother it.
func _block_on(pool: PoweredLight) -> void:
	_blocking_pool = pool
	if state != S.WAIT_LIGHT:
		_resume_state = state
	set_state(S.WAIT_LIGHT)


func _wait_light(_delta: float) -> void:
	# stands at the edge of the light, then smothers it (the light stutters first)
	var pool := _blocking_pool
	if pool == null or not is_instance_valid(pool) or not pool.covers(pool.global_position):
		set_state(_resume_state, true)
		return
	if state_t > 0.6 and not pool.is_suppressed():
		pool.suppress(7.0, 1.4)
	if state_t > 8.0:
		# couldn't put it out (it was smothered not long ago): try another way
		if _resume_state in [S.CHASE, S.WAIT_LIGHT]:
			last_seen = player.global_position if player else last_seen
			set_state(S.SEARCH)
		else:
			if _current_patrol >= 0:
				blocked_until[_current_patrol] = _time + 20.0
			set_state(S.PATROL)
			_pick_patrol()


func _catch(fatal_override: bool) -> void:
	if player.dead:
		return
	var fatal := fatal_override or player.vitals.health < Vitals.INJURED
	caught_player.emit(fatal)
	if fatal:
		set_state(S.GRAB)
		velocity = Vector3.ZERO
		look_at_flat(player.global_position)
		_play_voice("keeper_grab", 4.0)
		player.grab(self)
	else:
		# it strikes, then lets go. It is keeping count.
		_play_voice("keeper_strike", 3.0)
		player.hurt(55.0, "keeper")
		var push := (player.global_position - global_position)
		push.y = 0
		player.velocity += push.normalized() * 6.0
		_retreat()


func _retreat() -> void:
	# run to the patrol point farthest from the player
	var best := lair
	var best_d := -1.0
	for pp in patrol_points:
		var d := pp.distance_to(player.global_position) if player else 0.0
		if d > best_d:
			best_d = d
			best = pp
	agent.target_position = best
	awareness = 0.0
	seen_hiding = null
	set_state(S.RETREAT)


func repel() -> bool:
	if state in [S.DORMANT, S.REPELLED, S.RETREAT, S.GRAB] or repel_cooldown > 0.0:
		return false
	repel_cooldown = 4.0
	set_state(S.REPELLED)
	if player:
		var fl := player.flashlight
		fl.battery.charge = maxf(0.0, fl.battery.charge - REPEL_COST)
		fl.battery_changed.emit(fl.battery.charge)
	return true


func _check_beam(delta: float) -> void:
	if player == null or state in [S.DORMANT, S.REPELLED, S.RETREAT, S.GRAB]:
		beam_t = 0.0
		return
	if is_in_beam():
		beam_t += delta
		if beam_t >= REPEL_BEAM_TIME:
			beam_t = 0.0
			repel()
	else:
		beam_t = maxf(0.0, beam_t - delta * 2.0)


## Is the player's flashlight shining on it (cone + range + line of sight)?
func is_in_beam() -> bool:
	if player == null or not player.flashlight.on or player.hidden_in:
		return false
	var spot := player.flashlight.light
	var origin := spot.global_position
	var chest := global_position + Vector3.UP * 1.5
	var to := chest - origin
	if to.length() > REPEL_RANGE:
		return false
	var fwd := -spot.global_transform.basis.z
	if rad_to_deg(fwd.angle_to(to)) > 16.0:
		return false
	return _clear_line(origin, chest)


func sight_range() -> float:
	if player == null:
		return 0.0
	var dark := not player.flashlight.on
	if PoweredLight.pool_at(get_tree(), player.global_position):
		return SIGHT_POOL
	if not dark:
		return SIGHT_LIGHT
	return SIGHT_CROUCH if player.crouching else SIGHT_DARK


func can_see_player() -> bool:
	if player == null or player.hidden_in or player.dead:
		return false
	var eye := global_position + Vector3.UP * 1.9
	var target := player.global_position + Vector3.UP * (0.9 if player.crouching else 1.3)
	var to := target - eye
	var d := to.length()
	if d > sight_range():
		return false
	var fwd := -global_transform.basis.z
	var flat := Vector3(to.x, 0, to.z)
	if d > 2.5 and rad_to_deg(fwd.angle_to(flat)) > FOV_DEG:
		return false
	return _clear_line(eye, target)


func _clear_line(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1, [get_rid()])
	if player:
		q.exclude = [get_rid(), player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Called by a HidingSpot as the player climbs in.
func on_player_hiding(spot: Node) -> void:
	if state in [S.CHASE, S.WAIT_LIGHT] and player and _clear_line(global_position + Vector3.UP * 1.9, player.global_position + Vector3.UP * 1.2) \
			and global_position.distance_to(player.global_position) < SEEN_HIDING_RANGE:
		seen_hiding = spot
	else:
		seen_hiding = null


func _pick_patrol() -> void:
	if patrol_points.is_empty():
		agent.target_position = lair
		return
	var cands: Array[int] = []
	var near: Array[int] = []
	for i in patrol_points.size():
		if blocked_until.get(i, -1.0) > _time:
			continue
		if patrol_points[i].distance_to(global_position) < 2.0:
			continue
		cands.append(i)
		if player and patrol_points[i].distance_to(player.global_position) < 16.0:
			near.append(i)
	if cands.is_empty():
		agent.target_position = lair
		return
	# it stalks: more often than not it drifts toward where you are
	var pool := near if not near.is_empty() and _rng.randf() < 0.6 else cands
	var idx: int = pool[_rng.randi() % pool.size()]
	_current_patrol = idx
	agent.target_position = patrol_points[idx]


var _current_patrol := -1


# ------------------------------------------------------------------ movement
var _height_fixed := false


func _fix_height() -> void:
	# the navmesh surface sits a little above the floor; measure it once so the
	# agent's 3D "waypoint reached" check works on flat ground
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return
	var cp := NavigationServer3D.map_get_closest_point(map, global_position)
	if cp != Vector3.ZERO:
		agent.path_height_offset = maxf(0.0, cp.y - global_position.y)
		_height_fixed = true


func _move(delta: float) -> void:
	if not _height_fixed:
		_fix_height()
	var spd: float = SPEED.get(state, 0.0) * speed_scale
	if _door_pause > 0.0:
		_door_pause -= delta
		spd = 0.0
	if _windup > 0.0:
		# the moment it sees you: it straightens and screams before it comes
		_windup -= delta
		spd = 0.0
		if player:
			look_at_flat(player.global_position, delta * 8.0)
	var vel := Vector3.ZERO
	if spd > 0.0 and not agent.is_navigation_finished():
		var nxt := agent.get_next_path_position()
		var dir := nxt - global_position
		dir.y = 0
		if dir.length() > 0.05:
			dir = dir.normalized()
			# white light keeps it out: it won't step into a lit pool unless it's chasing
			# and the light is smothered
			var ahead := global_position + dir * 0.6
			var pool_ahead := PoweredLight.pool_at(get_tree(), ahead)
			if pool_ahead and not PoweredLight.pool_at(get_tree(), global_position) and state != S.RETREAT:
				_block_on(pool_ahead)
				dir = Vector3.ZERO
			vel = dir * spd
			if dir != Vector3.ZERO:
				look_at_flat(global_position + dir, delta * 6.0)
			_handle_doors(dir)
	if state == S.WAIT_LIGHT and player:
		look_at_flat(player.global_position, delta * 4.0)
	velocity.x = vel.x
	velocity.z = vel.z
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = -0.3
	move_and_slide()


func look_at_flat(p: Vector3, k := 1.0) -> void:
	var d := p - global_position
	d.y = 0
	if d.length() < 0.01:
		return
	var want := atan2(-d.x, -d.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(k, 0.0, 1.0))


func _handle_doors(dir: Vector3) -> void:
	if dir == Vector3.ZERO:
		return
	for dn in get_tree().get_nodes_in_group("doors"):
		var door := dn as Door
		if door == null or door.is_open() or door.state == Door.State.OPENING:
			continue
		var to := door.global_position - global_position
		to.y = 0
		if to.length() > 1.5 or dir.dot(to.normalized()) < 0.3:
			continue
		if door.keeper_can_open():
			door.open()
			_door_pause = 0.8
			Events.noise.emit(door.global_position, 0.0, "door")
		else:
			# locked or unpowered: it can't get through here
			if state == S.CHASE:
				set_state(S.SEARCH)
			elif _current_patrol >= 0:
				blocked_until[_current_patrol] = _time + 45.0
				_pick_patrol()
			else:
				agent.target_position = lair
		return


# ------------------------------------------------------------------ presentation
func _animate() -> void:
	if _anim == null:
		return
	var v := Vector2(velocity.x, velocity.z).length()
	var clip := "Idle"
	var sp := 1.0
	var dt := get_physics_process_delta_time()
	# target pose layer for the creature: hunch, search sniffing, reaching, crawl
	var want := {"hunch": 0.75, "search": 0.0, "reach": 0.0, "grab": 0.0, "shield": 0.0, "crawl": 0.0}
	var d := player.global_position.distance_to(global_position) if player and is_instance_valid(player) else 99.0
	match state:
		S.DORMANT:
			clip = "Crouch_Idle"
			sp = 0.3
			want["hunch"] = 1.0
			want["crawl"] = 0.35
		S.REPELLED:
			clip = "Hit_Chest"
			want["shield"] = 1.0
			want["hunch"] = 1.0
		S.GRAB:
			clip = "Idle"
			want["reach"] = 1.0
			want["grab"] = 1.0
			want["hunch"] = 0.4
		S.SEARCH:
			clip = "Crouch_Fwd" if v > 0.3 else "Crouch_Idle"
			sp = 0.75
			want["search"] = 1.0
			want["hunch"] = 1.0
			want["crawl"] = 0.25
		S.WAIT_LIGHT:
			clip = "Idle"
			sp = 0.6
			want["hunch"] = 1.0
			want["search"] = 0.35
		S.RETREAT:
			clip = "Sprint" if v > 2.5 else "Walk"
			want["hunch"] = 1.0
			want["crawl"] = 0.3
		S.CHASE:
			clip = "Jog_Fwd" if v > 2.5 else ("Walk" if v > 0.3 else "Idle")
			sp = 0.95
			want["hunch"] = 0.55
			want["reach"] = 0.45 if d > 3.2 else 1.0     # the lunge: both arms out for you
		S.INVESTIGATE:
			clip = "Walk" if v > 0.3 else "Idle"
			sp = 0.7
			want["search"] = 0.5
		_:
			clip = "Walk" if v > 0.3 else "Idle"
			sp = 0.62 if v > 0.3 else 0.5
	if in_vent:
		want = {}
	if not _anim.has_animation(clip):
		clip = "Idle"
	if _anim.current_animation != clip:
		_anim.play(clip, 0.3)
	_anim.speed_scale = sp
	if poser:
		for key in want:
			poser.set(key, move_toward(float(poser.get(key)), want[key], dt * 3.0))
	_step_t -= dt * v
	if v > 0.3 and _step_t <= 0.0:
		_step_t = 1.1
		if _steps.stream:
			_steps.stream = Sfx.stream("res://audio/keeper/keeper_step_%d.ogg" % (1 + _rng.randi() % 2))
			_steps.pitch_scale = randf_range(0.8, 0.95)
			_steps.volume_db = (0.0 if state == S.CHASE else -5.0)
			_steps.play()
			if state == S.CHASE and d < 12.0:
				Sfx.caption_for("keeper_step", global_position, 1.5)


func _presence(delta: float) -> void:
	# its voice gives it away: clicks while it wanders, sniffing while it searches
	_vocal_t -= delta
	if _vocal_t <= 0.0 and state in [S.PATROL, S.SEARCH, S.INVESTIGATE]:
		_vocal_t = _rng.randf_range(5.0, 11.0)
		if not _voice.playing:
			_play_voice("keeper_sniff" if state != S.PATROL else "keeper_click", -3.0)
	# lights near it stutter: you can tell it's close before you see it
	_flicker_t -= delta
	if _flicker_t > 0.0 or state == S.DORMANT:
		return
	_flicker_t = 0.15
	for l in get_tree().get_nodes_in_group("powered_lights"):
		var pl := l as PoweredLight
		if pl.is_on() and not pl.is_suppressed() and pl.global_position.distance_to(global_position) < 5.5 and _rng.randf() < 0.35:
			pl._apply(_rng.randf_range(0.2, 0.7))
	var e := 5.0 if state in [S.CHASE, S.WAIT_LIGHT] else 2.5
	_eye_mat.emission_energy_multiplier = e
