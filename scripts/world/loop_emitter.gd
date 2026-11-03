extends AudioStreamPlayer3D
## Positional ambience that loops (machinery behind a wall, wind in the shaft).

func _ready() -> void:
	if stream:
		stream = AudioLoop.make(stream)
	if not playing:
		play(randf() * 4.0)
