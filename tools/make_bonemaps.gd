extends Node
## One-off: writes the humanoid bone maps used to retarget the Universal Animation
## Library clips onto the Universal Base Character (both Quaternius, CC0).

func _side(m: Dictionary, prefix: String, s_ual: String, s_ubc: String, ual: bool) -> void:
	pass

func _ready() -> void:
	var ual := {"Root": "root", "Hips": "DEF-hips", "Spine": "DEF-spine.001", "Chest": "DEF-spine.002",
		"UpperChest": "DEF-spine.003", "Neck": "DEF-neck", "Head": "DEF-head"}
	var ubc := {"Root": "root", "Hips": "pelvis", "Spine": "spine_01", "Chest": "spine_02",
		"UpperChest": "spine_03", "Neck": "neck_01", "Head": "Head"}
	for side in [["Left", "L", "l"], ["Right", "R", "r"]]:
		var S: String = side[0]
		var a: String = side[1]
		var b: String = side[2]
		ual[S + "Shoulder"] = "DEF-shoulder." + a
		ual[S + "UpperArm"] = "DEF-upper_arm." + a
		ual[S + "LowerArm"] = "DEF-forearm." + a
		ual[S + "Hand"] = "DEF-hand." + a
		ual[S + "UpperLeg"] = "DEF-thigh." + a
		ual[S + "LowerLeg"] = "DEF-shin." + a
		ual[S + "Foot"] = "DEF-foot." + a
		ual[S + "Toes"] = "DEF-toe." + a
		ubc[S + "Shoulder"] = "clavicle_" + b
		ubc[S + "UpperArm"] = "upperarm_" + b
		ubc[S + "LowerArm"] = "lowerarm_" + b
		ubc[S + "Hand"] = "hand_" + b
		ubc[S + "UpperLeg"] = "thigh_" + b
		ubc[S + "LowerLeg"] = "calf_" + b
		ubc[S + "Foot"] = "foot_" + b
		ubc[S + "Toes"] = "ball_" + b
		var segs := ["Proximal", "Intermediate", "Distal"]
		var tsegs := ["Metacarpal", "Proximal", "Distal"]
		for i in 3:
			ual[S + "Thumb" + tsegs[i]] = "DEF-thumb.0%d.%s" % [i + 1, a]
			ubc[S + "Thumb" + tsegs[i]] = "thumb_0%d_%s" % [i + 1, b]
			for f in [["Index", "index"], ["Middle", "middle"], ["Ring", "ring"], ["Little", "pinky"]]:
				ual[S + f[0] + segs[i]] = "DEF-f_%s.0%d.%s" % [f[1], i + 1, a]
				ubc[S + f[0] + segs[i]] = "%s_0%d_%s" % [f[1], i + 1, b]
	for pair in [[ual, "res://assets/characters/bonemap_ual.tres"], [ubc, "res://assets/characters/bonemap_ubc.tres"]]:
		var bm := BoneMap.new()
		bm.profile = SkeletonProfileHumanoid.new()
		var m: Dictionary = pair[0]
		for k in m:
			bm.set_skeleton_bone_name(StringName(k), StringName(m[k]))
		ResourceSaver.save(bm, pair[1])
		print("saved ", pair[1], " ", m.size())
	get_tree().quit(0)
