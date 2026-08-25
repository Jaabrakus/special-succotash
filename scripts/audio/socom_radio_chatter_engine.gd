class_name SocomRadioChatterEngine
extends RefCounted

## Authentic SOCOM 2 Tactical Radio Chatter & SITREP Audio System
## Ported from reCOM (zSound/zsnd_csnd.cpp, zSpeech, uisounds.rdr)

signal callout_dispatched(callout_id: StringName, callsign: String, text: String)

enum CalloutType {
	BOMB_PLANTED,
	BOMB_DEFUSED,
	TARGET_DOWN,
	FRAG_OUT,
	FLASHBANG_OUT,
	RELOADING,
	COVER_ME,
	HOLD_POSITION,
	FOLLOW_ME,
	ROGER_THAT,
	NEGATIVE,
}

const CALLOUT_DATA: Dictionary = {
	&"bomb_planted": {"text": "Bomb has been planted!", "priority": 100, "tone_pitch": 1.15},
	&"bomb_defused": {"text": "Bomb defused. Good work.", "priority": 100, "tone_pitch": 1.25},
	&"target_down": {"text": "Target eliminated / Tango down.", "priority": 70, "tone_pitch": 1.05},
	&"frag_out": {"text": "Frag out! Take cover!", "priority": 85, "tone_pitch": 1.10},
	&"flashbang_out": {"text": "Flashbang! Cover eyes!", "priority": 85, "tone_pitch": 1.10},
	&"reloading": {"text": "Reloading! Cover me!", "priority": 60, "tone_pitch": 0.95},
	&"cover_me": {"text": "Cover me! Moving up!", "priority": 60, "tone_pitch": 1.00},
	&"hold_position": {"text": "Hold position. Stay frosty.", "priority": 50, "tone_pitch": 0.90},
	&"follow_me": {"text": "On me. Follow my lead.", "priority": 50, "tone_pitch": 1.00},
	&"roger_that": {"text": "Roger that. Moving out.", "priority": 40, "tone_pitch": 1.00},
	&"negative": {"text": "Negative. Cannot comply.", "priority": 40, "tone_pitch": 0.85},
}

static var _is_initialized: bool = false
static var _key_in_stream: AudioStreamWAV
static var _squelch_out_stream: AudioStreamWAV
static var _callout_streams: Dictionary = {}
static var _last_callout_time: float = -99.0
static var _min_callout_interval: float = 0.85


static func _init_streams() -> void:
	if _is_initialized:
		return
	_key_in_stream = _build_key_in_stream()
	_squelch_out_stream = _build_squelch_stream()
	for id in CALLOUT_DATA:
		var pitch: float = float(CALLOUT_DATA[id].get("tone_pitch", 1.0))
		_callout_streams[id] = _build_voice_pulse_stream(pitch)
	_is_initialized = true


static func play_callout(
	tree: SceneTree,
	callout_id: StringName,
	callsign: String = "SPECTRE",
	force: bool = false
) -> void:
	_init_streams()
	var current_time := float(Time.get_ticks_msec()) / 1000.0
	if not force and current_time - _last_callout_time < _min_callout_interval:
		return
	_last_callout_time = current_time

	var data: Dictionary = CALLOUT_DATA.get(callout_id, {})
	var text: String = data.get("text", "Radio transmission.")

	# Dispatch signal / notification for SITREP HUD overlay
	var root := tree.root if tree != null else null
	if root != null:
		var hud := root.get_node_or_null("GameplayHUD/SocomSitrepHudOverlay")
		if hud != null and hud.has_method("add_sitrep_message"):
			hud.call("add_sitrep_message", callsign, text)

	# Play VHF Radio Key-In Beep + Callout Stream + Squelch Release
	if tree != null and root != null:
		var player := AudioStreamPlayer.new()
		player.bus = &"Effects" if AudioServer.get_bus_index(&"Effects") >= 0 else &"Master"
		player.stream = _key_in_stream
		player.volume_db = 0.0
		root.add_child(player)
		player.play()

		# Play Voice Callout after key-in click (40ms delay)
		var t := root.create_tween()
		t.tween_interval(0.05)
		t.tween_callback(func():
			if not is_instance_valid(player):
				return
			player.stream = _callout_streams.get(callout_id, _key_in_stream)
			player.volume_db = 1.0
			player.play()
		)
		t.tween_interval(0.28)
		t.tween_callback(func():
			if not is_instance_valid(player):
				return
			player.stream = _squelch_out_stream
			player.volume_db = -1.0
			player.play()
		)
		t.tween_interval(0.12)
		t.tween_callback(func():
			if is_instance_valid(player):
				player.queue_free()
		)


static func _build_key_in_stream() -> AudioStreamWAV:
	# Authentic VHF radio key-in chirp (1350Hz tone pulse)
	var sample_rate := 22050
	var duration := 0.045
	var frame_count := int(sample_rate * duration)
	var stream := _new_mono_stream(sample_rate, frame_count)
	var buffer := stream.data
	for i in range(frame_count):
		var t := float(i) / float(sample_rate)
		var env := sin(clampf(t / duration, 0.0, 1.0) * PI)
		var beep := sin(t * TAU * 1350.0) * 0.70 * env
		var click := (randf() * 2.0 - 1.0) * 0.40 * exp(-t * 120.0)
		var val := clampf(beep + click, -1.0, 1.0)
		buffer.encode_s16(i * 2, int(val * 32767.0))
	stream.data = buffer
	return stream


static func _build_squelch_stream() -> AudioStreamWAV:
	# Authentic VHF radio key-out static burst ("ksssh-click")
	var sample_rate := 22050
	var duration := 0.095
	var frame_count := int(sample_rate * duration)
	var stream := _new_mono_stream(sample_rate, frame_count)
	var buffer := stream.data
	for i in range(frame_count):
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 32.0)
		var noise := (randf() * 2.0 - 1.0) * 0.75 * env
		var pop := sin(t * TAU * 380.0) * 0.45 * exp(-t * 90.0)
		var val := clampf(noise + pop, -1.0, 1.0)
		buffer.encode_s16(i * 2, int(val * 32767.0))
	stream.data = buffer
	return stream


static func _build_voice_pulse_stream(pitch_multiplier: float) -> AudioStreamWAV:
	# VHF Band-Limited Vocal Formant Burst
	var sample_rate := 22050
	var duration := 0.26
	var frame_count := int(sample_rate * duration)
	var stream := _new_mono_stream(sample_rate, frame_count)
	var buffer := stream.data
	var base_freq := 280.0 * pitch_multiplier
	for i in range(frame_count):
		var t := float(i) / float(sample_rate)
		var env := sin(clampf(t / duration, 0.0, 1.0) * PI)
		var f1 := sin(t * TAU * base_freq) * 0.50
		var f2 := sin(t * TAU * (base_freq * 2.2)) * 0.35
		var f3 := sin(t * TAU * (base_freq * 3.8)) * 0.20
		var radio_distortion := (randf() * 2.0 - 1.0) * 0.12
		var mixed := (f1 + f2 + f3 + radio_distortion) * env
		buffer.encode_s16(i * 2, int(clampf(mixed, -1.0, 1.0) * 32767.0))
	stream.data = buffer
	return stream


static func _new_mono_stream(sample_rate: int, frame_count: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	var buffer := PackedByteArray()
	buffer.resize(frame_count * 2)
	stream.data = buffer
	return stream
