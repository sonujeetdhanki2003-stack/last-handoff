extends Node
## Phase 6 profiler: the real station, the player's own camera, each area, each preset.
##   xvfb-run godot --path . --resolution 960x540 res://tools/perf_probe.tscn -- --q=0,1,2,3 [--noocc]
## Prints one PERF line per area x preset: frame ms (this machine), draw calls, objects,
## primitives in frame.
var g: Node

func _ready() -> void:
	GameState.new_expedition(77)
	GameState.threat_enabled = false
	GameState.set_flag("intro_shown")
	g = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	for i in 10:
		await get_tree().process_frame
	GameState.grid.set_on("aux", true)
	get_viewport().use_occlusion_culling = not Harness.has("noocc")
	var qs: Array = Harness.get_arg("q", "0,1,2,3").split(",")
	var areas: Array = Harness.get_arg("areas", ",".join(Zones.RECTS.keys())).split(",")
	var p: Player = g.player
	p.flashlight.set_on(true)
	for qs_ in qs:
		var q := int(qs_)
		Settings.set_value("video", "quality", q, false)
		for area in areas:
			var r: Array = Zones.RECTS[area]
			var c := Vector3((r[0] + r[1]) * 0.5, 0.05, (r[2] + r[3]) * 0.5)
			var map: RID = g.get_world_3d().navigation_map
			var pos := NavigationServer3D.map_get_closest_point(map, c)
			if Zones.area_at(pos) != area:
				pos = c
			p.global_position = pos + Vector3(0, 0.05, 0)
			# look down the long axis of the room
			var yaw := 0.0 if (r[3] - r[2]) > (r[1] - r[0]) else 90.0
			p.cam.set_view(yaw, -8.0)
			p.cam.global_position = p.global_position + Vector3.UP * 1.55
			for i in 6:
				await get_tree().process_frame
			var dc := 0.0
			var ob := 0.0
			var pr := 0.0
			var t0 := Time.get_ticks_usec()
			var n := int(Harness.get_arg("frames", "8"))
			for i in n:
				await get_tree().process_frame
				dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
				ob += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
				pr += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
			print("PERF ", JSON.stringify({"q": q, "area": area, "ms": snappedf(ms, 0.1), "draws": int(dc / n), "objects": int(ob / n), "prims": int(pr / n), "occ": get_viewport().use_occlusion_culling}))
	get_tree().quit()
