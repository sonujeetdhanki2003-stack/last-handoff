class_name Vitals
extends RefCounted
## Stamina and health. Pure data, stepped by the player each physics frame.
##   stamina 0..1: sprinting drains it; it refills after a short pause. Running it
##                 dry leaves you winded (no sprint until it is back to 35%).
##   health 0..100: hazards and the Keeper hurt you. Under 50 you limp, under 20
##                 you can barely walk. 0 = dead. Field dressings heal 45.

signal health_changed(health: float)
signal state_changed(state: String)    # "ok", "injured", "critical", "dead"
signal died(cause: String)
signal winded

const SPRINT_DRAIN := 0.16       # per second -> 6.25 s of sprint from full (Phase 6, was 0.2)
const REGEN := 0.22              # per second
const REGEN_DELAY := 0.9
const RECOVER_AT := 0.35
const INJURED := 50.0
const CRITICAL := 20.0
const MEDKIT := 45.0

var stamina := 1.0
var health := 100.0
var exhausted := false
var last_cause := ""
var _since_sprint := 99.0
var _state := "ok"


func can_sprint() -> bool:
	return not exhausted and stamina > 0.0 and health >= CRITICAL


## Call every frame. `sprinting` = the player is actually running.
func step(delta: float, sprinting: bool) -> void:
	if health <= 0.0:
		return
	if sprinting and not exhausted and health >= CRITICAL:
		var mult := 1.35 if health < INJURED else 1.0
		stamina = maxf(0.0, stamina - SPRINT_DRAIN * mult * delta)
		_since_sprint = 0.0
		if stamina <= 0.005:
			stamina = 0.0
			exhausted = true
			winded.emit()
	else:
		_since_sprint += delta
		if _since_sprint >= REGEN_DELAY:
			var r := REGEN * (0.5 if health < INJURED else 1.0)
			stamina = minf(1.0, stamina + r * delta)
	if exhausted and stamina >= RECOVER_AT:
		exhausted = false


## Movement speed multiplier from injuries (limp).
func speed_mult() -> float:
	if health < CRITICAL:
		return 0.55
	if health < INJURED:
		return 0.78
	return 1.0


func state() -> String:
	if health <= 0.0:
		return "dead"
	if health < CRITICAL:
		return "critical"
	if health < INJURED:
		return "injured"
	return "ok"


func damage(amount: float, cause := "") -> void:
	if health <= 0.0 or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	last_cause = cause
	health_changed.emit(health)
	_check_state()
	if health <= 0.0:
		died.emit(cause)


func heal(amount: float) -> void:
	if health <= 0.0:
		return
	health = minf(100.0, health + amount)
	health_changed.emit(health)
	_check_state()


func _check_state() -> void:
	var s := state()
	if s != _state:
		_state = s
		state_changed.emit(s)


func to_dict() -> Dictionary:
	return {"stamina": stamina, "health": health}


func from_dict(d: Dictionary) -> void:
	stamina = float(d.get("stamina", 1.0))
	health = float(d.get("health", 100.0))
	_check_state()
