extends Node3D
## In-game root: wires level, player, HUD and pause menu; puts the chain into the
## world (ChainDirector), spawns the Keeper, tracks depth, autosaves the run, and
## runs the end of an expedition: grab-and-fade -> handoff screen -> next member.

@onready var level: Level = $Level
@onready var player: Player = $Player
@onready var hud: Node = $HUD

var keeper: Keeper
var chain_director: ChainDirector
var nav: NavigationRegion3D
var ending: Node
var intro: IntroDirector
var debug_overlay: DebugOverlay
var threat_feedback: ThreatFeedback
var fakeouts: FakeoutDirector
var ended := false
var _area := ""
var _area_t := 0.0
var _save_t := 0.0


func _ready() -> void:
	add_to_group("game")   # Ux (focus loss, back button, pad unplugged) finds the expedition here
	var t := level.get_spawn()
	player.global_transform = Transform3D(Basis(), t.origin)
	player.cam.set_view(rad_to_deg(t.basis.get_euler().y), -10.0)
	player.cam.global_position = player.global_position + Vector3.UP * 1.55
	hud.bind_player(player)
	Events.expedition_ended.connect(_on_end)
	Events.player_died.connect(_on_died)
	Events.ending_started.connect(_on_ending)
	get_tree().paused = false
	if GameState.chain_mode:
		chain_director = ChainDirector.new()
		level.add_child(chain_director)
		chain_director.setup(level)
		_sync_objectives()
		if not GameState.resume_player.is_empty():
			player.from_state(GameState.resume_player)
			GameState.resume_player = {}
	elif GameState.chapter_run != "" and not GameState.resume_player.is_empty():
		player.from_state(GameState.resume_player)
		GameState.resume_player = {}
	if GameState.threat_enabled:
		if GameState.chapter_run != "" and GameState.chapter_keeper_at is Vector3:
			spawn_keeper(GameState.chapter_keeper_at)
		else:
			spawn_keeper()
		if GameState.chapter_run != "" and GameState.chapter_wake >= 0.0:
			# a chapter starts with the power already on: it heard it, and it comes
			get_tree().create_timer(GameState.chapter_wake, false).timeout.connect(_chapter_wake)
		# v1.2: heartbeat + vibration (real distance cue) and the fake-out director
		threat_feedback = ThreatFeedback.new()
		threat_feedback.game = self
		add_child(threat_feedback)
		fakeouts = FakeoutDirector.new()
		fakeouts.game = self
		add_child(fakeouts)
	debug_overlay = DebugOverlay.new()
	debug_overlay.game = self
	add_child(debug_overlay)
	GameState.grid.circuit_changed.connect(_on_circuit_pa)
	_hook_progress()
	if GameState.play_intro:
		GameState.play_intro = false
		GameState.set_flag("intro_shown")
		intro = IntroDirector.new()
		add_child(intro)
		intro.play(self, GameState.expedition_number > Lore.FIRST_EXPEDITION or not GameState.chain_mode)
	elif not GameState.get_flag("intro_shown"):
		GameState.set_flag("intro_shown")
		if GameState.chapter_run != "" and not Harness.has("shot") and DisplayServer.get_name() != "headless":
			var c: Dictionary = Progress.CHAPTERS[maxi(0, Progress.chapter_index(GameState.chapter_run))]
			Ux.show_title_card("Chapter %s" % c["num"], str(c["title"]), "HALDEN DEEP  //  LEVEL B2", 1.6)
		elif not Harness.has("shot") and DisplayServer.get_name() != "headless":
			Ux.show_title_card("Expedition %d" % GameState.expedition_number, GameState.member_name if GameState.member_name != "" else "Field team", "HALDEN DEEP  //  LEVEL B2", 1.6)


# ----------------------------------------------------------------- v1.2 progress
func _chapter_wake() -> void:
	if keeper and is_instance_valid(keeper) and keeper.state == Keeper.S.DORMANT and not ended:
		keeper.wake()


var _hunted_at := -999.0
func _hook_progress() -> void:
	Progress.unlock("descent")
	GameState.grid.circuit_changed.connect(_on_circuit_progress)
	GameState.flag_changed.connect(_on_flag_progress)
	GameState.inventory.item_added.connect(_on_item_progress)
	Events.area_entered.connect(_on_area_progress)
	Events.ending_started.connect(_on_ending_progress)
	Events.expedition_ended.connect(_on_end_progress)
	if keeper:
		keeper.state_changed.connect(_on_keeper_progress)


func _on_circuit_progress(id: String, powered: bool) -> void:
	if powered and id == "aux":
		Progress.unlock("generator")
	elif powered and id == "lab":
		Progress.unlock("lab_power")
	Progress.check_world()


func _on_flag_progress(flag: String, _v: Variant) -> void:
	if flag == "lab_entered":
		Progress.unlock("lab_open")
	elif flag == "doc_lift_log":
		Progress.unlock("engineer")
	elif flag.begins_with("log_") and Legacy.mara_tapes_found() >= Lore.MARA_TAPES.size():
		Progress.unlock("tapes")


func _on_item_progress(id: String, _q: int) -> void:
	if id == "research_drive":
		Progress.unlock("drive")
		Progress.check_world()


func _on_area_progress(a: String) -> void:
	if a == "deep":
		Progress.unlock("camp")
	Progress.check_world()


func _on_ending_progress(_id: String) -> void:
	Progress.unlock("ending")


func _on_end_progress(reason: String) -> void:
	if reason == "extracted" and GameState.inventory.has("research_drive"):
		Progress.unlock("extracted")


func _on_keeper_progress(s: int) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if s == Keeper.S.REPELLED:
		Progress.unlock("repel")
	elif s in [Keeper.S.CHASE, Keeper.S.SEARCH]:
		_hunted_at = now
	elif s == Keeper.S.PATROL and player.hidden_in != null and now - _hunted_at < 40.0:
		Progress.unlock("hide")


func _on_circuit_pa(id: String, powered: bool) -> void:
	if id == "lab" and powered and not GameState.get_flag("pa_lab_done") and GameState.threat_enabled and not ended and ending == null:
		GameState.set_flag("pa_lab_done")
		get_tree().create_timer(2.0).timeout.connect(func(): if ending == null and not ended: Sfx.play_pa("pa_lab"))


func spawn_keeper(at := NavBaker.LAIR) -> Keeper:
	if nav == null:
		nav = NavBaker.bake(level)
	keeper = Keeper.new()
	keeper.name = "Keeper"
	add_child(keeper)
	keeper.global_position = at
	keeper.lair = at
	keeper.setup(player, NavBaker.PATROL)
	return keeper


## Objectives the world already satisfies (an earlier member did them).
func _sync_objectives() -> void:
	var o := GameState.objectives
	if GameState.get_world("keypad_lab").get("solved", false) or GameState.get_world("door_lab").get("code_unlocked", false):
		o.complete("code")
	if int(GameState.get_flag("fuses_installed", 0)) >= GameState.FUSES_NEEDED:
		o.set_progress("fuses", GameState.FUSES_NEEDED)
		o.complete("fuses")
	if GameState.get_world("door_lab").get("open", false):
		o.complete("enter_lab")
		o.reveal("drive")
	if Legacy.decision("drive") == "destroyed":
		o.reveal("drive")
		o.complete("drive")
		o.reveal("extract")


func _physics_process(delta: float) -> void:
	if ended:
		return
	_area_t -= delta
	if _area_t <= 0.0:
		_area_t = 0.4
		var a := Zones.area_at(player.global_position)
		if a != "" and a != _area:
			_area = a
			GameState.note_area(a)
			Events.area_entered.emit(a)
			autosave()
	_save_t += delta
	if _save_t > 60.0:
		autosave()


func autosave() -> void:
	_save_t = 0.0
	if GameState.chain_mode and not ended and not player.dead:
		Legacy.save_run(player.to_state())


func _on_end(reason: String) -> void:
	if ended:
		return
	ended = true
	player.set_control(false)
	if GameState.chain_mode:
		Legacy.end_expedition(reason, player.global_position, GameState.deepest)
		await hud.fade_to_black(1.2)
		hud.show_handoff()
	else:
		hud.show_end(reason)


func _on_died(cause: String) -> void:
	if ended:
		return
	ended = true
	var reason := "died" if cause == "keeper" else "injured"
	if GameState.chain_mode:
		Legacy.end_expedition(reason, player.global_position, GameState.deepest)
	# grab-and-fade: a beat of the hands on you, then black. No gore.
	hud.death_flash(cause)
	await hud.fade_to_black(1.8 if cause == "keeper" else 1.2)
	if GameState.chain_mode:
		hud.show_handoff()
	else:
		hud.show_end(reason)


func _on_ending(id: String) -> void:
	if ending != null:
		return   # one ending per expedition, even if a second trigger fires mid-sequence
	if ended and id != "break":
		return
	ended = true
	player.set_control(false)
	if GameState.chain_mode and id != "break":
		Legacy.end_expedition(id, player.global_position, GameState.deepest)
		Legacy.commit_handoff("", "", "", "", true)
	ending = EndingDirector.new()
	add_child(ending)
	await ending.play(id, self)
	if GameState.chain_mode:
		Legacy.reach_ending(id)
	hud.show_end_card(id)
