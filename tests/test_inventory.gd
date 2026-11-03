extends TestCase

func run() -> void:
	var inv := Inventory.new(4)
	t.eq(inv.used_slots(), 0, "new inventory is empty")
	t.eq(inv.add("fuse", 2), 0, "add 2 fuses fits")
	t.eq(inv.count("fuse"), 2, "count fuses = 2")
	t.eq(inv.used_slots(), 1, "fuses share one slot")
	t.eq(inv.add("fuse", 2), 0, "add 2 more fuses")
	t.eq(inv.used_slots(), 2, "stack cap 3 spills into a second slot")
	t.eq(inv.count("fuse"), 4, "count = 4")
	t.eq(inv.add("keycard_blue"), 0, "keycard added")
	t.eq(inv.add("research_drive"), 0, "drive added (inventory now full)")
	t.check(inv.is_full(), "inventory reports full")
	t.eq(inv.add("battery", 1), 1, "item that does not fit is returned as leftover")
	t.check(not inv.can_add("battery"), "can_add false when full")
	t.check(inv.can_add("fuse", 2), "can_add true when an existing stack has room")
	t.check(inv.remove("fuse", 3), "remove 3 fuses")
	t.eq(inv.count("fuse"), 1, "1 fuse left")
	t.check(not inv.remove("fuse", 2), "removing more than held fails")
	t.eq(inv.count("fuse"), 1, "failed remove changes nothing")
	var taken := inv.take_from_slot(0, 5)
	t.eq(taken.get("qty", 0), 1, "take_from_slot takes at most what the slot holds")
	t.check(inv.get_slot(0) == null, "slot emptied after take")
	# signals
	var log := []
	inv.item_added.connect(func(id, q): log.append(["add", id, q]))
	inv.item_removed.connect(func(id, q): log.append(["rem", id, q]))
	inv.add("battery", 1)
	inv.remove("battery", 1)
	t.eq(log, [["add", "battery", 1], ["rem", "battery", 1]], "add/remove emit signals")
	# serialisation
	inv.add("battery", 3)
	var d := inv.to_dict()
	var inv2 := Inventory.new()
	inv2.from_dict(JSON.parse_string(JSON.stringify(d)))
	t.eq(inv2.count("battery"), 3, "round-trips through JSON (batteries)")
	t.eq(inv2.count("keycard_blue"), 1, "round-trips through JSON (keycard)")
	inv2.from_dict({"size": 4, "slots": [{"id": "not_an_item", "qty": 3}, {"id": "fuse", "qty": -2}]})
	t.eq(inv2.used_slots(), 0, "from_dict drops unknown items and bad quantities")

	# World pickup -> inventory, then drop back into the world
	await t.physics(1)
	var p := Pickup.new()
	p.item_id = "battery"
	p.quantity = 2
	t.sandbox.add_child(p)
	await t.frames(1)
	t.eq(p.get_prompt(null), "Take Battery Cell x2", "pickup prompt names item and amount")
	p.interact(null)
	t.eq(GameState.inventory.count("battery"), 2, "pickup puts items in the expedition inventory")
	await t.frames(1)
	t.check(not is_instance_valid(p), "picked-up item is removed from the world")
	# full inventory refuses a pickup and keeps it in the world
	GameState.inventory.clear()
	for i in GameState.inventory.size:
		GameState.inventory.add("research_drive")
	var p2 := Pickup.new()
	p2.item_id = "fuse"
	t.sandbox.add_child(p2)
	await t.frames(1)
	t.check(not p2.can_interact(null), "pickup refused when inventory is full")
	t.eq(p2.get_refusal(null), "Inventory full", "refusal says why")
	t.check(is_instance_valid(p2) and p2.is_inside_tree(), "refused pickup stays in the world")
