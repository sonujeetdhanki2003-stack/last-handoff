class_name PowerGrid
extends RefCounted
## Named circuits. A circuit is powered when it is switched on AND every
## circuit it depends on is powered (e.g. "lab" requires "aux").

signal circuit_changed(id: String, powered: bool)

var _circuits := {}  # id -> {"on": bool, "requires": PackedStringArray}


func define(id: String, requires: Array = [], on := false) -> void:
	_circuits[id] = {"on": on, "requires": PackedStringArray(requires)}


func has_circuit(id: String) -> bool:
	return _circuits.has(id)


func is_on(id: String) -> bool:
	return _circuits.has(id) and _circuits[id]["on"]


func is_powered(id: String, _depth := 0) -> bool:
	if id == "" :
		return true
	if not _circuits.has(id) or _depth > 16:
		return false
	var c: Dictionary = _circuits[id]
	if not c["on"]:
		return false
	for r in c["requires"]:
		if not is_powered(r, _depth + 1):
			return false
	return true


func set_on(id: String, on: bool) -> void:
	if not _circuits.has(id):
		define(id)
	var before := _snapshot()
	_circuits[id]["on"] = on
	_emit_diff(before)


func toggle(id: String) -> bool:
	set_on(id, not is_on(id))
	return is_on(id)


func _snapshot() -> Dictionary:
	var s := {}
	for id in _circuits:
		s[id] = is_powered(id)
	return s


func _emit_diff(before: Dictionary) -> void:
	for id in _circuits:
		var now := is_powered(id)
		if before.get(id, false) != now:
			circuit_changed.emit(id, now)


func to_dict() -> Dictionary:
	var d := {}
	for id in _circuits:
		d[id] = {"on": _circuits[id]["on"], "requires": Array(_circuits[id]["requires"])}
	return d


func from_dict(d: Dictionary) -> void:
	var before := _snapshot()
	_circuits.clear()
	for id in d:
		define(id, d[id].get("requires", []), bool(d[id].get("on", false)))
	_emit_diff(before)
