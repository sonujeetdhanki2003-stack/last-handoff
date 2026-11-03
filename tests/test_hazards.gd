extends TestCase
## The lesser hazards: steam bursts, live wires, gas. Readable and fair.


func run() -> void:
	make_floor(40.0)
	var p := spawn_player(Vector3(0, 0.1, 10))
	await t.physics(5)
	# --- steam
	var s := SteamBurst.new()
	s.idle_time = 1.0
	t.sandbox.add_child(s)
	s.global_position = Vector3(0, 1.6, 0)   # blows along +Z
	await t.physics(2)
	t.check(s.contains(Vector3(0, 0.9, 1.5)), "danger box in front of the main")
	t.check(not s.contains(Vector3(0, 0.9, -1.0)), "behind it is safe")
	p.global_position = Vector3(0, 0.1, 1.5)
	await t.physics(2)
	var hp0 := p.vitals.health
	var saw_warn := false
	for i in 60:
		await t.physics(1)
		if s.stage == SteamBurst.P.WARN:
			saw_warn = true
			t.eq(p.vitals.health, hp0, "the warning hiss does no damage")
			break
	t.check(saw_warn, "it always warns before it blows")
	for i in 120:
		await t.physics(1)
		if s.stage == SteamBurst.P.BURST:
			break
	await t.physics(20)
	t.eq(p.vitals.health, hp0 - s.damage, "caught in the burst: 30 damage")
	await t.physics(60)
	t.eq(p.vitals.health, hp0 - s.damage, "only once per burst")
	p.global_position = Vector3(3, 0.1, 1.5)
	var h1 := p.vitals.health
	for i in 400:
		await t.physics(1)
		if s.stage == SteamBurst.P.BURST:
			break
	await t.physics(30)
	t.eq(p.vitals.health, h1, "standing clear of it: no damage")
	s.queue_free()

	# --- live wire
	p.vitals = Vitals.new()
	var w := LiveWire.new()
	t.sandbox.add_child(w)
	w.global_position = Vector3(-6, 0, 0)
	await t.physics(2)
	GameState.grid.set_on("aux", false)
	p.global_position = Vector3(-6, 0.1, 0.3)
	await t.physics(10)
	t.eq(p.vitals.health, 100.0, "no power: just a puddle")
	t.check(not w.is_live(), "wire reports dead")
	p.global_position = Vector3(-6, 0.1, 6)
	GameState.grid.set_on("aux", true)
	await t.physics(2)
	t.check(w.is_live(), "power on: the water is live")
	p.global_position = Vector3(-6, 0.1, 0.3)
	await t.physics(4)
	t.eq(p.vitals.health, 100.0 - w.damage, "stepping in: shocked for 35")
	t.check(p.global_position.distance_to(w.global_position) > 0.3 or p.velocity.length() > 1.0, "and thrown back")
	GameState.grid.set_on("aux", false)

	# --- gas
	p.vitals = Vitals.new()
	var g := GasPocket.new()
	t.sandbox.add_child(g)
	g.global_position = Vector3(8, 1.2, 0)
	await t.physics(2)
	p.flashlight.set_on(false)
	p.global_position = Vector3(8, 0.1, 0)
	await t.physics(90)
	t.eq(p.vitals.health, 100.0, "lights off in the gas: safe")
	t.check(g.warned, "first time in, you're warned about the gas")
	p.flashlight.set_on(true)
	await t.physics(30)
	t.eq(p.vitals.health, 100.0, "the light flickers on: a moment to switch it off")
	p.flashlight.set_on(false)
	await t.physics(60)
	t.eq(p.vitals.health, 100.0, "switched off in time: nothing happens")
	p.flashlight.set_on(true)
	await t.physics(75)
	t.eq(p.vitals.health, 100.0 - g.damage, "left on for a second: the gas goes up (60 damage)")
	t.check(not g.is_charged(), "the pocket burns off and has to refill")
	p.vitals = Vitals.new()
	await t.physics(60)
	t.eq(p.vitals.health, 100.0, "no second blast while it refills")
	p.global_position = Vector3(0, 0.1, 10)
	await t.physics(2)

	# hazards sleep in peaceful mode (the Phase 1-3 tests)
	GameState.threat_enabled = false
	var s2 := SteamBurst.new()
	s2.idle_time = 0.2
	t.sandbox.add_child(s2)
	await t.physics(60)
	t.eq(s2.stage, SteamBurst.P.IDLE, "hazards are off when the threat is disabled")
	GameState.threat_enabled = true
