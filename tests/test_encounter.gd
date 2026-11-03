extends TestCase
## A scripted encounter in the real level: it wakes when the power comes on, leaves
## the locked lab through the ducts, hears you run, chases, is driven off by the
## flashlight, loses you in a locker, opens doors it can, stops at locked ones, and
## a second catch while injured is the fair grab-and-fade.

var g: Node
var p: Player
var k: Keeper


func _tree() -> SceneTree:
	return t.sandbox.get_tree()


func _go(pos: Vector3, yaw: float) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.cam.set_view(yaw, -6.0)
	p.cam.global_position = pos + Vector3.UP * 1.55
	await t.physics(3)


func run() -> void:
	GameState.new_expedition(77)
	GameState.threat_enabled = true
	g = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(g)
	p = g.player
	await t.physics(10)
	k = g.keeper
	t.check(k != null, "the Keeper is in the level")
	t.check(g.nav != null and NavigationServer3D.region_get_connections_count(g.nav.get_rid()) >= 0, "navmesh baked at runtime")
	t.eq(k.state_name(), "dormant", "dormant in Lab 3 at the start")
	t.check(k.global_position.distance_to(NavBaker.LAIR) < 1.0, "in its lair")
	# the facility path exists: lair -> shaft
	var path := NavigationServer3D.map_get_path(g.get_world_3d().navigation_map, NavBaker.LAIR, Vector3(0, 0, 3.0), true)
	t.check(path.size() > 2 and path[-1].distance_to(Vector3(0, 0, 3.0)) < 1.0, "navmesh connects Lab 3 to the shaft through the doorways")
	var crawl := NavigationServer3D.map_get_closest_point(g.get_world_3d().navigation_map, Vector3(-14, 0, -5.5))
	t.check(crawl.distance_to(Vector3(-14, 0, -5.5)) > 0.8, "the crawlspace is too low for it (no navmesh in there)")

	# power on -> it wakes, and (lab still coded shut) takes the ducts out
	g.get_node("Level/Interactables/DoorShaft").set_open_immediate(true)
	await _go(Vector3(0.4, 0.05, 2.0), 0.0)
	GameState.grid.set_on("aux", true)
	for i in 60 * 11:
		await t.physics(1)
		if k.global_position.z > -21.0 and k.state != Keeper.S.DORMANT:
			break
	t.check(k.state != Keeper.S.DORMANT, "the generator wakes it")
	t.check(k.global_position.z > -21.0, "it drops out of the duct into the corridor")

	# it hears running
	k.global_position = Vector3(0, 0.05, -14)
	k.set_state(Keeper.S.PATROL)
	k.look_at_flat(Vector3(0, 0, -20))
	p.flashlight.set_on(false)
	await _go(Vector3(0.4, 0.05, -3.0), 0.0)
	p.cam.set_view(0.0, -60.0)   # torch on the floor, not in its face
	await t.physics(2)
	Events.noise.emit(p.global_position, Player.NOISE_RUN, "run")
	await t.physics(2)
	t.eq(k.state_name(), "investigate", "running 11 m away: it comes")
	p.flashlight.set_on(true)
	for i in 300:
		await t.physics(1)
		if k.state == Keeper.S.CHASE:
			break
	t.eq(k.state_name(), "chase", "it sees your light and charges")
	# drive it off with the beam
	for i in 120:
		if i % 6 == 0:
			await aim_at(p, k.global_position + Vector3.UP * 1.6)
		else:
			await t.physics(1)
		if k.state in [Keeper.S.REPELLED, Keeper.S.RETREAT]:
			break
		if p.dead or p.vitals.health < 100.0:
			break
	t.check(k.state in [Keeper.S.REPELLED, Keeper.S.RETREAT], "the beam on its face drives it back (%s)" % k.state_name())
	t.eq(p.vitals.health, 100.0, "before it reached you")

	# run to Security and hide while it's backing off
	g.get_node("Level/Interactables/DoorSecurity").set_open_immediate(true)
	var locker: HidingSpot = g.get_node("Level/Interactables/LockerSecurityA")
	await _go(locker.outside_point(), 90.0)
	locker.interact(p)
	await t.physics(2)
	t.check(p.is_hidden() and k.seen_hiding == null, "hidden in the Security locker, unseen")
	k.global_position = Vector3(3.5, 0.05, -6.0)
	k.velocity = Vector3.ZERO
	k.set_state(Keeper.S.SEARCH)
	var alive := true
	for i in 60 * 9:
		await t.physics(1)
		if p.dead:
			alive = false
	t.check(alive, "it searches the room and doesn't find you")
	locker.leave(p)
	await t.physics(3)

	# doors: it opens a closed, unlocked, powered door ...
	var ds: Door = g.get_node("Level/Interactables/DoorStorage")
	ds.key_used = true            # a member swiped it open on an earlier visit
	ds.set_open_immediate(false)
	await t.physics(2)
	await _go(Vector3(0.6, 0.05, 6.0), 0.0)
	k.global_position = Vector3(0.0, 0.05, -15.0)
	k.velocity = Vector3.ZERO
	k.set_state(Keeper.S.PATROL)
	k._investigate(Vector3(-5.0, 0.0, -15.0))
	for i in 60 * 14:
		await t.physics(1)
		if k.global_position.x < -2.5:
			break
	t.check(ds.is_open() or ds.state == Door.State.OPENING, "it opens the storage door")
	t.check(k.global_position.x < -2.5, "and walks into Storage")
	# ... but not the coded lab door
	var dl: Door = g.get_node("Level/Interactables/DoorLab")
	t.check(not dl.keeper_can_open(), "the lab door is locked to it")
	k.global_position = Vector3(0.0, 0.05, -17.0)
	k.set_state(Keeper.S.PATROL)
	k._investigate(Vector3(0.0, 0.0, -28.0))
	for i in 60 * 6:
		await t.physics(1)
	t.check(not dl.is_open() and k.global_position.z > -22.2, "a locked door stops it")

	# a catch while healthy hurts; injured, the next is the grab
	await _go(Vector3(0.4, 0.05, -6.0), 180.0)
	p.flashlight.set_on(false)
	k.global_position = Vector3(0.0, 0.05, -8.0)
	k.velocity = Vector3.ZERO
	k.awareness = 1.0
	k.last_seen = p.global_position
	k.repel_cooldown = 99.0
	k.set_state(Keeper.S.CHASE)
	for i in 240:
		await t.physics(1)
		if p.vitals.health < 100.0:
			break
	t.check(p.vitals.state() == "injured" and not p.dead, "first catch: struck and injured, it backs off")
	k.global_position = p.global_position + Vector3(0, 0, -2.0)
	k.awareness = 1.0
	k.last_seen = p.global_position
	k.set_state(Keeper.S.CHASE)
	for i in 240:
		await t.physics(1)
		if p.dead:
			break
	t.check(p.dead and p.grabbed, "injured: the grab")
	t.check(not p.control_enabled, "no control while grabbed")
	var shown := false
	for i in 60 * 6:
		await _tree().process_frame
		if g.hud.end_panel.visible:
			shown = true
			break
	t.check(shown, "fade to black, then the end screen (no gore: hands, a shake, black)")
	t.check(g.hud._fade.color.a > 0.9, "screen faded to black")
	g.queue_free()
	g = null
	_tree().paused = false
	Events.set_modal(false)
	await t.physics(3)
