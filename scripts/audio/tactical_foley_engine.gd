class_name TacticalFoleyEngine
extends Node

const SAMPLE_RATE := 22050
const POOL_SIZE := 20
const SurfaceResolver := preload("res://scripts/audio/surface_audio_resolver.gd")

var _players: Array[AudioStreamPlayer3D] = []
var _streams: Dictionary = {}
var _cursor := 0
var surface_resolver: SurfaceAudioResolver


func _ready() -> void:
	surface_resolver = SurfaceResolver.new()
	surface_resolver.name = "SurfaceAudioResolver"
	add_child(surface_resolver)
	for index in POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.name = "FoleyVoice%02d" % index
		player.max_distance = 24.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_players.append(player)
	_build_streams()


func play_surface_event(
	event_name: StringName,
	world_position: Vector3,
	intensity := 1.0,
	collider: Node = null,
	explicit_surface: StringName = &""
) -> StringName:
	return surface_resolver.play_event(
		self, event_name, world_position, intensity, collider, explicit_surface
	)


func surface_physics(surface_name: StringName) -> Dictionary:
	return surface_resolver.physics_for(surface_name)


func play_cue(cue: StringName, world_position: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(cue):
		return
	var propagation := get_node_or_null("/root/AcousticPropagation")
	if propagation != null and propagation.has_method("play_event"):
		propagation.call(
			"play_event", _streams[cue], world_position, _event_class_for_cue(cue),
			{"volume_db": volume_db, "pitch_scale": clampf(pitch, 0.65, 1.45)}
		)
		return
	if _players.is_empty():
		return
	var player := _players[_cursor]
	_cursor = (_cursor + 1) % _players.size()
	player.global_position = world_position
	player.stream = _streams[cue]
	player.volume_db = volume_db
	player.pitch_scale = clampf(pitch, 0.65, 1.45)
	player.play()


func _event_class_for_cue(cue: StringName) -> StringName:
	var cue_text := String(cue)
	if cue_text.begins_with("foot_"):
		return &"footstep"
	if cue_text.begins_with("impact_") or cue_text.begins_with("grenade_"):
		return &"world_impact"
	return &"foley"


func cue_names() -> PackedStringArray:
	return PackedStringArray(_streams.keys())


func stream_for_cue(cue: StringName) -> AudioStream:
	return _streams.get(cue) as AudioStream


func _build_streams() -> void:
	_streams = {
		&"foot_concrete": _make_impact(0.19, 82.0, 0.52, 0.32),
		&"foot_metal": _make_impact(0.22, 245.0, 0.34, 0.15),
		&"foot_dirt": _make_noise_burst(0.24, 0.30, 0.55),
		&"foot_wood": _make_impact(0.26, 132.0, 0.40, 0.25),
		&"foot_sand": _make_noise_burst(0.28, 0.24, 0.70),
		&"foot_carpet": _make_noise_burst(0.18, 0.12, 0.88),
		&"gear_rustle": _make_noise_burst(0.16, 0.11, 0.82),
		&"sling_jingle": _make_impact(0.16, 760.0, 0.15, 0.05),
		&"plate_clatter": _make_impact(0.18, 118.0, 0.28, 0.12),
		&"pin_pull": _make_impact(0.13, 1160.0, 0.12, 0.03),
		&"spoon_snap": _make_impact(0.10, 620.0, 0.24, 0.04),
		&"mag_eject": _make_impact(0.18, 180.0, 0.35, 0.10),
		&"mag_insert": _make_impact(0.16, 145.0, 0.46, 0.08),
		&"bolt_rack": _make_noise_burst(0.22, 0.28, 0.72),
		&"body_landing": _make_impact(0.32, 62.0, 0.72, 0.42),
		&"body_roll": _make_noise_burst(0.45, 0.34, 0.74),
		&"grenade_concrete": _make_impact(0.22, 320.0, 0.44, 0.18),
		&"grenade_metal": _make_impact(0.32, 780.0, 0.36, 0.10),
		&"grenade_dirt": _make_noise_burst(0.22, 0.22, 0.70),
		&"grenade_sand": _make_noise_burst(0.25, 0.16, 0.84),
		&"grenade_wood": _make_impact(0.27, 168.0, 0.38, 0.20),
		&"impact_hard": _make_impact(0.12, 460.0, 0.34, 0.22),
		&"impact_metal": _make_impact(0.18, 1240.0, 0.22, 0.08),
		&"impact_soft": _make_noise_burst(0.16, 0.18, 0.76),
		&"impact_wood": _make_impact(0.18, 210.0, 0.30, 0.18),
		&"smoke_hiss": _make_noise_burst(1.2, 0.16, 0.92),
		&"tinnitus": _make_tone(2.2, 3650.0, 0.12),
	}


func _make_impact(duration: float, frequency: float, gain: float, noise_gain: float) -> AudioStreamWAV:
	var samples := PackedByteArray()
	var count := int(duration * SAMPLE_RATE)
	for index in count:
		var t := float(index) / SAMPLE_RATE
		var envelope := exp(-t * 18.0)
		var value := sin(TAU * frequency * t) * gain + randf_range(-1.0, 1.0) * noise_gain
		_write_sample(samples, value * envelope)
	return _make_wav(samples)


func _make_noise_burst(duration: float, gain: float, decay: float) -> AudioStreamWAV:
	var samples := PackedByteArray()
	var count := int(duration * SAMPLE_RATE)
	var previous := 0.0
	for index in count:
		var t := float(index) / duration / SAMPLE_RATE
		var noise := randf_range(-1.0, 1.0)
		previous = lerpf(noise, previous, decay)
		_write_sample(samples, previous * gain * (1.0 - t))
	return _make_wav(samples)


func _make_tone(duration: float, frequency: float, gain: float) -> AudioStreamWAV:
	var samples := PackedByteArray()
	var count := int(duration * SAMPLE_RATE)
	for index in count:
		var t := float(index) / SAMPLE_RATE
		var envelope := minf(1.0, t * 8.0) * maxf(0.0, 1.0 - t / duration)
		_write_sample(samples, sin(TAU * frequency * t) * gain * envelope)
	return _make_wav(samples)


func _write_sample(bytes: PackedByteArray, value: float) -> void:
	var sample := int(clampf(value, -1.0, 1.0) * 32767.0)
	bytes.append(sample & 0xff)
	bytes.append((sample >> 8) & 0xff)


func _make_wav(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
