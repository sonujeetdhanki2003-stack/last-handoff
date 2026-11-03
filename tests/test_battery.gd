extends TestCase

func run() -> void:
	var b := BatteryModel.new()
	b.drain_per_second = 0.1
	var lows := [0]
	var deads := [0]
	b.low.connect(func(): lows[0] += 1)
	b.depleted.connect(func(): deads[0] += 1)
	b.drain(5.0)
	t.near(b.charge, 0.5, 0.0001, "drains at the set rate")
	b.drain(3.5)
	t.eq(lows[0], 1, "low signal once under 20%")
	b.drain(0.1)
	t.eq(lows[0], 1, "low signal not repeated")
	b.drain(10.0)
	t.check(b.is_empty(), "empties")
	t.eq(deads[0], 1, "depleted fires once")
	b.drain(1.0)
	t.near(b.charge, 0.0, 0.0, "never below zero")
	b.recharge(1.0)
	t.check(b.charge > 0.0, "recharge raises charge")
	b.replace()
	t.near(b.charge, 1.0, 0.0, "replace = full")

	# Flashlight node: drain only while on, dies at 0, battery item swap
	GameState.battery_charge = 0.5
	var root := Node3D.new()
	t.sandbox.add_child(root)
	var fl: Flashlight = load("res://scripts/player/flashlight.gd").new()
	var spot := SpotLight3D.new()
	spot.name = "SpotLight3D"
	fl.add_child(spot)
	fl.name = "Flashlight"
	root.add_child(fl)
	fl.set_process(false)  # drive time by hand
	await t.frames(1)
	t.near(fl.battery.charge, 0.5, 0.0001, "flashlight starts from the expedition's carried charge")
	fl.step(10.0)
	t.near(fl.battery.charge, 0.5, 0.0001, "no drain while off")
	fl.set_on(true)
	t.check(spot.visible, "light visible when on")
	fl.step(21.0)
	t.near(fl.battery.charge, 0.5 - 21.0 / 210.0, 0.001, "drains while on (210 s per full cell)")
	t.near(GameState.battery_charge, fl.battery.charge, 0.0001, "charge mirrored into GameState")
	var e_full := spot.light_energy
	fl.battery.charge = 0.1
	fl._flicker = 1.0
	fl._apply()
	t.check(spot.light_energy < e_full, "beam dims when the battery is low")
	var died := [false]
	fl.battery_dead.connect(func(): died[0] = true)
	for i in 30:
		fl.step(1.0)
	t.check(died[0] and not fl.on and not spot.visible, "light shuts off when the battery dies")
	fl.set_on(true)
	t.check(not fl.on, "cannot switch on a dead battery")
	t.check(not fl.replace_battery(), "swap refused with no spare cells")
	GameState.inventory.add("battery", 2)
	t.check(fl.replace_battery(), "swap with a spare cell")
	t.near(fl.battery.charge, 1.0, 0.0001, "battery full after swap")
	t.eq(GameState.inventory.count("battery"), 1, "swap consumes one cell")
	t.check(not fl.replace_battery(), "swap refused when already full (no cell wasted)")
	t.eq(GameState.inventory.count("battery"), 1, "no cell consumed when refused")

	# Charging dock (powered) recharges the player's flashlight
	var dock := ChargingDock.new()
	t.sandbox.add_child(dock)
	await t.frames(1)
	var actor := Node3D.new()
	actor.set_script(load("res://tests/fake_actor.gd"))
	actor.flashlight = fl
	fl.battery.charge = 0.3
	t.check(not dock.can_interact(actor), "dock refuses without power")
	t.eq(dock.get_refusal(actor), "Charger has no power", "dock says why")
	GameState.grid.set_on("aux", true)
	t.check(dock.can_interact(actor), "dock usable once aux is powered")
	t.check(dock.get_hold_time(actor) > 0.0, "charging is a hold interaction")
	dock.interact(actor)
	t.near(fl.battery.charge, 1.0, 0.0001, "dock recharges to full")
	t.check(not dock.can_interact(actor), "dock refuses a full battery")
	actor.free()
