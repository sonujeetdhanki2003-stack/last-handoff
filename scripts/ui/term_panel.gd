class_name TermPanel
extends PanelContainer
## Gunmetal panel with amber corner brackets, faint scanlines and an optional
## code line cut into the top edge ("HD-B2 // FIELD TERMINAL 07").

@export var code := ""
@export var brackets := true
@export var scanlines := true


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if scanlines:
		var y := 2.0
		while y < size.y:
			draw_line(Vector2(1, y), Vector2(size.x - 1, y), Color(1, 1, 1, 0.018), 1.0)
			y += 3.0
	if brackets:
		var L := 18.0
		var c := UIKit.AMBER
		var w := 2.0
		for p in [[r.position, Vector2(1, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 1)],
				[Vector2(r.position.x, r.end.y), Vector2(1, -1)], [r.end, Vector2(-1, -1)]]:
			var o: Vector2 = p[0]
			var d: Vector2 = p[1]
			draw_line(o, o + Vector2(L * d.x, 0), c, w)
			draw_line(o, o + Vector2(0, L * d.y), c, w)
	if code != "":
		var f := UIKit.font("mono")
		var fs := 14
		var tw := f.get_string_size(code, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_rect(Rect2(30, -9, tw + 16, 18), UIKit.BG)
		draw_string(f, Vector2(38, 5), code, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIKit.AMBER_DIM)
