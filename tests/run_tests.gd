extends Node
## Headless test runner.
##   godot --headless --path . res://tests/run_tests.tscn                 (all)
##   godot --headless --path . res://tests/run_tests.tscn -- --tests=inventory,doors
## Each test file is res://tests/test_<name>.gd extending TestCase and gets a
## fresh expedition + an empty 3D sandbox. Prints PASS/FAIL per check, a summary
## per system, and exits with code 0 only when everything passed.

const ALL := ["inventory", "power", "objectives", "battery", "settings", "interaction",
	"doors", "switches", "puzzles", "movement", "camera", "playthrough", "world",
	"save", "vitals", "threat", "hiding", "hazards", "handoff", "decisions", "endings", "encounter", "ui", "polish"]
## Phase 1-3 systems are tested without the Keeper and the hazards (peaceful).
const PEACEFUL := ["inventory", "power", "objectives", "battery", "settings", "interaction",
	"doors", "switches", "puzzles", "movement", "camera", "playthrough", "world"]

var sandbox: Node3D
var _fails := 0
var _passes := 0
var _current := ""
var results := {}


class ScriptErrorCounter extends Logger:
	var count := 0
	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			count += 1

var _errs := ScriptErrorCounter.new()


func _ready() -> void:
	OS.add_logger(_errs)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var names: Array = ALL
	var arg := Harness.get_arg("tests", "")
	if arg != "":
		names = arg.split(",")
	_run(names)


func _run(names: Array) -> void:
	await get_tree().process_frame
	for n in names:
		_current = n
		_fails = 0
		_passes = 0
		GameState.new_expedition(1234)
		GameState.threat_enabled = not PEACEFUL.has(n)
		EndingDirector.time_scale = 8.0
		Legacy.use_path("user://test_chain_%s.json" % n)
		Events.set_modal(false)
		get_tree().paused = false
		sandbox = Node3D.new()
		sandbox.name = "Sandbox_" + n
		add_child(sandbox)
		var script: Script = load("res://tests/test_%s.gd" % n)
		if script == null:
			fail("could not load test_%s.gd" % n)
		else:
			var tc: TestCase = script.new()
			tc.t = self
			print("\n=== %s ===" % n.to_upper())
			var before := _errs.count
			await tc.run()
			if _errs.count > before:
				fail("%d script error(s) during the suite (it may have stopped early)" % (_errs.count - before))
		results[n] = [_passes, _fails]
		print("--- %s: %s (%d passed, %d failed)" % [n, "PASS" if _fails == 0 else "FAIL", _passes, _fails])
		sandbox.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	var total_f := 0
	var total_p := 0
	print("\n================ SUMMARY ================")
	for n in results:
		total_p += results[n][0]
		total_f += results[n][1]
		print("%-14s %s  %3d checks" % [n, "PASS" if results[n][1] == 0 else "FAIL", results[n][0] + results[n][1]])
	print("TOTAL: %s  (%d passed, %d failed)" % ["PASS" if total_f == 0 else "FAIL", total_p, total_f])
	get_tree().quit(0 if total_f == 0 else 1)


func check(cond: bool, msg: String) -> bool:
	if cond:
		_passes += 1
		print("  PASS  ", msg)
	else:
		_fails += 1
		print("  FAIL  ", msg)
	return cond


func eq(a: Variant, b: Variant, msg: String) -> bool:
	var ok: bool = a == b
	if not ok:
		msg += "   (got %s, expected %s)" % [str(a), str(b)]
	return check(ok, msg)


func near(a: float, b: float, eps: float, msg: String) -> bool:
	return check(absf(a - b) <= eps, msg + "   (got %.4f, expected %.4f)" % [a, b])


func fail(msg: String) -> void:
	check(false, msg)


func frames(n := 1) -> void:
	for i in n:
		await get_tree().process_frame


func physics(n := 2) -> void:
	for i in n:
		await get_tree().physics_frame
