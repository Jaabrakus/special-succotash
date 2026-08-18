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
const VOICE_COUNT := 16

static func initialize(parent: Node) -> void:
	if _is_initialized and not _audio_players.is_empty():
		return
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
	var sample_rate := 22050
	var duration := 0.32 if not is_silenced else 0.16
	var frame_count := int(sample_rate * duration)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false

	var buffer := PackedByteArray()
	buffer.resize(frame_count * 2)

	# Heavy 7.62x39mm / 5.56mm Gunshot Synthesis:
	# Layer 1: 55Hz Sub-bass punch (chest thump)
	# Layer 2: 180Hz mechanical bolt carrier slam
	# Layer 3: White noise gunpowder detonation wave
	for i in range(frame_count):
		var t := float(i) / float(sample_rate)
		var sub_env := exp(-t * 22.0)
		var body_env := exp(-t * 16.0)
		var noise_env := exp(-t * 38.0)

		# Sub-bass punch (55Hz dropping to 35Hz)
		var sub_freq := lerpf(65.0, 32.0, clampf(t * 8.0, 0.0, 1.0))
		var sub_tone := sin(t * TAU * sub_freq) * 0.95 * sub_env

		# Mechanical mid punch
		var mid_tone := sin(t * TAU * 185.0 * exp(-t * 15.0)) * 0.65 * body_env

		# Gunpowder crack noise
		var noise := (randf() * 2.0 - 1.0) * 0.85 * noise_env

		var mixed := (sub_tone * 0.55 + mid_tone * 0.30 + noise * 0.40)
		var sample_val := clampf(mixed, -1.0, 1.0)
		var int16_val := int(sample_val * 32767.0)

		buffer.encode_s16(i * 2, int16_val)

	stream.data = buffer
	player.stream = stream
	player.volume_db = 2.0
	player.pitch_scale = randf_range(0.95, 1.05)
	player.play()

static func play_hit_confirm(tree: SceneTree, is_headshot: bool = false) -> void:
	var player := _get_available_player(tree)
	var sample_rate := 22050
	var duration := 0.12
	var frame_count := int(sample_rate * duration)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false

	var buffer := PackedByteArray()
	buffer.resize(frame_count * 2)

	# Heavy kinetic flesh thud + tactical chime
	var chime_freq := 1600.0 if is_headshot else 720.0
	for i in range(frame_count):
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 35.0)
		var chime := sin(t * TAU * chime_freq) * 0.65
		var thud := sin(t * TAU * 95.0 * exp(-t * 25.0)) * 0.80
		var mixed := (chime * 0.6 + thud * 0.5) * env
		var int16_val := int(clampf(mixed, -1.0, 1.0) * 32767.0)
		buffer.encode_s16(i * 2, int16_val)

	stream.data = buffer
	player.stream = stream
	player.volume_db = 1.0
	player.pitch_scale = 1.0
	player.play()

static func play_casing_clink(tree: SceneTree) -> void:
	var player := _get_available_player(tree)
	var sample_rate := 22050
	var duration := 0.08
	var frame_count := int(sample_rate * duration)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false

	var buffer := PackedByteArray()
	buffer.resize(frame_count * 2)

	var freq := randf_range(3200.0, 4200.0)
	for i in range(frame_count):
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 60.0)
		var tone := sin(t * TAU * freq) * 0.5
		var int16_val := int(clampf(tone * env, -1.0, 1.0) * 32767.0)
		buffer.encode_s16(i * 2, int16_val)

	stream.data = buffer
	player.stream = stream
	player.volume_db = -8.0
	player.pitch_scale = randf_range(0.9, 1.1)
	player.play()
