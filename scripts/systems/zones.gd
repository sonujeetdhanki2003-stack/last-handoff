class_name Zones
extends RefCounted
## Floor-plan rectangles of each area (x0, x1, z0, z1): depth tracking, ambience.

const RECTS := {
	"shaft": [-4.0, 4.0, 0.0, 8.0],
	"corridor": [-1.6, 1.6, -22.0, 0.0],
	"generator": [-10.0, -1.6, -9.0, -1.0],
	"security": [1.6, 8.0, -11.0, -3.0],
	"storage": [-8.0, -1.6, -19.0, -12.0],
	"lab": [-6.0, 6.0, -34.0, -22.0],
	"archive": [1.6, 9.0, -21.5, -12.0],
	"crawlspace": [-18.0, -10.0, -6.4, -4.6],
	"deep": [-25.0, -18.0, -10.0, -1.5],
	"winch": [4.15, 10.0, 1.0, 7.0],   # v1.2: the lift winch room off the shaft
}


static func area_at(pos: Vector3) -> String:
	for k in RECTS:
		var r: Array = RECTS[k]
		if pos.x >= r[0] and pos.x <= r[1] and pos.z >= r[2] and pos.z <= r[3]:
			return k
	return ""
