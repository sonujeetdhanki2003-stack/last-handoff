class_name Flashlight
extends Node3D
## Third-person flashlight. Mounted near the shoulder, aims where the camera aims.
## Battery drains while on; flickers and dims when low; dies at 0.

signal toggled(on: bool)
signal battery_changed(charge: float)
signal battery_dead

@export var max_energy := 9.0
@export var spot_range := 22.0

@onready var light: SpotLight3D = $SpotLight3D

var battery := BatteryModel.new()
var on := false
var _flicker := 1.0
var _flick_t := 0.0
var _rng := RandomNumberGenerator.new()
var _click: AudioStreamPlayer


func _ready() -> void:
	top_level = true
	_rng.randomize()
	battery.charge = GameState.battery_charge
	battery.depleted.connect(_on_depleted)
	light.spot_range = spot_range
	_click = AudioStreamPlayer.new()
	_click.bus = &"SFX"
	var s := load("res://audio/sfx/flashlight_click.wav")
	if s:
		_click.stream = s
	add_child(_click)
	_apply()


func toggle() -> bool:
	set_on(not on)
	return on


func set_on(v: bool) -> void:
	if v and battery.is_empty():
		Events.interaction_feedback.emit("Battery dead. Press R to swap a cell")
		v = false
	if v == on:
		return
	on = v
	_click.stream = Sfx.stream("res://audio/sfx2/flash_on.ogg" if on else "res://audio/sfx2/flash_off.ogg")
	if _click.stream:
		_click.volume_db = -8.0
		_click.play()
	_apply()
	toggled.emit(on)


func replace_battery() -> bool:
	if battery.charge >= 0.999:
		Events.interaction_feedback.emit("Battery already full")
		return false
	if not GameState.inventory.remove("battery", 1):
		Events.interaction_feedback.emit("No spare battery cells")
		return false
	battery.replace()
	sync_to_state()
	Sfx.play("battery_swap")
	Events.toast.emit("Battery replaced")
	return true


func sync_to_state() -> void:
	GameState.battery_charge = battery.charge
	battery_changed.emit(battery.charge)
	_apply()


func _on_depleted() -> void:
	on = false
	_apply()
	toggled.emit(false)
	battery_dead.emit()
	Events.interaction_feedback.emit("Flashlight battery is dead")


func step(delta: float) -> void:
	## Separate from _process so tests can drive time deterministically.
	if on:
		battery.drain(delta)
		GameState.battery_charge = battery.charge
		battery_changed.emit(battery.charge)
	_update_flicker(delta)
	_apply()


func _process(delta: float) -> void:
	step(delta)


func _update_flicker(delta: float) -> void:
	if not on or battery.charge > 0.15:
		_flicker = 1.0
		return
	_flick_t -= delta
	if _flick_t <= 0.0:
		_flick_t = _rng.randf_range(0.04, 0.5)
		_flicker = 1.0 if _rng.randf() > 0.3 else _rng.randf_range(0.05, 0.5)


func _apply() -> void:
	if light == null:
		return
	light.visible = on
	# Dim gently below 25 % so low battery reads on screen, not just in the HUD.
	var dim := clampf(remap(battery.charge, 0.0, 0.25, 0.35, 1.0), 0.35, 1.0)
	light.light_energy = max_energy * dim * _flicker


## Called by the player each frame with the shoulder mount and the aim point.
func aim(mount: Vector3, target_point: Vector3) -> void:
	global_position = mount
	if mount.distance_to(target_point) > 0.05:
		var t := global_transform.looking_at(target_point, Vector3.UP)
		global_transform = global_transform.interpolate_with(t, 0.6)
