class_name Level
extends Node3D
## A playable map. Holds a PlayerSpawn marker; nodes register themselves by group.

func get_spawn() -> Transform3D:
	var m := get_node_or_null("PlayerSpawn") as Marker3D
	return m.global_transform if m else Transform3D.IDENTITY


func find_interactable(n: String) -> Node:
	return find_child(n, true, false)


func _ready() -> void:
	_static_shadows(self, false)
	# Phase 6: occlusion culling + per-preset draw distances / shadow budget
	if not Harness.has("noocc"):
		Quality.build_occluders(self)
	GfxUpgrade.level(self)   # v1.1: Blender props + baked AO (after the occluders read the boxes)
	GfxV12.level(self)       # v1.2: Blender lift car, shaft steelwork, call box, winch
	apply_quality()
	if not Engine.is_editor_hint():
		Settings.changed.connect(_on_setting)


func _on_setting(section: String, key: String, _v: Variant) -> void:
	if section == "video" and key == "quality":
		apply_quality()


func apply_quality() -> void:
	Quality.apply_level(self, int(Settings.get_value("video", "quality")))


## Anything that moves every frame (fans, flywheels, swaying cables, beacons,
## particles) does not cast shadows: a moving caster forces every omni shadow
## cube around it to re-render each frame. The still world keeps cached shadows.
func _static_shadows(n: Node, moving: bool) -> void:
	var m := moving or n is Spinner or n is Sway or n is GPUParticles3D or n is CPUParticles3D
	if m and n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_static_shadows(c, m)
