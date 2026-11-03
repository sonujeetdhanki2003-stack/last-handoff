extends TestCase
## Stamina and health (pure model + the player using it), and the noise you make.


func run() -> void:
	var v := Vitals.new()
	t.check(v.can_sprint(), "fresh: can sprint")
	var secs := 0.0
	while not v.exhausted and secs < 10.0:
		v.step(0.1, true)
		secs += 0.1
	t.near(secs, 1.0 / Vitals.SPRINT_DRAIN, 0.25, "full stamina = about %.1f s of sprinting" % (1.0 / Vitals.SPRINT_DRAIN))
	t.check(not v.can_sprint(), "winded: no sprint")
	v.step(0.5, false)
	t.check(v.stamina == 0.0, "no regen during the short pause after sprinting")
	for i in 20:
		v.step(0.1, false)
	t.check(v.stamina > 0.0, "stamina refills after the pause")
	while v.exhausted:
		v.step(0.1, false)
	t.check(v.stamina >= Vitals.RECOVER_AT - 0.01, "sprint comes back at %d%%" % int(Vitals.RECOVER_AT * 100))

	var died := [""]
	v.died.connect(func(c): died[0] = c)
	v.damage(30, "steam")
	t.eq(v.state(), "ok", "70 health: fine")
	v.damage(25, "steam")
	t.eq(v.state(), "injured", "45 health: injured")
	t.near(v.speed_mult(), 0.78, 0.001, "injured: limping (78% speed)")
	v.damage(30, "shock")
	t.eq(v.state(), "critical", "15 health: critical")
	t.check(not v.can_sprint(), "critical: can't sprint")
	t.near(v.speed_mult(), 0.55, 0.001, "critical: barely walking")
	v.heal(Vitals.MEDKIT)
	t.eq(v.state(), "ok", "a field dressing (+45) brings you back up (60)")
	v.damage(500, "fire")
	t.eq(v.state(), "dead", "0 health: dead")
	t.eq(died[0], "fire", "death reports its cause")

	# --- on the player ------------------------------------------------------------
	make_floor(60.0)
	var p := spawn_player(Vector3(0, 0.1, 0))
	await t.physics(10)
	var noises: Array = []
	Events.noise.connect(func(pos, r, src): noises.append([r, src]))
	Input.action_press("move_forward")
	await t.physics(70)
	Input.action_release("move_forward")
	var walk := noises.filter(func(n): return n[1] == "step")
	t.check(not walk.is_empty() and walk[0][0] == Player.NOISE_WALK, "walking footsteps are heard at %.1f m" % Player.NOISE_WALK)
	noises.clear()
	p.toggle_crouch()
	await t.physics(5)
	Input.action_press("move_forward")
	await t.physics(80)
	Input.action_release("move_forward")
	t.check(noises.filter(func(n): return n[1] in ["step", "run"]).is_empty(), "crouch-walking makes no footstep noise")
	p.toggle_crouch()
	await t.physics(30)
	noises.clear()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await t.physics(60)
	t.check(p.running, "sprinting")
	t.check(noises.any(func(n): return n[1] == "run" and n[0] == Player.NOISE_RUN), "running footsteps are heard at %.0f m" % Player.NOISE_RUN)
	await t.physics(int(60.0 / Vitals.SPRINT_DRAIN) - 60 + 20)
	t.check(p.vitals.exhausted, "after ~%.1f s the player is winded" % (1.0 / Vitals.SPRINT_DRAIN))
	t.check(not p.running, "winded: sprint key no longer runs")
	t.check(noises.any(func(n): return n[1] == "winded"), "running out of breath makes a gasp the Keeper can hear")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await t.physics(10)
	# injuries slow the player
	p.hurt(60, "steam")
	t.eq(p.vitals.state(), "injured", "player injured by a hazard")
	p.velocity = Vector3.ZERO
	Input.action_press("move_forward")
	await t.physics(60)
	var sp := Vector2(p.velocity.x, p.velocity.z).length()
	Input.action_release("move_forward")
	t.near(sp, p.walk_speed * 0.78, 0.08, "injured player limps")
	GameState.inventory.add("medkit")
	t.check(p.use_medkit(), "field dressing used")
	t.eq(p.vitals.state(), "ok", "dressing treats the injury (40 + 45 = 85)")
	t.check(not GameState.inventory.has("medkit"), "dressing consumed")
	p.hurt(1000, "fire")
	await t.physics(2)
	t.check(p.dead and not p.control_enabled, "death removes control")
