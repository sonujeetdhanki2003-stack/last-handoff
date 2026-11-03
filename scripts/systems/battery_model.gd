class_name BatteryModel
extends RefCounted
## Flashlight battery: charge in [0, 1]. Pure logic, the Flashlight node drives it.

signal depleted
signal low
signal charged

const LOW_THRESHOLD := 0.2

var charge := 1.0
var drain_per_second := 1.0 / 210.0   # a full cell lasts 3.5 minutes of light
var recharge_per_second := 1.0 / 6.0  # charging dock: empty to full in 6 s
var _was_low := false


func drain(delta: float) -> void:
	if charge <= 0.0:
		return
	charge = maxf(0.0, charge - drain_per_second * delta)
	if charge < LOW_THRESHOLD and not _was_low:
		_was_low = true
		low.emit()
	if charge <= 0.0:
		depleted.emit()


func recharge(delta: float) -> void:
	var before := charge
	charge = minf(1.0, charge + recharge_per_second * delta)
	if charge >= LOW_THRESHOLD:
		_was_low = false
	if before < 1.0 and charge >= 1.0:
		charged.emit()


func replace() -> void:
	charge = 1.0
	_was_low = false
	charged.emit()


func is_empty() -> bool:
	return charge <= 0.0


func is_low() -> bool:
	return charge < LOW_THRESHOLD


func percent() -> int:
	return int(round(charge * 100.0))
