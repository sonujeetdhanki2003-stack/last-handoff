extends Node
## Power-cut simulation helper. Two modes:
##   --mode=write : save the same path in a tight loop (counter++), printing each
##                  committed counter, until killed (kill -9 = a power cut)
##   --mode=check : load the path and print "LOAD source counter" (exit 0) or FAIL (exit 1)
const PATH := "user://stress_chain.json"

func _ready() -> void:
	var mode := Harness.get_arg("mode", "check")
	if mode == "write":
		var big := []
		for i in 400:
			big.append({"expedition": i, "member": "Member %d" % i, "message": "Don't trust the lights. ".repeat(4), "pos": [i * 0.1, 0.0, -i * 0.2]})
		var c := 0
		var last := SaveIO.load_json(PATH)
		if last["ok"]:
			c = int(last["data"].get("counter", 0))
		while true:
			c += 1
			if SaveIO.save_json(PATH, {"counter": c, "history": big}) == OK:
				printraw("SAVED %d\n" % c)
	else:
		var r := SaveIO.load_json(PATH)
		if r["ok"] and (r["data"].get("history", []) as Array).size() == 400:
			print("LOAD %s %d" % [r["source"], int(r["data"]["counter"])])
			get_tree().quit(0)
		else:
			print("FAIL %s" % r["error"])
			get_tree().quit(1)
