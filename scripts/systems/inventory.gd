class_name Inventory
extends RefCounted
## Slot-based inventory with stacking. Pure data, no nodes: unit-testable.

signal changed
signal item_added(id: String, qty: int)
signal item_removed(id: String, qty: int)

var size: int
var slots: Array = []  # each entry: null or {"id": String, "qty": int}


func _init(p_size := 8) -> void:
	size = p_size
	slots.resize(size)
	slots.fill(null)


## Adds up to `qty`; returns how many did NOT fit.
func add(id: String, qty := 1) -> int:
	if qty <= 0:
		return 0
	var left := qty
	var cap := ItemDB.max_stack(id)
	# Top up existing stacks first.
	for i in size:
		if left == 0:
			break
		var s: Variant = slots[i]
		if s != null and s["id"] == id and s["qty"] < cap:
			var n: int = min(cap - s["qty"], left)
			s["qty"] += n
			left -= n
	# Then empty slots.
	for i in size:
		if left == 0:
			break
		if slots[i] == null:
			var n: int = min(cap, left)
			slots[i] = {"id": id, "qty": n}
			left -= n
	var added := qty - left
	if added > 0:
		item_added.emit(id, added)
		changed.emit()
	return left


func can_add(id: String, qty := 1) -> bool:
	var room := 0
	var cap := ItemDB.max_stack(id)
	for s in slots:
		if s == null:
			room += cap
		elif s["id"] == id:
			room += cap - int(s["qty"])
	return room >= qty


func count(id: String) -> int:
	var n := 0
	for s in slots:
		if s != null and s["id"] == id:
			n += int(s["qty"])
	return n


func has(id: String, qty := 1) -> bool:
	return count(id) >= qty


## Removes exactly `qty` (all or nothing). Takes from the last stacks first.
func remove(id: String, qty := 1) -> bool:
	if qty <= 0 or count(id) < qty:
		return false
	var left := qty
	for i in range(size - 1, -1, -1):
		var s: Variant = slots[i]
		if s != null and s["id"] == id:
			var n: int = min(int(s["qty"]), left)
			s["qty"] -= n
			left -= n
			if s["qty"] <= 0:
				slots[i] = null
			if left == 0:
				break
	item_removed.emit(id, qty)
	changed.emit()
	return true


## Removes up to `qty` from one slot; returns {"id","qty"} actually removed or {}.
func take_from_slot(index: int, qty := 1) -> Dictionary:
	if index < 0 or index >= size or slots[index] == null:
		return {}
	var s: Dictionary = slots[index]
	var n: int = min(qty, int(s["qty"]))
	s["qty"] -= n
	var id: String = s["id"]
	if s["qty"] <= 0:
		slots[index] = null
	item_removed.emit(id, n)
	changed.emit()
	return {"id": id, "qty": n}


func get_slot(index: int) -> Variant:
	if index < 0 or index >= size:
		return null
	return slots[index]


func used_slots() -> int:
	var n := 0
	for s in slots:
		if s != null:
			n += 1
	return n


func is_full() -> bool:
	return used_slots() >= size


func clear() -> void:
	slots.fill(null)
	changed.emit()


func to_dict() -> Dictionary:
	var out := []
	for s in slots:
		out.append(null if s == null else {"id": s["id"], "qty": s["qty"]})
	return {"size": size, "slots": out}


func from_dict(d: Dictionary) -> void:
	size = int(d.get("size", 8))
	slots.resize(size)
	slots.fill(null)
	var src: Array = d.get("slots", [])
	for i in min(size, src.size()):
		var s: Variant = src[i]
		if s is Dictionary and ItemDB.exists(str(s.get("id", ""))) and int(s.get("qty", 0)) > 0:
			slots[i] = {"id": str(s["id"]), "qty": int(s["qty"])}
	changed.emit()
