class_name ObjectiveTracker
extends RefCounted
## Ordered mission objectives with optional counters.

signal objective_added(id: String)
signal objective_updated(id: String)
signal objective_completed(id: String)
signal all_completed

var _order: Array[String] = []
var _obj := {}  # id -> {"text", "target", "progress", "done", "hidden"}


func add(id: String, text: String, target := 1, hidden := false) -> void:
	if not _obj.has(id):
		_order.append(id)
	_obj[id] = {"text": text, "target": max(1, target), "progress": 0, "done": false, "hidden": hidden}
	objective_added.emit(id)


func has(id: String) -> bool:
	return _obj.has(id)


func reveal(id: String) -> void:
	if _obj.has(id) and _obj[id]["hidden"]:
		_obj[id]["hidden"] = false
		objective_updated.emit(id)


func set_progress(id: String, value: int) -> void:
	if not _obj.has(id) or _obj[id]["done"]:
		return
	var o: Dictionary = _obj[id]
	var v: int = clampi(value, 0, o["target"])
	if v == o["progress"]:
		return
	o["progress"] = v
	objective_updated.emit(id)
	if v >= o["target"]:
		complete(id)


func add_progress(id: String, amount := 1) -> void:
	if _obj.has(id):
		set_progress(id, int(_obj[id]["progress"]) + amount)


func complete(id: String) -> void:
	if not _obj.has(id) or _obj[id]["done"]:
		return
	var o: Dictionary = _obj[id]
	o["done"] = true
	o["progress"] = o["target"]
	o["hidden"] = false
	objective_completed.emit(id)
	if is_all_complete():
		all_completed.emit()


func is_complete(id: String) -> bool:
	return _obj.has(id) and _obj[id]["done"]


func is_all_complete() -> bool:
	for id in _order:
		if not _obj[id]["done"]:
			return false
	return _order.size() > 0


func get_objective(id: String) -> Dictionary:
	return _obj.get(id, {})


## First visible, unfinished objective in order ("" when none).
func current_id() -> String:
	for id in _order:
		if not _obj[id]["done"] and not _obj[id]["hidden"]:
			return id
	return ""


func label(id: String) -> String:
	if not _obj.has(id):
		return ""
	var o: Dictionary = _obj[id]
	if o["target"] > 1:
		return "%s  (%d/%d)" % [o["text"], o["progress"], o["target"]]
	return o["text"]


func ids() -> Array[String]:
	return _order.duplicate()


func to_dict() -> Dictionary:
	var list := []
	for id in _order:
		var o: Dictionary = _obj[id]
		list.append({"id": id, "text": o["text"], "target": o["target"], "progress": o["progress"], "done": o["done"], "hidden": o["hidden"]})
	return {"objectives": list}


func from_dict(d: Dictionary) -> void:
	_order.clear()
	_obj.clear()
	for o in d.get("objectives", []):
		_order.append(o["id"])
		_obj[o["id"]] = {"text": o["text"], "target": int(o["target"]), "progress": int(o["progress"]), "done": bool(o["done"]), "hidden": bool(o["hidden"])}
