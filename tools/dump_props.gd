extends Node
func _aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D: t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var a: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
		if acc[0] == null: acc[0] = a
		else: acc[0] = (acc[0] as AABB).merge(a)
	for c in n.get_children(): _aabb(c, t, acc)
func _ready() -> void:
	var d := DirAccess.open("res://assets/props")
	for id in d.get_directories():
		var f := "res://assets/props/%s/%s_1k.gltf" % [id, id]
		if not ResourceLoader.exists(f):
			print(id, " MISSING"); continue
		var s: Node3D = load(f).instantiate()
		var acc := [null]
		_aabb(s, Transform3D.IDENTITY, acc)
		var kids := []
		for c in s.get_children(): kids.append(c.name)
		var a: AABB = acc[0]
		print("%s|%s|%s|%s" % [id, str(a.position.snapped(Vector3.ONE*0.01)), str(a.size.snapped(Vector3.ONE*0.01)), ",".join(kids.slice(0, 14))])
		s.free()
	get_tree().quit(0)
