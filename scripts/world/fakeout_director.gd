class_name FakeoutDirector
extends Node
## v1.2 fake-out scares: a locker that rattles, a lamp that browns out, a distant thud,
## far-off footsteps, a vent that creaks. Nothing is there. The rules keep them fair:
##   * rare: never in the first FIRST_DELAY s, then at least MIN_GAP s apart (+ random)
##   * never while the Keeper is hunting (chase, lunge, grab, investigate, search,
##     waiting at a light, recoiling) and not for CALM_AFTER s after it was
##   * never when the Keeper is within KEEPER_CLEAR m of you, and the scare's spot is at
##     least SPOT_FROM_KEEPER m from the Keeper, so it never points at or away from it
##   * never while you hide, read, use a menu, or during the intro / an ending
##   * no noise event: the Keeper does not hear them, and the heartbeat stays silent
## so they only ever play while you are genuinely safe. The heartbeat never lies.

const FIRST_DELAY := 50.0
const MIN_GAP := 75.0
const GAP_JITTER := 45.0
const CALM_AFTER := 25.0
const KEEPER_CLEAR := 14.0
const SPOT_FROM_KEEPER := 12.0
const SPOT_MIN := 5.0
const SPOT_MAX := 16.0
const KINDS := ["locker", "flicker", "thud", "steps", "vent"]
const HUNTING := [Keeper.S.CHASE, Keeper.S.LUNGE, Keeper.S.GRAB, Keeper.S.INVESTIGATE, Keeper.S.SEARCH,
	Keeper.S.WAIT_LIGHT, Keeper.S.REPELLED, Keeper.S.RETREAT]
## Ceiling vents and ducts (the corridor vent the Keeper uses, the generator exhaust, room vents).
const VENTS := [Vector3(0.0, 3.1, -19.6), Vector3(0.0, 3.0, -8.0), Vector3(-6.0, 3.0, -5.5), Vector3(4.8, 2.9, -9.0),
	Vector3(-4.8, 2.9, -15.0), Vector3(0.0, 4.0, -27.0), Vector3(6.0, 3.0, 3.6)]
## Floor points for thuds and footsteps (behind walls is fine: they are far-off sounds).
const FLOOR := [Vector3(0.0, 0.5, -4.0), Vector3(0.0, 0.5, -11.0), Vector3(0.0, 0.5, -18.0), Vector3(-6.0, 0.5, -5.0),
	Vector3(5.0, 0.5, -7.0), Vector3(-5.0, 0.5, -15.5), Vector3(5.0, 0.5, -16.5), Vector3(0.0, 0.5, -28.0),
	Vector3(0.0, 0.5, 4.0), Vector3(7.0, 0.5, 4.0), Vector3(-14.0, 0.5, -5.5)]

var game: Node
var enabled := true
var clock := 0.0            ## seconds this expedition (pausable)
var next_at := FIRST_DELAY
var last_alert := -999.0    ## clock when the Keeper last hunted
var fired: Array = []       ## [clock, kind, spot] (tests, debug)
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "FakeoutDirector"
	rng.randomize()


## Pure rule (tested): may a fake-out play now?
static func allowed(clock_: float, next_at_: float, keeper_state: int, keeper_dist: float, since_alert: float, player_busy: bool) -> bool:
	if clock_ < FIRST_DELAY or clock_ < next_at_ or player_busy:
		return false
	if keeper_state in HUNTING or since_alert < CALM_AFTER:
		return false
	if keeper_state != Keeper.S.DORMANT and keeper_dist < KEEPER_CLEAR:
		return false
	return true


## Pure rule (tested): is this spot fair for a fake-out?
static func spot_ok(spot: Vector3, player_pos: Vector3, keeper_pos: Variant) -> bool:
	var d := Vector2(spot.x - player_pos.x, spot.z - player_pos.z).length()
	if d < SPOT_MIN or d > SPOT_MAX:
		return false
	if keeper_pos is Vector3 and Vector2(spot.x - keeper_pos.x, spot.z - keeper_pos.z).length() < SPOT_FROM_KEEPER:
		return false
	return true


func _player_busy() -> bool:
	var p: Player = game.get("player")
	if p == null or p.dead or p.hidden_in != null or not p.control_enabled:
		return true
	return Events.modal_open or game.get("ended") or game.get("ending") != null


func _keeper() -> Keeper:
	var k: Variant = game.get("keeper")
	return k if k != null and is_instance_valid(k) else null


func _process(delta: float) -> void:
	if game == null or not enabled or get_tree().paused:
		return
	clock += delta
	var k := _keeper()
	var st := k.state if k else Keeper.S.DORMANT
	if st in HUNTING:
		last_alert = clock
	if clock < next_at:
		return
	var p: Player = game.get("player")
	var kd := k.global_position.distance_to(p.global_position) if k and p else 999.0
	if not allowed(clock, next_at, st, kd, clock - last_alert, _player_busy()):
		return
	if try_fire():
		next_at = clock + MIN_GAP + rng.randf() * GAP_JITTER
	else:
		next_at = clock + 5.0   # nothing fair right now: look again shortly


## Pick a kind and a fair spot and play it. Returns false when nothing fits.
func try_fire(force_kind := "") -> bool:
	var p: Player = game.get("player")
	if p == null:
		return false
	var k := _keeper()
	var kp: Variant = k.global_position if k and k.state != Keeper.S.DORMANT else null
	var pp := p.global_position
	var kinds: Array = [force_kind] if force_kind != "" else KINDS.duplicate()
	if bool(Settings.get_value("access", "reduce_flashes")):
		kinds.erase("flicker")
	# shuffle
	for i in range(kinds.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = tmp
	for kind in kinds:
		var cands: Array = _candidates(kind, pp, kp)
		if cands.is_empty():
			continue
		var c: Variant = cands[rng.randi() % cands.size()]
		if _play(kind, c):
			var at: Vector3 = c.global_position if c is Node3D else c
			fired.append([clock, kind, at])
			return true
	return false


func _candidates(kind: String, pp: Vector3, kp: Variant) -> Array:
	var out: Array = []
	match kind:
		"locker":
			for s in get_tree().get_nodes_in_group("hiding_spots"):
				if s is HidingSpot and s.kind == "locker" and s.occupant == null and spot_ok(s.global_position, pp, kp):
					out.append(s)
		"flicker":
			for l in get_tree().get_nodes_in_group("powered_lights"):
				var pl := l as PoweredLight
				if pl and pl.is_on() and not pl.is_suppressed() and spot_ok(pl.global_position, pp, kp):
					out.append(pl)
		"vent":
			for v in VENTS:
				if spot_ok(v, pp, kp):
					out.append(v)
		_:
			for v in FLOOR:
				if spot_ok(v, pp, kp):
					out.append(v)
	return out


func _play(kind: String, c: Variant) -> bool:
	match kind:
		"locker":
			return (c as HidingSpot).rattle()
		"flicker":
			if (c as PoweredLight).brownout():
				Sfx.play_at("breaker", (c as Node3D).global_position, -18.0, 1.6, false)
				return true
			return false
		"thud":
			return Sfx.play_at("distant_thud", c, -6.0, rng.randf_range(0.8, 1.0)) != null
		"vent":
			return Sfx.play_at("vent_creak", c, -2.0, rng.randf_range(0.85, 1.1)) != null
		"steps":
			# four slow steps walking away from you, then nothing
			var dir := (Vector3(c.x, 0, c.z) - Vector3(game.player.global_position.x, 0, game.player.global_position.z)).normalized()
			for i in 4:
				var at: Vector3 = c + dir * 0.7 * i
				get_tree().create_timer(0.62 * i, false).timeout.connect(func():
					if is_inside_tree():
						Sfx.play_at("distant_steps", at, -4.0 - i * 2.0, rng.randf_range(0.9, 1.0), i == 0))
			return true
	return false
