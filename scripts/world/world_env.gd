@tool
extends WorldEnvironment
## Dark facility environment. Effects scale with the Quality setting:
## Low = no SSAO / volumetric fog, Medium = SSAO, High = SSAO + SSIL + volumetric fog.

@export var ambient_energy := 0.35
@export var fog_density := 0.025


func _ready() -> void:
	if environment == null:
		environment = _make_env()
	if not Engine.is_editor_hint():
		Settings.changed.connect(func(s, _k, _v): if s == "video": apply_quality())
		apply_quality()


func _make_env() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.005, 0.006, 0.008)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.32, 0.38, 0.48)
	e.ambient_light_energy = ambient_energy
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.0
	e.ssao_enabled = true
	e.ssao_radius = 0.7
	e.ssao_intensity = 2.0
	e.ssao_power = 1.4
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.0
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_light_color = Color(0.03, 0.035, 0.045)
	e.fog_density = 0.035
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = fog_density
	e.volumetric_fog_albedo = Color(0.7, 0.72, 0.75)
	e.volumetric_fog_length = 32.0
	e.volumetric_fog_ambient_inject = 0.05
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.06
	e.adjustment_saturation = 0.85
	return e


func apply_quality() -> void:
	if environment == null:
		return
	var q: int = Settings.get_value("video", "quality")
	var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	environment.ssao_enabled = q >= 1 and not compat
	environment.ssil_enabled = q >= 2 and not compat
	environment.volumetric_fog_enabled = q >= 2 and not compat
	environment.glow_enabled = true
	if Harness.has("nossao"):
		environment.ssao_enabled = false
	if Harness.has("nossil"):
		environment.ssil_enabled = false
	if Harness.has("nofog"):
		environment.volumetric_fog_enabled = false
	environment.adjustment_brightness = Settings.get_value("video", "brightness")
	# Compatibility renderer has no volumetric fog: lean on depth fog instead.
	environment.fog_density = 0.035 if (q >= 2 and not compat) else 0.05
