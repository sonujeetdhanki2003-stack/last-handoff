extends Node
## v1.1 graphics pass: fixed camera spots for before/after comparisons + per-view render stats.
##   xvfb-run godot --path . --resolution 1280x720 res://tools/gfx_blender/gfx_shots.tscn -- --out=/tmp/shots --tag=before --q=2 [--views=corridor,lockers]
## Saves <out>/<tag>_<view>_q<q>.png and prints one GFX line per view (draw calls, primitives, objects).
var g: Node

const VIEWS := {
	# view: [camera position, look-at point]  (a free camera carrying a copy of the player's torch)
	"corridor": [Vector3(-0.9, 1.6, -4.4), Vector3(1.4, 1.3, -7.4)],
	"lockers": [Vector3(5.3, 1.55, -5.2), Vector3(7.6, 1.0, -7.0)],
	"pipes": [Vector3(0.5, 1.45, -16.2), Vector3(0.0, 2.9, -20.0)],
	"generator": [Vector3(-2.6, 1.6, -3.2), Vector3(-7.0, 1.0, -6.0)],
	"platform": [Vector3(0.0, 1.6, 1.2), Vector3(0.0, 1.1, 6.0)],
	"keeper": [Vector3(0.35, 1.45, -5.6), Vector3(0.0, 1.25, -7.6)],
	"lift34": [Vector3(-2.9, 1.55, 1.3), Vector3(0.6, 1.9, 6.6)],     # v1.2: the lift cage + shaft
	"liftclose": [Vector3(2.9, 1.5, 3.2), Vector3(-0.4, 1.35, 6.8)],    # v1.2: cage side, call box, rails
	"winch": [Vector3(4.9, 1.6, 1.6), Vector3(8.6, 1.0, 5.6)],         # v1.2: the new winch room
	"keeper_close": [Vector3(0.22, 1.62, -6.75), Vector3(0.0, 1.3, -7.9)],
}
var keeper: Keeper
var cam: Camera3D
var torch: Light3D

func _ready() -> void:
	GameState.new_expedition(77)
	GameState.threat_enabled = false
	GameState.set_flag("intro_shown")
	var q := int(Harness.get_arg("q", "2"))
	Settings.set_value("video", "quality", q, false)
	g = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	for i in 10:
		await get_tree().process_frame
	for c in Harness.get_arg("circuits", "aux,lab").split(",", false):
		GameState.grid.set_on(c, true)
	if g.get("hud"):
		g.hud.visible = false
	var p: Player = g.player
	for gi in p.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visible = false
	p.flashlight.set_on(true)
	await get_tree().process_frame
	cam = Camera3D.new()
	cam.fov = p.cam.find_children("*", "Camera3D", true, false)[0].fov if p.cam.find_children("*", "Camera3D", true, false).size() > 0 else 70.0
	add_child(cam)
	var src: Light3D = null
	for l in p.find_children("*", "SpotLight3D", true, false):
		if (l as Light3D).visible and (l as Light3D).light_energy > 0.0:
			src = l
			break
	if src and Harness.get_arg("torch", "1") == "1":
		torch = src.duplicate() as Light3D
		cam.add_child(torch)
		torch.transform = Transform3D(Basis(), Vector3(0.18, -0.15, 0.0))
	for l in p.find_children("*", "Light3D", true, false):
		(l as Light3D).visible = false
	for c in p.find_children("*", "Camera3D", true, false):
		(c as Camera3D).current = false
	p.process_mode = Node.PROCESS_MODE_DISABLED
	cam.make_current()
	if Harness.has("aodebug"):
		for mi in g.find_children("*", "MeshInstance3D", true, false):
			var sm := (mi as MeshInstance3D).material_override as ShaderMaterial
			if sm:
				sm.set_shader_parameter("ao_debug", 1.0)
	var out := Harness.get_arg("out", "/tmp/shots")
	DirAccess.make_dir_recursive_absolute(out)
	var tag := Harness.get_arg("tag", "shot")
	var views: Array = Harness.get_arg("views", ",".join(VIEWS.keys())).split(",", false)
	for v in views:
		var spec: Array = VIEWS[v]
		if v.begins_with("keeper") and keeper == null:
			keeper = load("res://scripts/threat/keeper.gd").new()
			keeper.think = false
			g.add_child(keeper)
			keeper.global_position = Vector3(0.0, 0.0, -7.9)
			keeper.rotation.y = PI - 0.35
			for i in 3:
				await get_tree().process_frame
			keeper.pose_clip(Harness.get_arg("clip", "kp_idle"), float(Harness.get_arg("clip_t", "0.6")))
		p.global_position = Vector3(spec[0].x, 0.05, spec[0].z)
		cam.global_position = spec[0]
		cam.look_at(spec[1])
		cam.make_current()
		for i in int(Harness.get_arg("settle", "14")):
			await get_tree().process_frame
		var dc := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var pr := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var ob := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var f := "%s/%s_%s_q%d.png" % [out, tag, v, q]
		img.save_png(f)
		print("GFX ", JSON.stringify({"view": v, "q": q, "draws": int(dc), "prims": int(pr), "objects": int(ob), "file": f}))
	get_tree().quit()
