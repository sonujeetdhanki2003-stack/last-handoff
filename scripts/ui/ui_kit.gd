class_name UIKit
extends RefCounted
## The game's one visual language: a worn field terminal. Dark gunmetal panels with
## amber corner brackets and faint scanlines, condensed caps, mono read-outs, amber
## focus. Paper (notes, handoff preview) uses bone paper and ink.

const AMBER := Color(0.96, 0.66, 0.24)
const AMBER_DIM := Color(0.96, 0.66, 0.24, 0.55)
const TEXT := Color(0.87, 0.86, 0.81)
const DIM := Color(0.53, 0.55, 0.53)
const FAINT := Color(0.36, 0.38, 0.37)
const RED := Color(0.95, 0.34, 0.26)
const GREEN := Color(0.45, 0.93, 0.6)
const CYAN := Color(0.45, 0.8, 0.9)
const PANEL := Color(0.035, 0.04, 0.045, 0.93)
const BG := Color(0.016, 0.018, 0.021, 1.0)
const PAPER := Color(0.85, 0.81, 0.71)
const INK := Color(0.13, 0.12, 0.1)
const LINE := Color(1, 1, 1, 0.09)

static var _fonts := {}
static var _icons := {}


static func font(kind := "ui") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var path := {
		"ui": "res://assets/fonts/BarlowCondensed-Medium.ttf",
		"ui_bold": "res://assets/fonts/BarlowCondensed-SemiBold.ttf",
		"title": "res://assets/fonts/Oswald-Variable.ttf",
		"title_light": "res://assets/fonts/Oswald-Variable.ttf",
		"mono": "res://assets/fonts/IBMPlexMono-Regular.ttf",
		"mono_bold": "res://assets/fonts/IBMPlexMono-Bold.ttf",
		"typed": "res://assets/fonts/SpecialElite-Regular.ttf",
		"hand": "res://assets/fonts/Caveat-Variable.ttf",
	}.get(kind, "res://assets/fonts/BarlowCondensed-Medium.ttf")
	var f: Font = load(path)
	if kind == "title" or kind == "title_light":
		var v := FontVariation.new()
		v.base_font = f
		v.variation_opentype = {"wght": 600 if kind == "title" else 300}
		v.spacing_glyph = 2 if kind == "title" else 1
		f = v
	_fonts[kind] = f
	return f


static func label(text: String, size := 26, color := TEXT, kind := "ui") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func shadowed(l: Label, a := 0.85) -> Label:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, a))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 6)
	return l


static func panel_style(bg := PANEL, border := LINE, radius := 2, pad := 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.75
	s.content_margin_bottom = pad * 0.75
	s.anti_aliasing = false
	return s


## A plain panel (kept for the older call sites; same look as a terminal panel).
static func panel(bg := PANEL, pad := 18) -> PanelContainer:
	var p := TermPanel.new()
	p.add_theme_stylebox_override("panel", panel_style(bg, LINE, 2, pad))
	if bg.v > 0.5:
		p.brackets = false
		p.scanlines = false
	return p


## A framed terminal panel with corner brackets and a code line in the top edge.
static func term_panel(code := "", pad := 26) -> TermPanel:
	var p := TermPanel.new()
	p.code = code
	p.add_theme_stylebox_override("panel", panel_style(PANEL, LINE, 2, pad))
	return p


static func button(text: String, size := 30) -> Button:
	var b := TermButton.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_ALL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b


## Header block: small mono code line, big title, amber rule.
static func header(title: String, code := "", size := 54) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	if code != "":
		v.add_child(label(code.to_upper(), 16, AMBER_DIM, "mono"))
	v.add_child(label(title.to_upper(), size, TEXT, "title"))
	v.add_child(rule(AMBER, 2, 120))
	return v


static func rule(c := LINE, h := 1, w := 0) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.custom_minimum_size = Vector2(w, h)
	if w > 0:
		r.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func spacer(h := 12.0, w := 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func expand() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Full-screen dark backdrop with film grain, scanlines and a vignette.
static func backdrop(alpha := 0.82) -> Control:
	var b := ScreenBackdrop.new()
	b.alpha = alpha
	return b


## A row of button prompts that follows the input device: [["ui_accept","Select"],...]
static func hint_bar(pairs: Array) -> HintBar:
	var h := HintBar.new()
	h.pairs = pairs
	return h


## Wires focus neighbours so the d-pad/stick walks the given controls in order
## (vertical list by default; wraps around).
static func chain_focus(ctrls: Array, horizontal := false) -> void:
	var list: Array = ctrls.filter(func(c): return c is Control and (c as Control).focus_mode != Control.FOCUS_NONE)
	var n := list.size()
	for i in n:
		var c: Control = list[i]
		var prev: Control = list[(i - 1 + n) % n]
		var nxt: Control = list[(i + 1) % n]
		if horizontal:
			c.focus_neighbor_left = c.get_path_to(prev)
			c.focus_neighbor_right = c.get_path_to(nxt)
		else:
			c.focus_neighbor_top = c.get_path_to(prev)
			c.focus_neighbor_bottom = c.get_path_to(nxt)
		c.focus_previous = c.get_path_to(prev)
		c.focus_next = c.get_path_to(nxt)


static func _icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var img: Image
	match id:
		"check_on", "check_off":
			img = Image.create(46, 24, false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
			var on := id == "check_on"
			var track := Color(0.96, 0.66, 0.24, 0.85) if on else Color(1, 1, 1, 0.16)
			for y in range(4, 20):
				for x in range(2, 44):
					img.set_pixel(x, y, track)
			var kx := 26 if on else 4
			for y in range(2, 22):
				for x in range(kx, kx + 16):
					img.set_pixel(x, y, Color(0.06, 0.06, 0.06) if on else Color(0.8, 0.8, 0.77))
		"grabber", "grabber_hl":
			img = Image.create(8, 26, false, Image.FORMAT_RGBA8)
			img.fill(TEXT if id == "grabber" else AMBER)
		"arrow":
			img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
			for y in range(5, 11):
				for x in range(8 - (10 - y), 8 + (10 - y) + 1):
					if x >= 0 and x < 16:
						img.set_pixel(x, y, DIM)
		_:
			img = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var t := ImageTexture.create_from_image(img)
	_icons[id] = t
	return t


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font("ui")
	t.default_font_size = 26
	# Buttons: flat, a hairline on the left; amber bar + tint when focused/hovered.
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.025)
	normal.border_color = Color(1, 1, 1, 0.1)
	normal.border_width_left = 2
	normal.content_margin_left = 22
	normal.content_margin_right = 18
	normal.content_margin_top = 6
	normal.content_margin_bottom = 7
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.96, 0.66, 0.24, 0.13)
	hover.border_color = AMBER
	hover.border_width_left = 4
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.96, 0.66, 0.24, 0.28)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0, 0, 0, 0)
	disabled.border_color = Color(1, 1, 1, 0.04)
	var toggled := normal.duplicate() as StyleBoxFlat
	toggled.bg_color = Color(0.96, 0.66, 0.24, 0.08)
	toggled.border_color = AMBER_DIM
	toggled.border_width_left = 4
	for cls in ["Button", "OptionButton", "CheckButton", "CheckBox", "MenuButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed if cls != "CheckButton" else normal)
		t.set_stylebox("hover_pressed", cls, pressed if cls != "CheckButton" else hover)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color(1, 0.86, 0.6))
		t.set_color("font_focus_color", cls, Color(1, 0.86, 0.6))
		t.set_color("font_pressed_color", cls, AMBER)
		t.set_color("font_hover_pressed_color", cls, AMBER)
		t.set_color("font_disabled_color", cls, Color(0.38, 0.39, 0.38))
	t.set_stylebox("pressed", "Button", toggled)
	t.set_icon("checked", "CheckButton", _icon("check_on"))
	t.set_icon("unchecked", "CheckButton", _icon("check_off"))
	t.set_icon("arrow", "OptionButton", _icon("arrow"))
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "PopupMenu", panel_style(Color(0.04, 0.045, 0.05, 0.98), AMBER_DIM, 2, 10))
	t.set_stylebox("hover", "PopupMenu", hover)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color(1, 0.86, 0.6))
	t.set_font_size("font_size", "PopupMenu", 24)
	t.set_stylebox("panel", "TooltipPanel", panel_style(Color(0.04, 0.045, 0.05, 0.97), AMBER_DIM, 2, 10))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 20)
	# Sliders: a thin track, amber fill, a small upright grabber.
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(1, 1, 1, 0.12)
	slider_bg.content_margin_top = 2
	slider_bg.content_margin_bottom = 2
	var slider_fill := slider_bg.duplicate() as StyleBoxFlat
	slider_fill.bg_color = AMBER_DIM
	var slider_fill_hl := slider_bg.duplicate() as StyleBoxFlat
	slider_fill_hl.bg_color = AMBER
	t.set_stylebox("slider", "HSlider", slider_bg)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill_hl)
	t.set_icon("grabber", "HSlider", _icon("grabber"))
	t.set_icon("grabber_highlight", "HSlider", _icon("grabber_hl"))
	t.set_stylebox("focus", "HSlider", StyleBoxEmpty.new())
	# Progress bars
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(1, 1, 1, 0.1)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = AMBER
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	t.set_font_size("font_size", "ProgressBar", 1)
	# Text entry
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0, 0, 0, 0.45)
	le.border_color = Color(1, 1, 1, 0.14)
	le.set_border_width_all(1)
	le.content_margin_left = 12
	le.content_margin_right = 12
	var le_f := le.duplicate() as StyleBoxFlat
	le_f.border_color = AMBER
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le_f)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.5, 0.5, 0.48, 0.7))
	t.set_color("caret_color", "LineEdit", AMBER)
	# Scrollbars: thin, amber when grabbed
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(1, 1, 1, 0.22)
	var grab_h := grab.duplicate() as StyleBoxFlat
	grab_h.bg_color = AMBER_DIM
	t.set_stylebox("scroll", "VScrollBar", sb)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_h)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_h)
	# Tabs
	var tab_sel := StyleBoxFlat.new()
	tab_sel.bg_color = Color(0.96, 0.66, 0.24, 0.12)
	tab_sel.border_color = AMBER
	tab_sel.border_width_bottom = 3
	tab_sel.content_margin_left = 22
	tab_sel.content_margin_right = 22
	tab_sel.content_margin_top = 6
	tab_sel.content_margin_bottom = 8
	var tab_un := tab_sel.duplicate() as StyleBoxFlat
	tab_un.bg_color = Color(0, 0, 0, 0)
	tab_un.border_color = Color(1, 1, 1, 0.12)
	tab_un.border_width_bottom = 1
	for cls in ["TabBar", "TabContainer"]:
		t.set_stylebox("tab_selected", cls, tab_sel)
		t.set_stylebox("tab_unselected", cls, tab_un)
		t.set_stylebox("tab_hovered", cls, tab_un)
		t.set_stylebox("tab_focus", cls, StyleBoxEmpty.new())
		t.set_color("font_selected_color", cls, AMBER)
		t.set_color("font_unselected_color", cls, DIM)
		t.set_color("font_hovered_color", cls, TEXT)
		t.set_font("font", cls, font("ui_bold"))
		t.set_font_size("font_size", cls, 26)
	t.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	return t
