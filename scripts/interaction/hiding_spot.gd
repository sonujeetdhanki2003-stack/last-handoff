class_name HidingSpot
extends Interactable
## A locker or the space under a cot. Interact to climb in, Interact again to get
## out. While hidden the Keeper can't see you, unless it watched you go in.

@export var kind := "locker"            ## "locker" | "cot"
@export var view_offset := Vector3(0, 1.55, -0.12)   ## local camera position inside
@export var exit_offset := Vector3(0, 0.05, 0.75)    ## local point you step out to

var occupant: Player = null
var view: Camera3D
var _door: Node3D
var _audio: AudioStreamPlayer3D


func _ready() -> void:
	solid = kind == "locker"
	prompt = "Hide in the locker" if kind == "locker" else "Hide under the cot"
	add_to_group("hiding_spots")
	super._ready()
	if kind == "locker":
		_build_locker()
	else:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(2.1, 0.6, 1.1)
		cs.shape = bs
		cs.position.y = 0.3
		add_child(cs)
	view = Camera3D.new()
	view.name = "View"
	view.position = view_offset
	view.fov = 62.0
	view.rotation.x = 0.0 if kind == "locker" else deg_to_rad(4.0)
	add_child(view)
	_audio = AudioStreamPlayer3D.new()
	_audio.bus = &"SFX"
	_audio.stream = load("res://audio/sfx/locker.wav")
	_audio.position.y = 1.0
	add_child(_audio)


func _build_locker() -> void:
	var steel: Material = ArtMats.local("green_metal", Color(0.55, 0.62, 0.6))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.05, 0.05)
	var w := 0.62
	var dpt := 0.55
	var h := 1.95
	if GfxAssets.mesh("locker_body") and GfxAssets.mesh("locker_door"):
		# v1.1: the Blender locker (pressed sides, louvred door, latch, hinges, name card)
		var body := GfxAssets.instance("locker_body", steel)
		add_child(body)
		GfxAssets.shadow_proxy(body, self, Vector3(w, h, dpt - 0.03), Vector3(0, h / 2, -0.015))
		_door = Node3D.new()
		_door.position = Vector3(-w / 2, 0, dpt / 2)
		add_child(_door)
		var dm := GfxAssets.instance("locker_door", steel)
		_door.add_child(dm)
		GfxAssets.shadow_proxy(dm, _door, Vector3(w, h - 0.04, 0.025), Vector3(w / 2, h / 2, 0))
		var cs1 := CollisionShape3D.new()
		var bs1 := BoxShape3D.new()
		bs1.size = Vector3(w, h, dpt)
		cs1.shape = bs1
		cs1.position = Vector3(0, h / 2, 0)
		add_child(cs1)
		return
	_box(self, Vector3(w, h, 0.03), Vector3(0, h / 2, -dpt / 2), steel)          # back
	_box(self, Vector3(0.03, h, dpt), Vector3(-w / 2, h / 2, 0), steel)           # sides
	_box(self, Vector3(0.03, h, dpt), Vector3(w / 2, h / 2, 0), steel)
	_box(self, Vector3(w, 0.03, dpt), Vector3(0, h, 0), steel)                    # top
	_box(self, Vector3(w, 0.06, dpt), Vector3(0, 0.03, 0), steel)                 # floor
	_door = Node3D.new()
	_door.position = Vector3(-w / 2, 0, dpt / 2)
	add_child(_door)
	_box(_door, Vector3(w, h - 0.04, 0.025), Vector3(w / 2, h / 2, 0), steel)
	for k in 5:  # vent slits you look out through
		_box(_door, Vector3(w * 0.6, 0.018, 0.03), Vector3(w / 2, 1.42 + k * 0.045, 0.0), dark)
	_box(_door, Vector3(0.03, 0.14, 0.04), Vector3(w - 0.07, 1.05, 0.02), dark)   # handle
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, h, dpt)
	cs.shape = bs
	cs.position = Vector3(0, h / 2, 0)
	add_child(cs)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func get_prompt(_a: Node) -> String:
	return prompt


## v1.2 fake-out: the empty locker's door shudders on its hinges (FakeoutDirector).
## Visual + sound only: no noise event, the Keeper does not hear it.
var rattling := false
func rattle() -> bool:
	if kind != "locker" or occupant != null or _door == null or rattling:
		return false
	rattling = true
	var p := AudioStreamPlayer3D.new()
	p.bus = &"SFX"
	p.stream = load("res://audio/sfx/locker_rattle.wav")
	p.unit_size = 4.0
	p.max_distance = 30.0
	p.volume_db = -3.0
	p.position.y = 1.2
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	Sfx.caption_for("locker_rattle", global_position + Vector3.UP)
	var base := _door.rotation.y
	var tw := create_tween()
	for i in 9:
		tw.tween_property(_door, "rotation:y", base + deg_to_rad(randf_range(1.5, 4.0)) * (1.0 - i / 10.0), 0.04)
		tw.tween_property(_door, "rotation:y", base, 0.05)
	tw.tween_callback(func(): rattling = false)
	return true


func can_interact(a: Node) -> bool:
	return occupant == null and a is Player and not (a as Player).dead


func get_refusal(_a: Node) -> String:
	return "Occupied"


func interact(actor: Node) -> void:
	var p := actor as Player
	if p == null or occupant != null:
		return
	for k in get_tree().get_nodes_in_group("keeper"):
		k.call("on_player_hiding", self)
	occupant = p
	p.enter_hiding(self)
	view.current = true
	_swing(true)
	Events.noise.emit(global_position, 2.5, "locker")
	Events.toast.emit("Hiding. Press %s to come out." % Ux.glyph("interact"))
	super.interact(actor)


func leave(p: Player) -> void:
	if occupant != p:
		return
	occupant = null
	_swing(true)
	p.exit_hiding(outside_point())


func force_out(p: Player) -> void:
	if occupant == p:
		occupant = null
		_swing(true)
		p.hidden_in = null
		p.collider.disabled = false
		p.model.visible = true
		p.global_position = outside_point()
		p.cam.camera.current = true


func outside_point() -> Vector3:
	return global_transform * exit_offset


func _swing(_open: bool) -> void:
	if _audio:
		_audio.stream = Sfx.stream("res://audio/sfx2/locker_close.ogg" if occupant != null else "res://audio/sfx2/locker_open.ogg") if kind == "locker" else Sfx.stream("res://audio/foley/cloth_2.ogg")
	if _audio and _audio.stream:
		_audio.play()
	if _door == null:
		return
	var t := create_tween()
	t.tween_property(_door, "rotation:y", -1.2, 0.12)
	t.tween_property(_door, "rotation:y", 0.0, 0.14)   # Phase 6: the door slams shut faster
