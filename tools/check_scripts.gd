extends Node
## Loads every GDScript in the project so parse/compile errors show up with
## autoloads registered. Prints CHECK OK / CHECK FAIL.

func _ready() -> void:
	var files: Array[String] = []
	_walk("res://", files)
	var bad := 0
	for f in files:
		var s: Script = load(f)
		if s == null or not s.can_instantiate():
			print("CHECK FAIL ", f)
			bad += 1
	print("CHECK %s  (%d scripts, %d failed)" % ["OK" if bad == 0 else "FAIL", files.size(), bad])
	get_tree().quit(1 if bad else 0)


func _walk(dir: String, out: Array[String]) -> void:
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with("."):
			continue
		_walk(dir.path_join(d), out)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
