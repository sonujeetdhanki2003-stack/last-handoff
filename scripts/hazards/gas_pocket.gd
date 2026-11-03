class_name GasPocket
extends Node3D
## A pocket of gas in the crawlspace. Readable: green haze, a hiss, a stencilled
## warning. Keep your flashlight OFF inside: switched on, the old bulb sparks and
## after a second the gas goes up (60 damage), then the pocket has to refill.

@export var size := Vector3(5.0, 2.4, 4.0)   ## box centred on this node
@export var fuse_time := 1.0
@export var damage := 60.0
@export var refill_time := 25.0

var light_t := 0.0
var burnt_t := 0.0
var warned := false
var _fog: FogVolume
var _hiss: AudioStreamPlayer3D
var _boom: AudioStreamPlayer3D
var _flash: OmniLight3D


var _haze: MeshInstance3D          ## fallback haze where volumetric fog is off (Low, Phone, GLES3)


func _ready() -> void:
	add_to_group("hazards")
	# FogVolume only renders with Forward+ volumetric fog; the OpenGL fallback can't even compile it
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_fog = FogVolume.new()
		_fog.size = size
		var fm := FogMaterial.new()
		fm.density = 0.35
		fm.albedo = Color(0.55, 0.7, 0.3)
		fm.emission = Color(0.03, 0.05, 0.01)
		fm.edge_fade = 0.4
		_fog.material = fm
		add_child(_fog)
	_haze = MeshInstance3D.new()
	_haze.name = "Haze"
	var bm := BoxMesh.new()
	bm.size = size
	_haze.mesh = bm
	var hm := StandardMaterial3D.new()
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	hm.albedo_color = Color(0.5, 0.68, 0.26, 0.22)
	hm.proximity_fade_enabled = true
	hm.proximity_fade_distance = 0.8
	hm.disable_receive_shadows = true
	_haze.material_override = hm
	_haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_haze)
	_update_haze.call_deferred()   # after WorldEnv has applied the preset
	Settings.changed.connect(func(s, _k, _v):
		if s == "video":
			_update_haze.call_deferred())
	_hiss = AudioStreamPlayer3D.new()
	_hiss.bus = &"Ambience"
	_hiss.unit_size = 3.0
	_hiss.stream = AudioLoop.make(load("res://audio/sfx/gas_hiss.wav"))
	add_child(_hiss)
	_hiss.play()
	_boom = AudioStreamPlayer3D.new()
	_boom.bus = &"SFX"
	_boom.unit_size = 10.0
	_boom.stream = load("res://audio/sfx/gas_ignite.wav")
	add_child(_boom)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.55, 0.15)
	_flash.omni_range = 8.0
	_flash.light_energy = 0.0
	add_child(_flash)


func contains(pos: Vector3) -> bool:
	var lp := global_transform.affine_inverse() * pos
	return absf(lp.x) <= size.x / 2.0 and absf(lp.z) <= size.z / 2.0 and absf(lp.y) <= size.y / 2.0 + 0.6


func is_charged() -> bool:
	return burnt_t <= 0.0


func _physics_process(delta: float) -> void:
	_flash.light_energy = move_toward(_flash.light_energy, 0.0, delta * 12.0)
	if burnt_t > 0.0:
		burnt_t -= delta
		_set_gas_visible(false)
		if burnt_t <= 0.0:
			_set_gas_visible(true)
		return
	if not GameState.threat_enabled:
		return
	for p in get_tree().get_nodes_in_group("player"):
		var pl := p as Player
		if pl == null or pl.dead:
			continue
		if contains(pl.global_position + Vector3.UP * 0.8):
			if not warned:
				warned = true
				Events.toast.emit("The air tastes of gas. Lights OFF in here.")
			if pl.flashlight.on:
				light_t += delta
				if light_t >= fuse_time:
					ignite(pl)
			else:
				light_t = 0.0
			if pl.running:
				Events.noise.emit(pl.global_position, 7.0, "cough")
		else:
			light_t = 0.0


func ignite(pl: Player) -> void:
	light_t = 0.0
	burnt_t = refill_time
	_fog.visible = false
	_boom.play()
	_flash.light_energy = 16.0
	Events.noise.emit(global_position, 20.0, "explosion")
	if pl and contains(pl.global_position + Vector3.UP * 0.8):
		pl.hurt(damage, "fire")
		var away := pl.global_position - global_position
		away.y = 0
		pl.velocity += away.normalized() * 6.0


func volumetric_active() -> bool:
	if _fog == null or not is_inside_tree():
		return false
	var env: Environment = get_viewport().get_world_3d().environment if get_viewport() and get_viewport().get_world_3d() else null
	return env != null and env.volumetric_fog_enabled and RenderingServer.get_current_rendering_method() == "forward_plus"


func _update_haze() -> void:
	_set_gas_visible(burnt_t <= 0.0)


## The green gas must read on every renderer and preset: volumetric fog where it runs,
## otherwise a translucent haze box.
func _set_gas_visible(v: bool) -> void:
	var vol := volumetric_active()
	if _fog:
		_fog.visible = v
	if _haze:
		_haze.visible = v and not vol
