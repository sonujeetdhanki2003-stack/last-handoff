class_name ScreenBackdrop
extends Control
## Full-screen dark backdrop for menus: a vertical darkening, scanlines, a
## vignette and slowly crawling film grain.

var alpha := 0.82
var grain := true
var _t := 0.0
var _noise: ImageTexture
var _vig: GradientTexture2D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var img := Image.create(256, 256, false, Image.FORMAT_LA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in 256:
		for x in 256:
			var v := rng.randf()
			img.set_pixel(x, y, Color(v, v, v, 0.06 if v > 0.5 else 0.03))
	_noise = ImageTexture.create_from_image(img)
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	if grain and is_visible_in_tree():
		_t += delta
		if int(_t * 12.0) != int((_t - delta) * 12.0):
			queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.012, 0.014, 0.017, alpha))
	if grain and _noise:
		var off := Vector2(fmod(_t * 731.0, 256.0), fmod(_t * 377.0, 256.0)).floor()
		draw_texture_rect(_noise, Rect2(-off, size + Vector2(256, 256)), true)
	var y := 0.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.16), 1.0)
		y += 3.0
	if _vig == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.0))
		g.add_point(0.6, Color(0, 0, 0, 0.12))
		g.set_color(g.get_point_count() - 1, Color(0, 0, 0, 0.75))
		_vig = GradientTexture2D.new()
		_vig.gradient = g
		_vig.fill = GradientTexture2D.FILL_RADIAL
		_vig.fill_from = Vector2(0.5, 0.5)
		_vig.fill_to = Vector2(1.05, 1.05)
		_vig.width = 128
		_vig.height = 128
	draw_texture_rect(_vig, Rect2(Vector2.ZERO, size), false)
