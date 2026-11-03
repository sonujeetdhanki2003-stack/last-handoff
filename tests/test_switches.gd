extends TestCase

func run() -> void:
	var lever := Lever.new()
	lever.circuit_id = "corridor_lights"
	lever.label_text = "LIGHTS"
	t.sandbox.add_child(lever)
	var light := PoweredLight.new()
	light.circuit = "corridor_lights"
	var o := OmniLight3D.new()
	light.add_child(o)
	t.sandbox.add_child(light)
	await t.frames(1)
	t.eq(lever.get_prompt(null), "Switch on Lights", "lever prompt")
	lever.interact(null)
	t.check(GameState.grid.is_on("corridor_lights"), "lever switches its circuit on")
	await t.frames(1)
	t.check(not o.visible, "light stays dark: breaker on but no upstream power")
	var gen := Generator.new()
	t.sandbox.add_child(gen)
	await t.frames(1)
	t.check(gen.can_interact(null), "generator can be started")
	t.eq(gen.get_hold_time(null), 2.0, "generator start is a 2 s hold")
	gen.interact(null)
	t.check(gen.running and GameState.grid.is_powered("aux"), "generator running powers aux")
	await t.frames(1)
	for i in 40:
		await t.frames(1)
	t.check(o.visible, "corridor light comes on once aux + breaker are on")
	t.check(not gen.can_interact(null), "running generator cannot be started again")
	lever.interact(null)
	await t.frames(2)
	t.check(not o.visible, "breaker off turns the light off")
	t.eq(GameState.get_world("").size(), 0, "no persist id -> nothing stored")

	var master := Lever.new()
	master.circuit_id = "lab"
	master.requires_flag = "fuse_panel_complete"
	master.requires_flag_text = "Dead"
	master.one_way = true
	t.sandbox.add_child(master)
	await t.frames(1)
	t.check(not master.can_interact(null), "master switch refuses until the fuse panel is fixed")
	t.eq(master.get_refusal(null), "Dead", "custom refusal text")
	GameState.set_flag("fuse_panel_complete")
	t.check(master.can_interact(null), "master switch usable after the flag")
	master.interact(null)
	t.check(GameState.grid.is_powered("lab"), "master switch powers the lab")
	t.check(not master.can_interact(null), "one-way switch cannot be turned back off")
