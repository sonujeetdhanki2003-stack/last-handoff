class_name EcgTrace
extends Control
## The suit's heart monitor: a scrolling pulse trace. Calm and green when steady,
## faster and amber when hurt or running, fast and red when critical.

var bpm := 72.0
var color := UIKit.GREEN
var _t := 0.0
var _buf := PackedFloat32Array()
const N := 90


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buf.resize(N)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta * bpm / 60.0
	var ph := fmod(_t, 1.0)
	var y := 0.0
	if ph < 0.06:
		y = sin(ph / 0.06 * PI) * 0.15
	elif ph < 0.12:
		y = 0.0
	elif ph < 0.14:
		y = -0.25
	elif ph < 0.17:
		y = 1.0
	elif ph < 0.2:
		y = -0.45
	elif ph < 0.34 and ph > 0.26:
		y = sin((ph - 0.26) / 0.08 * PI) * 0.25
	for i in N - 1:
		_buf[i] = _buf[i + 1]
	_buf[N - 1] = y
	queue_redraw()


func _draw() -> void:
	var pts := PackedVector2Array()
	var mid := size.y * 0.58
	for i in N:
		pts.append(Vector2(size.x * i / (N - 1), mid - _buf[i] * size.y * 0.5))
	draw_polyline(pts, Color(color, 0.25), 4.0, true)
	draw_polyline(pts, color, 1.6, true)
	draw_circle(pts[N - 1], 2.5, color)
