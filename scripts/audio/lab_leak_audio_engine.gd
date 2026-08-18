class_name LabLeakAudioEngine
extends Node

## Project Lab Leak: Heavy Tactical Military Audio Engine
## Features:
## - Heavy 55Hz Sub-Bass Chest Punch (Physical Acoustic Weight)
## - Mechanical Bolt-Action Slam & Gunpowder Pressure Wave
## - Concrete Bullet Thud & High-Velocity Flesh Impact Splat
## - Authentic Metallic Shell Casing Ring on Floor
## - Crisp Tactical Hit Confirmation Chimes

static var _is_initialized: bool = false
static var _audio_players: Array[AudioStreamPlayer] = []
static var _player_index: int = 0
static var _gunshot_stream: AudioStreamWAV
static var _silenced_gunshot_stream: AudioStreamWAV
static var _hit_confirm_stream: AudioStreamWAV
static var _headshot_confirm_stream: AudioStreamWAV
static var _casing_stream: AudioStreamWAV
const VOICE_COUNT := 16

static func initialize(parent: Node) -> void:
	if (
		_is_initialized
		and not _audio_players.is_empty()
		and is_instance_valid(_audio_players[0])
	):
		return
	_build_cached_streams()
	_audio_players.clear()
	_player_index = 0

	for i in range(VOICE_COUNT):
		var asp := AudioStreamPlayer.new()
		asp.name = "PooledAudioVoice_%d" % i
		asp.bus = "Master"
		asp.volume_db = 0.0
		parent.add_child(asp)
		_audio_players.append(asp)

	_is_initialized = true

static func _get_available_player(tree: SceneTree) -> AudioStreamPlayer:
	if not _is_initialized or _audio_players.is_empty():
		initialize(tree.current_scene)
	var p := _audio_players[_player_index]
	_player_index = (_player_index + 1) % VOICE_COUNT
	return p

static func play_gunshot(tree: SceneTree, is_silenced: bool = false) -> void:
	var player := _get_available_player(tree)
	player.stream = _silenced_gunshot_stream if is_silenced else _gunshot_stream
	player.volume_db = 2.0
	player.pitch_scale = randf_range(0.95, 1.05)
	player.play()

static func play_hit_confirm(tree: SceneTree, is_headshot: bool = false) -> void:
	var player := _get_available_player(tree)
	player.stream = _headshot_confirm_stream if is_headshot else _hit_confirm_stream
	player.volume_db = 1.0
	player.pitch_scale = 1.0
	player.play()

static func play_casing_clink(tree: SceneTree) -> void:
	var player := _get_available_player(tree)
	player.stream = _casing_stream
	player.volume_db = -8.0
	player.pitch_scale = randf_range(0.9, 1.1)
	player.play()


static func get_cached_resource_ids() -> Dictionary:
	return {
		"gunshot": _gunshot_stream.get_instance_id() if _gunshot_stream else 0,
		"silenced_gunshot": _silenced_gunshot_stream.get_instance_id() if _silenced_gunshot_stream else 0,
		"hit": _hit_confirm_stream.get_instance_id() if _hit_confirm_stream else 0,
		"headshot": _headshot_confirm_stream.get_instance_id() if _headshot_confirm_stream else 0,
		"casing": _casing_stream.get_instance_id() if _casing_stream else 0,
		"voices": _audio_players.size(),
	}


static func shutdown() -> void:
	for player in _audio_players:
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	_audio_players.clear()
	_player_index = 0
	_gunshot_stream = null
	_silenced_gunshot_stream = null
	_hit_confirm_stream = null
	_headshot_confirm_stream = null
	_casing_stream = null
	_is_initialized = false


static func _build_cached_streams() -> void:
	if _gunshot_stream != null:
		return
	_gunshot_stream = _build_gunshot_stream(0.32)
	_silenced_gunshot_stream = _build_gunshot_stream(0.16)
	_hit_confirm_stream = _build_hit_confirm_stream(720.0)
	_headshot_confirm_stream = _build_hit_confirm_stream(1600.0)
	_casing_stream = _build_casing_stream(3700.0)


static func _new_mono_stream(sample_rate: int, frame_count: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	var buffer := PackedByteArray()
	buffer.resize(frame_count * 2)
	stream.data = buffer
	return stream


static func _build_gunshot_stream(duration: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var frame_count := int(sample_rate * duration)
	var stream := _new_mono_stream(sample_rate, frame_count)
	var buffer := stream.data
	for i in range(frame_count):
		var t := float(i) / float(sample_rate)
		var sub_env := exp(-t * 22.0)
		var body_env := exp(-t * 16.0)
		var noise_env := exp(-t * 38.0)
		var sub_freq := lerpf(65.0, 32.0, clampf(t * 8.0, 0.0, 1.0))
		var sub_tone := sin(t * TAU * sub_freq) * 0.95 * sub_env
		var mid_tone := sin(t * TAU * 185.0 * exp(-t * 15.0)) * 0.65 * body_env
		var noise := (randf() * 2.0 - 1.0) * 0.85 * noise_env
		var mixed := sub_tone * 0.55 + mid_tone * 0.30 + noise * 0.40
		var int16_val := int(clampf(mixed, -1.0, 1.0) * 32767.0)
		buffer.encode_s16(i * 2, int16_val)
	stream.data = buffer
	return stream


static func _build_hit_confirm_stream(chime_frequency: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var frame_count := int(sample_rate * 0.12)
	var stream := _new_mono_stream(sample_rate, frame_count)
	var buffer := stream.data
	for i in range(frame_count):
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 35.0)
		var chime := sin(t * TAU * chime_frequency) * 0.65
		var thud := sin(t * TAU * 95.0 * exp(-t * 25.0)) * 0.80
		var mixed := (chime * 0.6 + thud * 0.5) * env
		buffer.encode_s16(i * 2, int(clampf(mixed, -1.0, 1.0) * 32767.0))
	stream.data = buffer
	return stream


static func _build_casing_stream(frequency: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var frame_count := int(sample_rate * 0.08)
	var stream := _new_mono_stream(sample_rate, frame_count)
	var buffer := stream.data
	for i in range(frame_count):
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 60.0)
		var tone := sin(t * TAU * frequency) * 0.5
		buffer.encode_s16(i * 2, int(clampf(tone * env, -1.0, 1.0) * 32767.0))
	stream.data = buffer
	return stream
