class_name SegmentBar
extends Control
## A segmented meter (battery cells, the lift counter...). Same value/max_value
## interface as a ProgressBar.

var value := 1.0:
	set(v):
		value = v
		queue_redraw()
var max_value := 1.0
var step := 0.001
var show_percentage := false
var segments := 10
var color := UIKit.AMBER
var low_color := UIKit.RED
var low_at := 0.25
var gap := 3.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var f := clampf(value / maxf(max_value, 0.0001), 0.0, 1.0)
	var w := (size.x - gap * (segments - 1)) / segments
	var lit := f * segments
	var c := low_color if f <= low_at else color
	for i in segments:
		var r := Rect2(i * (w + gap), 0, w, size.y)
		draw_rect(r, Color(1, 1, 1, 0.1))
		var k := clampf(lit - i, 0.0, 1.0)
		if k > 0.0:
			draw_rect(Rect2(r.position, Vector2(w * k, size.y)), c)
