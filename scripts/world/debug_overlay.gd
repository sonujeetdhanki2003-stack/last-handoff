class_name DebugOverlay
extends Node
## F3 tuning overlay (off by default): the Keeper's state, awareness, speed and
## senses as text, every noise as a ring on the floor at its hearing radius, the
## Keeper's path target, and its sight range around it.

var game: Node
var on := false
var _layer: CanvasLayer
var _label: Label
var _root3d: Node3D
var _rings: Array = []    ## [MeshInstance3D, life]
var _sight: MeshInstance3D
var _target: MeshInstance3D
var _mat_ring: StandardMaterial3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 50
	add_child(_layer)
	var p := UIKit.panel(Color(0, 0, 0, 0.7), 12)
	p.position = Vector2(1180, 330)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(p)
	_label = UIKit.label("", 17, UIKit.GREEN, "mono")
	p.add_child(_label)
	_layer.visible = false
	_root3d = Node3D.new()
	_root3d.name = "DebugGizmos"
	_root3d.visible = false
	add_child(_root3d)
	_mat_ring = StandardMaterial3D.new()
	_mat_ring.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_ring.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_ring.no_depth_test = true
	_mat_ring.albedo_color = Color(0.3, 1.0, 0.5, 0.8)
	_sight = _ring_mesh(Color(1.0, 0.3, 0.2, 0.7))
	_target = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	_target.mesh = sm
	var tm := _mat_ring.duplicate() as StandardMaterial3D
	tm.albedo_color = Color(1, 0.8, 0.2, 0.9)
	_target.material_override = tm
	_root3d.add_child(_target)
	Events.noise.connect(_on_noise)


func _ring_mesh(c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.97
	t.outer_radius = 1.0
	t.rings = 48
	t.ring_segments = 4
	mi.mesh = t
	var m := _mat_ring.duplicate() as StandardMaterial3D
	m.albedo_color = c
	mi.material_override = m
	_root3d.add_child(mi)
	return mi


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("debug_overlay"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	set_on(not on)


func set_on(v: bool) -> void:
	on = v
	_layer.visible = v
	_root3d.visible = v


func _on_noise(pos: Vector3, radius: float, source: String) -> void:
	if not on or radius <= 0.05:
		return
	var mi := _ring_mesh(Color(0.3, 1.0, 0.5, 0.85) if source in ["step", "run", "click"] else Color(0.4, 0.7, 1.0, 0.85))
	mi.global_position = pos + Vector3.UP * 0.05
	mi.scale = Vector3(radius, 1.0, radius)
	_rings.append([mi, 1.2])


func _process(delta: float) -> void:
	for i in range(_rings.size() - 1, -1, -1):
		_rings[i][1] -= delta
		var mi: MeshInstance3D = _rings[i][0]
		if _rings[i][1] <= 0.0:
			mi.queue_free()
			_rings.remove_at(i)
		else:
			(mi.material_override as StandardMaterial3D).albedo_color.a = _rings[i][1] / 1.2 * 0.85
	if not on or game == null:
		return
	var k: Keeper = game.get("keeper")
	var p: Player = game.get("player")
	var lines := ["DEBUG  [F3]", "fps %d" % Engine.get_frames_per_second()]
	if p:
		lines.append("player  %s%s  stamina %.2f  hp %d" % ["crouch " if p.crouching else "", "RUN " if p.running else "", p.vitals.stamina, int(p.vitals.health)])
		lines.append("light %s  %d%%   area %s" % ["on" if p.flashlight.on else "off", p.flashlight.battery.percent(), Zones.area_at(p.global_position)])
	if k and is_instance_valid(k):
		var d := k.global_position.distance_to(p.global_position) if p else 0.0
		lines.append("")
		lines.append("KEEPER  %s   t %.1f" % [k.state_name().to_upper(), k.state_t])
		lines.append("dist %.1f m   speed %.2f   x%.2f" % [d, Vector2(k.velocity.x, k.velocity.z).length(), k.speed_scale])
		lines.append("aware %.2f   sight %.1f m   sees %s" % [k.awareness, k.sight_range(), "YES" if k.can_see_player() else "no"])
		lines.append("beam %.2f   lost %.1f   repel cd %.1f" % [k.beam_t, k.lost_t, k.repel_cooldown])
		_sight.visible = true
		_sight.global_position = k.global_position + Vector3.UP * 0.06
		var r := k.sight_range()
		_sight.scale = Vector3(r, 1, r)
		_target.visible = not k.agent.is_navigation_finished()
		_target.global_position = k.agent.target_position + Vector3.UP * 0.3
	else:
		lines.append("KEEPER  -")
		_sight.visible = false
		_target.visible = false
	_label.text = "\n".join(lines)
