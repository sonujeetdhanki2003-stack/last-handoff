extends Node
## Balance simulation (headless, run with --fixed-fps 60): a scripted player in
## the real station against the real Keeper.
##   godot --headless --fixed-fps 60 --path . res://tools/balance_sim.tscn -- --runs=8
## Scenarios
##   flee   : spotted at distance d; sprint to the nearest locker by path, hide.
##   light  : spotted at distance d; stand and hold the flashlight on it.
##   hide   : sit in a locker for 120 s while it patrols (does it find you?).
##   still  : crouch still in a dark corner while it patrols (time until noticed).
## Prints one JSON line per run (SIM {...}) and a summary.

var results: Array = []


func _ready() -> void:
	var runs := int(Harness.get_arg("runs", "6"))
	var only := Harness.get_arg("only", "")
	var plan: Array = []
	for sc in ["flee", "light", "hide", "still"]:
		if only != "" and not only.split(",").has(sc):
			continue
		for d in ([6.0, 9.0, 12.0] if sc in ["flee", "light"] else [0.0]):
			for r in runs:
				plan.append([sc, d, 1000 + r * 17 + int(d)])
	for p in plan:
		await _run(p[0], p[1], p[2])
	_summary()
	get_tree().quit()


func _game(seed: int) -> Node:
	GameState.new_expedition(seed)
	GameState.threat_enabled = true
	GameState.chain_mode = false
	var g: Node = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	for i in 4:
		await get_tree().physics_frame
	for gid in ["aux", "corridor_lights"]:
		GameState.grid.set_on(gid, true)
	return g


const STARTS := [Vector3(0.5, 0.05, -4.0), Vector3(0.4, 0.05, -10.0), Vector3(-3.5, 0.05, -14.5), Vector3(4.5, 0.05, -9.5), Vector3(0.3, 0.05, -16.0), Vector3(-6.5, 0.05, -3.0)]


func _path_len(map: RID, a: Vector3, b: Vector3) -> float:
	var pts := NavigationServer3D.map_get_path(map, a, b, true)
	var L := 0.0
	for i in range(1, pts.size()):
		L += pts[i - 1].distance_to(pts[i])
	return L if pts.size() > 1 else 999.0


func _run(sc: String, d: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var g: Node = await _game(seed)
	var p: Player = g.player
	var k: Keeper = g.keeper if g.keeper else g.spawn_keeper()
	for i in 3:
		await get_tree().physics_frame
	var start: Vector3 = STARTS[rng.randi() % STARTS.size()]
	p.global_position = start
	var map := k.agent.get_navigation_map()
	# put the Keeper d metres away along the navmesh, toward the station's depths
	# a spot ~d metres away by path with a clear line of sight to the player
	var kpos := NavigationServer3D.map_get_closest_point(map, start + Vector3(0, 0, -d))
	var best_err := 999.0
	var space := p.get_world_3d().direct_space_state
	for a in 36:
		var ang := TAU * a / 36.0 + rng.randf() * 0.1
		var c := NavigationServer3D.map_get_closest_point(map, start + Vector3(sin(ang), 0, cos(ang)) * d)
		var err := absf(_path_len(map, start, c) - d) + absf(c.distance_to(start) - d)
		var q := PhysicsRayQueryParameters3D.create(c + Vector3.UP * 1.6, start + Vector3.UP * 1.3, 1)
		q.exclude = [p.get_rid()]
		if not space.intersect_ray(q).is_empty():
			err += 50.0
		if err < best_err:
			best_err = err
			kpos = c
	if sc in ["hide", "still"]:
		kpos = NavigationServer3D.map_get_closest_point(map, Vector3(0.3, 0, -20.0))
	k.global_position = kpos
	k.state = Keeper.S.PATROL if sc in ["hide", "still"] else Keeper.S.DORMANT
	if sc in ["flee", "light"]:
		k.look_at_flat(p.global_position)
		k.set_state(Keeper.S.CHASE)
		k.last_seen = p.global_position
	var caught := [false, false]
	k.caught_player.connect(func(fatal: bool): caught[0] = true; caught[1] = fatal)
	var res := {"sc": sc, "d": d, "seed": seed, "start": [start.x, start.z]}
	var target_spot: Node = null
	if sc == "flee":
		var best := 999.0
		for s in get_tree().get_nodes_in_group("hiding_spots"):
			var goal: Vector3 = s.call("outside_point")
			var L := _path_len(map, p.global_position, goal)
			# a person runs away from it, not past it
			for q in NavigationServer3D.map_get_path(map, p.global_position, goal, true):
				if q.distance_to(kpos) < 3.0:
					L += 100.0
					break
			if L < best:
				best = L
				target_spot = s
		res["spot"] = target_spot.name if target_spot else ""
		res["spot_dist"] = snappedf(best, 0.1)
	if sc == "hide":
		target_spot = g.get_node("Level/Interactables/LockerArchive")
		p.global_position = target_spot.call("outside_point")
		target_spot.interact(p)
	if sc == "still":
		p.global_position = Vector3(-6.8, 0.05, -1.2)
		p._set_crouch(true)
	var T := 0.0
	var limit := 45.0 if sc in ["flee", "light"] else 120.0
	var min_d := 999.0
	var hidden_at := -1.0
	var noticed_at := -1.0
	var repelled_at := -1.0
	var max_stamina_out := false
	while T < limit and not caught[0]:
		await get_tree().physics_frame
		T += 1.0 / 60.0
		var kd := k.global_position.distance_to(p.global_position)
		min_d = minf(min_d, kd)
		if p.vitals.exhausted:
			max_stamina_out = true
		match sc:
			"flee":
				if p.hidden_in == null and target_spot:
					var goal: Vector3 = target_spot.call("outside_point")
					var pts := NavigationServer3D.map_get_path(map, p.global_position, goal, true)
					var nxt := goal
					for q in pts:
						if Vector2(q.x - p.global_position.x, q.z - p.global_position.z).length() > 0.6:
							nxt = q
							break
					var to := nxt - p.global_position
					p.cam.set_view(rad_to_deg(atan2(-to.x, -to.z)), -10.0)
					Input.action_press("move_forward")
					if p.vitals.can_sprint():
						Input.action_press("sprint")
					else:
						Input.action_release("sprint")
					if p.global_position.distance_to(goal) < 1.0:
						Input.action_release("move_forward")
						Input.action_release("sprint")
						target_spot.interact(p)
						hidden_at = T
			"light":
				var to := k.global_position - p.global_position
				p.cam.set_view(rad_to_deg(atan2(-to.x, -to.z)), -4.0)
				p.flashlight.set_on(true)
				if k.state == Keeper.S.REPELLED and repelled_at < 0.0:
					repelled_at = T
				if repelled_at > 0.0 and T > repelled_at + 8.0:
					break
			"hide", "still":
				if noticed_at < 0.0 and k.state in [Keeper.S.CHASE, Keeper.S.INVESTIGATE]:
					noticed_at = T
					if sc == "still":
						break
		if sc == "flee" and hidden_at > 0.0 and T > hidden_at + 25.0:
			break
	Input.action_release("move_forward")
	Input.action_release("sprint")
	res["caught"] = caught[0]
	res["fatal"] = caught[1]
	res["t"] = snappedf(T, 0.1)
	res["min_d"] = snappedf(min_d, 0.1)
	res["hidden_at"] = snappedf(hidden_at, 0.1)
	res["noticed_at"] = snappedf(noticed_at, 0.1)
	res["repelled_at"] = snappedf(repelled_at, 0.1)
	res["exhausted"] = max_stamina_out
	res["keeper_state"] = k.state_name()
	print("SIM ", JSON.stringify(res))
	results.append(res)
	g.queue_free()
	for i in 3:
		await get_tree().physics_frame


func _summary() -> void:
	var by := {}
	for r in results:
		var key := "%s d=%d" % [r["sc"], int(r["d"])]
		if not by.has(key):
			by[key] = {"n": 0, "caught": 0, "fatal": 0, "t": 0.0, "notice": []}
		by[key]["n"] += 1
		by[key]["caught"] += 1 if r["caught"] else 0
		by[key]["fatal"] += 1 if r["fatal"] else 0
		if r["noticed_at"] > 0:
			by[key]["notice"].append(r["noticed_at"])
	for key in by:
		var b: Dictionary = by[key]
		print("SUMMARY %-14s runs %d  caught %d (fatal %d)  noticed %s" % [key, b["n"], b["caught"], b["fatal"], str(b["notice"])])
