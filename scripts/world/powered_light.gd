class_name PoweredLight
extends Node3D
## Turns its Light3D children and emissive meshes on when `circuit` is powered.
## Empty circuit = always on. Optional flicker for atmosphere.

@export var circuit := ""
@export var flicker := 0.0      ## 0..1 chance-ish of dips per second
@export var power_on_delay := 0.0

var _lights: Array[Light3D] = []
var _energies: Array[float] = []
var _emissive: Array[StandardMaterial3D] = []
var _emissive_energy: Array[float] = []
var _on := false
var _flick_t := 0.0
var _rng := RandomNumberGenerator.new()
var _suppress_t := 0.0      ## >0: the Keeper is smothering this light
var _warn_t := 0.0          ## >0: stuttering before it goes out
var suppress_cooldown := 0.0
var pool_radius := 0.0      ## floor radius this light keeps the Keeper out of (0 = none)


func _ready() -> void:
	_rng.randomize()
	GfxUpgrade.fixture(self)   # v1.1 Blender batten fixture over the primitive one
	for n in find_children("*", "Light3D", true, false):
		_lights.append(n)
		_energies.append(n.light_energy)
	for n in find_children("*", "MeshInstance3D", true, false):
		var m := (n as MeshInstance3D).material_override as StandardMaterial3D
		if m and m.emission_enabled:
			m = m.duplicate()
			n.material_override = m
			_emissive.append(m)
			_emissive_energy.append(m.emission_energy_multiplier)
	add_to_group("powered_lights")
	for l in _lights:
		var r := 0.0
		if l is OmniLight3D:
			r = (l as OmniLight3D).omni_range
		elif l is SpotLight3D:
			r = (l as SpotLight3D).spot_range
		# only white working light counts; red emergency lamps don't keep it back
		if circuit != "" and l.light_energy >= 1.0 and l.light_color.g > 0.5:
			pool_radius = maxf(pool_radius, r * 0.5)
	if circuit != "":
		GameState.grid.circuit_changed.connect(_on_circuit)
	_set_on(circuit == "" or GameState.grid.is_powered(circuit), false)


func _on_circuit(id: String, powered: bool) -> void:
	if id == circuit:
		_set_on(powered, true)


func _set_on(on: bool, animate: bool) -> void:
	_on = on
	if on and animate and power_on_delay > 0.0:
		_apply(0.0)
		await get_tree().create_timer(power_on_delay).timeout
		# stutter on, like old tubes
		for i in 3:
			_apply(1.0)
			await get_tree().create_timer(0.06).timeout
			_apply(0.0)
			await get_tree().create_timer(0.09).timeout
	_apply(1.0 if _on else 0.0)


func _apply(k: float) -> void:
	for i in _lights.size():
		_lights[i].light_energy = _energies[i] * k
		_lights[i].visible = k > 0.001
	for i in _emissive.size():
		_emissive[i].emission_energy_multiplier = _emissive_energy[i] * k


func is_on() -> bool:
	return _on


## True when this light is lit right now and keeps the Keeper out of `pos`.
func covers(pos: Vector3) -> bool:
	if pool_radius <= 0.0 or not _on or (_suppress_t > 0.0 and _warn_t <= 0.0):
		return false
	var lp := global_position
	if absf(pos.y - lp.y) > 5.0:
		return false
	return Vector2(pos.x - lp.x, pos.z - lp.z).length() <= pool_radius


## The Keeper smothers the light: it stutters for `warn` seconds, then goes dark.
func suppress(seconds: float, warn := 1.2) -> bool:
	if suppress_cooldown > 0.0 or not _on:
		return false
	if browning and _brown_tw:   # the real cue always wins over a fake-out
		_brown_tw.kill()
		browning = false
	_warn_t = warn
	_suppress_t = seconds + warn
	suppress_cooldown = seconds + warn + 12.0
	return true


## v1.2 fake-out: a brownout. One lamp sags, buzzes and comes back over ~1.5 s, slower
## than the fast stutter the Keeper causes. Visual only: covers() is unchanged.
var browning := false
var _brown_tw: Tween
func brownout() -> bool:
	if not _on or _suppress_t > 0.0 or browning:
		return false
	browning = true
	var tw := create_tween()
	_brown_tw = tw
	tw.tween_method(_apply, 1.0, 0.3, 0.35)
	tw.tween_method(_apply, 0.3, 0.45, 0.12)
	tw.tween_method(_apply, 0.45, 0.15, 0.3)
	tw.tween_interval(0.25)
	tw.tween_method(_apply, 0.15, 1.0, 0.5)
	tw.tween_callback(func():
		browning = false
		_apply(1.0 if _on and _suppress_t <= 0.0 else (0.0 if not _on else 1.0)))
	return true


func is_suppressed() -> bool:
	return _suppress_t > 0.0


static func pool_at(tree: SceneTree, pos: Vector3) -> PoweredLight:
	for l in tree.get_nodes_in_group("powered_lights"):
		if (l as PoweredLight).covers(pos):
			return l
	return null


func _process(delta: float) -> void:
	if suppress_cooldown > 0.0:
		suppress_cooldown -= delta
	if _suppress_t > 0.0:
		_suppress_t -= delta
		if _warn_t > 0.0:
			_warn_t -= delta
			_apply(1.0 if _rng.randf() > 0.5 else _rng.randf_range(0.0, 0.3))
		else:
			_apply(0.0)
		if _suppress_t <= 0.0:
			_apply(1.0 if _on else 0.0)
		return
	if not _on or flicker <= 0.0 or browning:
		return
	_flick_t -= delta
	if _flick_t <= 0.0:
		_flick_t = _rng.randf_range(0.05, 1.0 / maxf(flicker, 0.01))
		var k := 1.0 if _rng.randf() > 0.35 else _rng.randf_range(0.1, 0.6)
		_apply(k)
