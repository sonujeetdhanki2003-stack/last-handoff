class_name PlayerAnimator
extends AnimationTree
## Builds the player's blend tree in code (so it is easy to read and diff):
##
##   loco (BlendSpace1D: Idle 0 / Walk 1.9 / Jog 4.4 / Sprint 6.5)  -> TimeScale
##   crouch (BlendSpace1D: Crouch_Idle 0 / Crouch_Fwd 1.15)
##   stance = Blend2(loco, crouch)
##   torch  = Blend2(stance, Idle_Torch) filtered to the torch arm
##   action = OneShot(torch, Interact | PickUp_Table | Fixing_Kneeling)
##
## Animation clips come from Quaternius' Universal Animation Library (CC0).

const TORCH_ARM_BONES := ["RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"RightThumbMetacarpal", "RightThumbProximal", "RightThumbDistal",
	"RightIndexProximal", "RightIndexIntermediate", "RightIndexDistal",
	"RightMiddleProximal", "RightMiddleIntermediate", "RightMiddleDistal",
	"RightRingProximal", "RightRingIntermediate", "RightRingDistal",
	"RightLittleProximal", "RightLittleIntermediate", "RightLittleDistal"]
## Both the character and the clips are retargeted to Godot's SkeletonProfileHumanoid
## on import, so tracks address the unique skeleton by profile bone names.
const SKELETON_PATH := "%GeneralSkeleton"  # relative to root_node (the Model)

const ACTIONS := {"interact": "Interact", "pickup": "PickUp_Table", "fix": "Fixing_Kneeling"}

var _speed := 0.0
var _crouch := 0.0
var _torch := 0.0
var _torch_target := 0.0
var current_action := ""


func _ready() -> void:
	_build_tree()
	active = true


func _anim(name_: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = StringName(name_)
	return a


func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()

	var loco := AnimationNodeBlendSpace1D.new()
	loco.add_blend_point(_anim("Idle"), 0.0, -1, &"idle")
	loco.add_blend_point(_anim("Walk"), 1.9, -1, &"walk")
	loco.add_blend_point(_anim("Jog_Fwd"), 4.4, -1, &"jog")
	loco.add_blend_point(_anim("Sprint"), 6.5, -1, &"sprint")
	loco.min_space = 0.0
	loco.max_space = 7.0
	bt.add_node("loco", loco, Vector2(0, 0))
	bt.add_node("loco_speed", AnimationNodeTimeScale.new(), Vector2(200, 0))
	bt.connect_node("loco_speed", 0, "loco")

	var crouch := AnimationNodeBlendSpace1D.new()
	crouch.add_blend_point(_anim("Crouch_Idle"), 0.0, -1, &"crouch_idle")
	crouch.add_blend_point(_anim("Crouch_Fwd"), 1.15, -1, &"crouch_fwd")
	crouch.min_space = 0.0
	crouch.max_space = 2.0
	bt.add_node("crouch", crouch, Vector2(0, 200))

	bt.add_node("stance", AnimationNodeBlend2.new(), Vector2(400, 100))
	bt.connect_node("stance", 0, "loco_speed")
	bt.connect_node("stance", 1, "crouch")

	bt.add_node("torch_anim", _anim("Idle_Torch"), Vector2(400, 300))
	var torch := AnimationNodeBlend2.new()
	torch.filter_enabled = true
	for b in TORCH_ARM_BONES:
		torch.set_filter_path(NodePath("%s:%s" % [SKELETON_PATH, b]), true)
	bt.add_node("torch", torch, Vector2(600, 100))
	bt.connect_node("torch", 0, "stance")
	bt.connect_node("torch", 1, "torch_anim")

	var actions := AnimationNodeTransition.new()
	for k in ACTIONS:
		actions.add_input(k)
	actions.xfade_time = 0.0
	bt.add_node("action_pick", actions, Vector2(600, 300))
	var i := 0
	for k in ACTIONS:
		bt.add_node("act_" + k, _anim(ACTIONS[k]), Vector2(400, 450 + i * 80))
		bt.connect_node("action_pick", i, "act_" + k)
		i += 1

	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.15
	shot.fadeout_time = 0.25
	bt.add_node("action", shot, Vector2(800, 100))
	bt.connect_node("action", 0, "torch")
	bt.connect_node("action", 1, "action_pick")

	bt.connect_node("output", 0, "action")
	tree_root = bt


func update_locomotion(speed: float, crouching: bool, _running: bool) -> void:
	var dt := get_physics_process_delta_time()
	_speed = lerpf(_speed, speed, clampf(dt * 10.0, 0.0, 1.0))
	_crouch = move_toward(_crouch, 1.0 if crouching else 0.0, dt * 5.0)
	_torch = move_toward(_torch, _torch_target, dt * 4.0)
	set("parameters/loco/blend_position", _speed)
	set("parameters/crouch/blend_position", _speed if crouching else 0.0)
	set("parameters/stance/blend_amount", _crouch)
	set("parameters/torch/blend_amount", _torch * (1.0 - _crouch * 0.5))
	# Slightly speed clips up/down so feet match ground speed between blend points.
	var ts := 1.0
	if _speed > 0.3:
		var pts := [1.9, 4.4, 6.5]
		var nearest: float = pts[0]
		for p in pts:
			if absf(p - _speed) < absf(nearest - _speed):
				nearest = p
		ts = clampf(_speed / nearest, 0.75, 1.25)
	set("parameters/loco_speed/scale", ts)


func set_torch(on: bool) -> void:
	_torch_target = 1.0 if on else 0.0


func play_action(kind: String) -> void:
	if not ACTIONS.has(kind):
		return
	current_action = kind
	set("parameters/action_pick/transition_request", kind)
	set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func stop_action() -> void:
	current_action = ""
	set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func is_action_playing() -> bool:
	return bool(get("parameters/action/active"))
