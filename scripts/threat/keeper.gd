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

enum S { DORMANT, PATROL, INVESTIGATE, CHASE, SEARCH, REPELLED, RETREAT, WAIT_LIGHT, GRAB, LUNGE }
const NAMES := ["dormant", "patrol", "investigate", "chase", "search", "repelled", "retreat", "wait_light", "grab", "lunge"]

const SPEED := {S.PATROL: 1.25, S.INVESTIGATE: 2.0, S.CHASE: 3.4, S.SEARCH: 1.6, S.RETREAT: 3.2}   # Phase 6: chase 3.6 -> 3.4
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
const SEEN_HIDING_RANGE := 5.0   ## Phase 6 (was 7, 10 before that): it has to be close to see which locker
const CHASE_WINDUP := 0.55     ## balance pass: a head start the moment it spots you
## Phase 6 fairness: it never strikes from a run. In reach it stops, rears back and
## screams (the telegraph), then lunges along a straight line. A player who keeps
## running or steps aside makes it miss, and a miss leaves it staggering.
const LUNGE_RANGE := 2.1
const LUNGE_TELEGRAPH := 0.5
const LUNGE_TIME := 0.3
const LUNGE_SPEED := 7.0
const LUNGE_HIT := 1.0
const LUNGE_RECOVER := 1.0
## A fresh chase starts slower and builds up to full speed.
const CHASE_START_SPEED := 2.3
const CHASE_RAMP := 3.0
var _lunge_dir := Vector3.FORWARD
var _lunge_hit := false
var _chase_ramp_t := 99.0
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
	# Phase 6: one continuous skinned creature mesh (assets/characters/keeper/Keeper.gltf),
	# sculpted from the CC0 Quaternius base body by tools/sculpt_keeper.py: stretched,
	# gaunt limbs with knobbed joints, a shrunken belly under a ribcage, a long neck and a
	# smooth faceless skull; the torn coverall is a cloth layer skinned to the same rig.
	_model = load("res://assets/characters/keeper/Keeper.gltf").instantiate()
	_model.name = "Model"
	_model.rotation = Vector3(0.0, PI, 0.0)
	add_child(_model)
	var skel := _model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	# v1.1: the Keeper's own clips, keyframed in Blender (tools/keeper_anim/), driven by an
	# AnimationTree from the AI state below. The pose layer (keeper_poser.gd) now only aims the head.
	_anim = AnimationPlayer.new()
	_anim.name = "AnimationPlayer"
	_model.add_child(_anim)
	_anim.add_animation_library("", load(CLIP_LIBRARY))
	_build_tree()
	if skel == null:
		return
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.name.begins_with("KeeperBody"):
			m.name = "Body"
			m.material_override = _skin_material()
		elif m.name.begins_with("KeeperRags"):
			m.name = "Rags"
			m.set_surface_override_material(0, _rag_material())
			if m.mesh.get_surface_count() > 1:
				m.set_surface_override_material(1, _strip_material())
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	poser = KeeperPoser.new()
	poser.name = "Poser"
	poser.clip_mode = true
	skel.add_child(poser)
	# the helmet it came down in, fused to the skull: cracked shell, dead lamp
	var ba := BoneAttachment3D.new()
	ba.bone_name = "Head"
	skel.add_child(ba)
	var hm := Node3D.new()
	hm.name = "FusedHelmet"
	hm.position = Vector3(0.0, 0.135, -0.04)
	hm.rotation = Vector3(-0.55, 0.0, 0.18)
	ba.add_child(hm)
	var helmet_v11: Mesh = GfxAssets.mesh("res://assets/characters/keeper/KeeperHelmet.glb")
	if helmet_v11:
		# v1.1: the Blender helmet (tools/gfx_blender/keeper_helmet.py): cracked shell, dents,
		# chipped paint, a dead lamp; normal/AO/colour baked from a sculpted high mesh
		var hmi := MeshInstance3D.new()
		hmi.name = "HelmetV11"
		hmi.mesh = helmet_v11
		hmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hm.add_child(hmi)
	else:
		_primitive_helmet(hm)
	# where it grew into the skin: ridges of flesh swallowing the brim
	var collar := TorusMesh.new()
	collar.inner_radius = 0.07
	collar.outer_radius = 0.104
	collar.rings = 24
	collar.ring_segments = 10
	_part(hm, collar, _skin_material(), Vector3(0, -0.006, 0), Vector3(0.95, 0.55, 1.15))
	# pale glints under the brim: the fair warning. No face to go with them.
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(0.7, 0.8, 0.85)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(0.75, 0.88, 1.0)
	_eye_mat.emission_energy_multiplier = 1.6
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for sx in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.0055
		sm.height = 0.008
		e.mesh = sm
		e.material_override = _eye_mat
		e.position = Vector3(0.027 * sx, 0.105, 0.062)
		ba.add_child(e)
		_eyes.append(e)


func _primitive_helmet(hm: Node3D) -> void:
	var shell_m := StandardMaterial3D.new()
	shell_m.albedo_color = Color(0.3, 0.25, 0.16)
	shell_m.roughness = 0.75
	shell_m.roughness_texture = _noise_tex(0.12, false)
	shell_m.normal_enabled = true
	shell_m.normal_texture = _noise_tex(0.05, true)
	shell_m.normal_scale = 0.25
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.04, 0.035, 0.03)
	dark.roughness = 0.6
	var shell := SphereMesh.new()
	shell.radius = 0.094
	shell.height = 0.17
	shell.is_hemisphere = true
	shell.radial_segments = 28
	shell.rings = 10
	_part(hm, shell, shell_m, Vector3.ZERO, Vector3(0.95, 1.0, 1.15))
	var brim := CylinderMesh.new()
	brim.top_radius = 0.099
	brim.bottom_radius = 0.101
	brim.height = 0.014
	brim.radial_segments = 28
	_part(hm, brim, dark, Vector3(0, 0.002, 0), Vector3(0.95, 1.0, 1.15))
	var ridge := BoxMesh.new()
	ridge.size = Vector3(0.02, 0.016, 0.2)
	_part(hm, ridge, shell_m, Vector3(0, 0.083, 0), Vector3.ONE)
	var lamp := CylinderMesh.new()
	lamp.top_radius = 0.02
	lamp.bottom_radius = 0.022
	lamp.height = 0.035
	var lamp_mi := _part(hm, lamp, dark, Vector3(0.0, 0.045, 0.1), Vector3.ONE)
	lamp_mi.rotation.x = PI / 2 - 0.35
	var crack := BoxMesh.new()
	crack.size = Vector3(0.01, 0.004, 0.13)
	var crack_mi := _part(hm, crack, dark, Vector3(0.04, 0.088, 0.0), Vector3.ONE)
	crack_mi.rotation = Vector3(0.0, 0.5, -0.45)


# ------------------------------------------------------------------ animation (v1.1)
const CLIP_LIBRARY := "res://assets/characters/keeper/keeper_anims.res"
## every clip the AI can ask for (all made in Blender, see tools/keeper_anim/build_clips.py)
const CLIPS := ["kp_idle", "kp_idle_head", "kp_idle_fingers", "kp_stalk", "kp_run", "kp_crawl", "kp_scream",
	"kp_lunge", "kp_stagger", "kp_grab", "kp_vent_drop", "kp_search", "kp_recoil"]
## ground speed (m/s) each locomotion clip was keyed at: playback is scaled by velocity / this,
## so the planted feet move with the floor instead of skating
const NATIVE_SPEED := {"kp_stalk": 1.25, "kp_run": 3.4, "kp_crawl": 1.2}
## cross-fade into a clip (s); everything else uses XFADE
const XFADE := 0.22
const XFADE_IN := {"kp_scream": 0.06, "kp_lunge": 0.04, "kp_stagger": 0.1, "kp_recoil": 0.06,
	"kp_vent_drop": 0.0, "kp_grab": 0.08, "kp_idle_head": 0.12, "kp_idle_fingers": 0.2}
## upper body for the strike one-shot (claws while it scuttles off)
const STRIKE_BONES := ["Spine", "Chest", "UpperChest", "Neck", "Head", "LeftShoulder", "LeftUpperArm",
	"LeftLowerArm", "LeftHand", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]
var tree: AnimationTree
var clip := ""                     ## the clip the tree is on (or fading to)
var _clip_t := 0.0                 ## seconds since that clip was requested
var _hold := ""                    ## a one-shot that plays out before the state picks again
var _hold_until := 0.0
var _idle_var_t := 3.0


func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()
	var tr := AnimationNodeTransition.new()
	tr.xfade_time = XFADE
	tr.allow_transition_to_self = false
	for i in CLIPS.size():
		tr.add_input(CLIPS[i])
		var an := AnimationNodeAnimation.new()
		an.animation = StringName(CLIPS[i])
		bt.add_node(StringName(CLIPS[i]), an, Vector2(0, i * 80))
	bt.add_node(&"state", tr, Vector2(300, 400))
	for i in CLIPS.size():
		tr.set_input_reset(i, true)
		bt.connect_node(&"state", i, StringName(CLIPS[i]))
	var ts := AnimationNodeTimeScale.new()
	bt.add_node(&"speed", ts, Vector2(500, 400))
	bt.connect_node(&"speed", 0, &"state")
	var os := AnimationNodeOneShot.new()
	os.fadein_time = 0.06
	os.fadeout_time = 0.25
	os.filter_enabled = true
	for b in STRIKE_BONES:
		os.set_filter_path(NodePath("%GeneralSkeleton:" + b), true)
	for s in ["Left", "Right"]:
		for f in ["Index", "Middle", "Ring", "Little"]:
			for seg in ["Proximal", "Intermediate", "Distal"]:
				os.set_filter_path(NodePath("%GeneralSkeleton:" + s + f + seg), true)
	bt.add_node(&"strike", os, Vector2(700, 400))
	var sa := AnimationNodeAnimation.new()
	sa.animation = &"kp_grab"
	bt.add_node(&"strike_clip", sa, Vector2(500, 600))
	bt.connect_node(&"strike", 0, &"speed")
	bt.connect_node(&"strike", 1, &"strike_clip")
	bt.connect_node(&"output", 0, &"strike")
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = bt
	_model.add_child(tree)
	tree.anim_player = tree.get_path_to(_anim)
	tree.root_node = tree.get_path_to(_model)
	tree.active = true
	play_clip("kp_search")


## Ask the tree for a clip (cross-faded). Returns true if it changed.
func play_clip(c: String, xfade := -1.0) -> bool:
	if tree == null or c == clip:
		return false
	var tr := (tree.tree_root as AnimationNodeBlendTree).get_node(&"state") as AnimationNodeTransition
	tr.xfade_time = xfade if xfade >= 0.0 else float(XFADE_IN.get(c, XFADE))
	tree.set("parameters/state/transition_request", c)
	clip = c
	_clip_t = 0.0
	return true


## Play a one-shot clip to its end (vent drop, strike...) before the state machine picks again.
func hold_clip(c: String, seconds: float, xfade := -1.0) -> void:
	play_clip(c, xfade)
	_hold = c
	_hold_until = _time + seconds


## The strike: an upper-body grab/rake layered over whatever the legs are doing.
func strike_anim() -> void:
	if tree:
		tree.set("parameters/strike/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Freeze on one frame of a clip (look-dev renders, tests): the tree steps aside.
func pose_clip(c: String, t: float) -> void:
	if tree:
		tree.active = false
	_anim.play(c)
	_anim.seek(t, true)
	_anim.pause()
	clip = c


func clip_speed() -> float:
	return float(tree.get("parameters/speed/scale")) if tree else 1.0


## Which clip the AI state wants right now, and at what playback speed.
func _pick_clip(v: float) -> Array:
	var c := "kp_idle"
	var sp := 1.0
	match state:
		S.DORMANT:
			c = "kp_search"
			sp = 0.35
		S.PATROL:
			c = "kp_stalk" if v > 0.3 else "kp_idle"
		S.INVESTIGATE:
			c = "kp_stalk" if v > 0.3 else "kp_search"
		S.SEARCH:
			c = "kp_crawl" if v > 0.3 else "kp_search"
		S.CHASE:
			if _windup > 0.0:
				c = "kp_scream"
			elif v > 1.0:
				c = "kp_run"
			elif v > 0.3:
				c = "kp_stalk"
			else:
				c = "kp_idle"
		S.LUNGE:
			c = {"telegraph": "kp_scream", "lunge": "kp_lunge", "recover": "kp_stagger"}.get(lunge_phase(), "kp_idle")
		S.REPELLED:
			c = "kp_recoil"
		S.RETREAT:
			c = "kp_crawl" if v > 0.3 else "kp_idle"
		S.WAIT_LIGHT:
			c = "kp_idle"
		S.GRAB:
			c = "kp_grab"
	if NATIVE_SPEED.has(c) and v > 0.3:
		sp = clampf(v / float(NATIVE_SPEED[c]), 0.4, 2.7)
	return [c, sp]


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
		var d := "res://assets/characters/keeper/"
		_skin_mat = StandardMaterial3D.new()
		var v11 := GfxAssets.enabled() and ResourceLoader.exists(d + "T_Keeper_Normal_v11.png")
		_skin_mat.albedo_texture = load(d + ("T_Keeper_BaseColor_v11.png" if v11 else "T_Keeper_BaseColor.png"))
		_skin_mat.albedo_color = Color(1.0, 1.0, 1.0)
		_skin_mat.normal_enabled = true
		_skin_mat.normal_texture = load(d + ("T_Keeper_Normal_v11.png" if v11 else "T_Keeper_Normal.png"))
		_skin_mat.normal_scale = 1.15
		if v11:
			# v1.1: sculpted in Blender (tools/gfx_blender/keeper_sculpt_bake.py): baked AO
			_skin_mat.ao_enabled = true
			_skin_mat.ao_texture = load(d + "T_Keeper_ORM_v11.png")
			_skin_mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			_skin_mat.ao_light_affect = 0.5
		_skin_mat.roughness_texture = load(d + "T_Keeper_Roughness.png")
		_skin_mat.roughness = 1.0
		_skin_mat.metallic_specular = 0.32
		# wet: a thin glossy film over matte, damp skin
		_skin_mat.clearcoat_enabled = false
		_skin_mat.clearcoat = 0.18
		_skin_mat.clearcoat_roughness = 0.5
		# a little light bleeds through the thin parts (Forward+ only; ignored elsewhere)
		_skin_mat.subsurf_scatter_enabled = true
		_skin_mat.subsurf_scatter_strength = 0.18
		_skin_mat.subsurf_scatter_skin_mode = true
		_skin_mat.rim_enabled = true
		_skin_mat.rim = 0.22
		_skin_mat.rim_tint = 0.4
		_skin_mat.emission_enabled = true
		_skin_mat.emission = Color(0.02, 0.03, 0.035)
		_skin_mat.emission_energy_multiplier = 0.25
	return _skin_mat


static func _rag_material() -> StandardMaterial3D:
	if _rag_mat == null:
		var d := "res://assets/characters/keeper/"
		_rag_mat = StandardMaterial3D.new()
		_rag_mat.albedo_texture = load(d + "T_KeeperRag_BaseColor.png")
		_rag_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_rag_mat.alpha_scissor_threshold = 0.5
		_rag_mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF
		_rag_mat.normal_enabled = true
		_rag_mat.normal_texture = load(d + "T_KeeperRag_Normal.png")
		_rag_mat.roughness = 0.88
		_rag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_rag_mat.rim_enabled = true
		_rag_mat.rim = 0.2
		_rag_mat.rim_tint = 0.6
	return _rag_mat


static var _strip_mat: StandardMaterial3D
static func _strip_material() -> StandardMaterial3D:
	if _strip_mat == null:
		_strip_mat = _rag_material().duplicate()
		_strip_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	return _strip_mat


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
		player.threat_near = s in [S.CHASE, S.WAIT_LIGHT, S.GRAB, S.LUNGE]
	match s:
		S.CHASE:
			lost_t = 0.0
			if prev in [S.PATROL, S.INVESTIGATE, S.SEARCH, S.DORMANT]:
				_windup = CHASE_WINDUP
				_chase_ramp_t = 0.0
			if prev not in [S.WAIT_LIGHT, S.LUNGE]:
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
	hold_clip("kp_crawl", 0.8 / vent_speed)
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
		# v1.1: the drop is the Blender clip kp_vent_drop (it pours out head first, lands on its
		# hands, freezes low and unfolds); its origin stays on the floor under the vent
		global_position = VENT_EXIT
		visible = true
		_model.rotation.x = 0.0
		hold_clip("kp_vent_drop", 1.2 / vent_speed, 0.0)
		ok = await _vent_phase(0.6, func(_x: float):
			global_position = VENT_EXIT)
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
		S.LUNGE:
			_lunge(delta)
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
			# Phase 6: it tears the door open and drags you out. At full health that is
			# a strike you survive (the same rule as any first catch), not instant death.
			seen_hiding.call("force_out", player)
			seen_hiding = null
			_catch(false)
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
	if d < LUNGE_RANGE and can_see_player():
		_start_lunge()


func _start_lunge() -> void:
	set_state(S.LUNGE)
	_lunge_hit = false
	look_at_flat(player.global_position)
	_play_voice("keeper_scream", 3.0)
	if player:
		player.rumble(0.25, 0.4)


## The telegraph, the lunge, the stagger. Returns to the chase after a miss.
func _lunge(delta: float) -> void:
	if state_t < LUNGE_TELEGRAPH:
		if player:
			var to := player.global_position - global_position
			to.y = 0
			# it turns to follow you while it rears back, but only so fast
			look_at_flat(player.global_position, delta * 5.0)
			_lunge_dir = (-global_transform.basis.z).normalized()
		return
	if state_t < LUNGE_TELEGRAPH + LUNGE_TIME:
		if not _lunge_hit and player and not player.dead and player.hidden_in == null:
			if global_position.distance_to(player.global_position) < LUNGE_HIT:
				_lunge_hit = true
				_catch(false)
		return
	if state_t > LUNGE_TELEGRAPH + LUNGE_TIME + LUNGE_RECOVER:
		set_state(S.CHASE)


func lunge_phase() -> String:
	if state != S.LUNGE:
		return ""
	if state_t < LUNGE_TELEGRAPH:
		return "telegraph"
	if state_t < LUNGE_TELEGRAPH + LUNGE_TIME:
		return "lunge"
	return "recover"


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
		strike_anim()
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
		# rearing up to lunge, it is wide open: light in its face then makes it flinch
		# three times as fast (the "parry": turn and flash it when it screams)
		beam_t += delta * (3.0 if state == S.LUNGE and lunge_phase() == "telegraph" else 1.0)
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
	if state == S.CHASE and _chase_ramp_t < CHASE_RAMP:
		_chase_ramp_t += delta
		spd = lerpf(CHASE_START_SPEED, SPEED[S.CHASE], clampf(_chase_ramp_t / CHASE_RAMP, 0.0, 1.0)) * speed_scale
	if state == S.LUNGE:
		var lv := Vector3.ZERO
		if lunge_phase() == "lunge":
			lv = _lunge_dir * LUNGE_SPEED
		velocity.x = lv.x
		velocity.z = lv.z
		velocity.y = -0.3 if is_on_floor() else velocity.y - _gravity * delta
		move_and_slide()
		return
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
	var dt := get_physics_process_delta_time()
	_clip_t += dt
	var d := player.global_position.distance_to(global_position) if player and is_instance_valid(player) else 99.0
	var pick := _pick_clip(v)
	var c: String = pick[0]
	var sp: float = pick[1]
	if _hold != "":
		# a one-shot (vent drop) plays out unless the AI has something urgent to show
		if _time < _hold_until and state not in [S.CHASE, S.LUNGE, S.REPELLED, S.GRAB]:
			c = _hold
			sp = vent_speed if _hold == "kp_vent_drop" else 1.0
		else:
			_hold = ""
	elif c == "kp_idle" and state in [S.PATROL, S.WAIT_LIGHT, S.CHASE, S.RETREAT]:
		# idle twitch variants: a head snap or a finger ripple every few seconds
		_idle_var_t -= dt * (2.0 if state == S.WAIT_LIGHT else 1.0)
		if clip in ["kp_idle_head", "kp_idle_fingers"] and _clip_t < 2.25:
			c = clip
		elif clip == "kp_idle" and _idle_var_t <= 0.0:
			_idle_var_t = _rng.randf_range(2.5, 6.0)
			c = "kp_idle_head" if _rng.randf() < 0.6 else "kp_idle_fingers"
	play_clip(c)
	if tree:
		var cur := float(tree.get("parameters/speed/scale"))
		tree.set("parameters/speed/scale", sp if absf(sp - cur) > 0.5 else move_toward(cur, sp, dt * 4.0))
	if poser:
		# the procedural layer only aims the head at you, on top of the clips
		var look := 0.0
		if player and is_instance_valid(player) and not in_vent and _hold == "":
			match state:
				S.CHASE, S.WAIT_LIGHT:
					look = 0.8 if d < 14.0 else 0.0
				S.LUNGE:
					look = 0.6 if lunge_phase() == "telegraph" else 0.0
				S.PATROL, S.INVESTIGATE:
					look = 0.45 if awareness > 0.3 and d < 10.0 else 0.0
				S.GRAB:
					look = 0.5
			poser.look_target = player.global_position + Vector3.UP * (0.6 if player.crouching else 1.4)
		poser.look_weight = move_toward(poser.look_weight, look, dt * 2.5)
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
