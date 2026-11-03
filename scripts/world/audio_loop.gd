class_name AudioLoop
extends RefCounted
## Marks a WAV as a seamless forward loop (our ambience is generated to loop exactly).

static func make(s: AudioStream) -> AudioStream:
	var w := s as AudioStreamWAV
	if w and w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(round(w.get_length() * w.mix_rate))
	return s
