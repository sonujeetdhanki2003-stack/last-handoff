class_name HintBar
extends HBoxContainer
## A row of prompts like "[A] Select   [B] Back", following the input device.

var pairs: Array = []
var size_px := 20


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for p in pairs:
		var g := GlyphBadge.new(str(p[0]), size_px - 2)
		add_child(g)
		var l := UIKit.label(str(p[1]).to_upper(), size_px, UIKit.DIM, "ui_bold")
		add_child(l)
		add_child(UIKit.spacer(0, 14))
