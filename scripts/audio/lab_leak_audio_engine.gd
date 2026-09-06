class_name LabLeakAudioEngine
extends Node

const WEAPON_SOUND_BANK_PATH := "res://config/weapon_sound_bank.json"
static var _weapon_streams: Dictionary = {}
static var _weapon_bank_loaded := false

const FRAG_CORE_STREAM := preload(
	"res://assets/audio/grenades/frag_core_grenade_training_cc0.mp3"
)
const FRAG_DISTANT_TAIL_STREAM := preload(
	"res://assets/audio/grenades/frag_distant_tail_cc0.wav"
)
const FLASHBANG_DETONATION_STREAM := preload(
	"res://assets/audio/grenades/flashbang_detonation_cc0.wav"
)

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
static var _body_impact_thump_stream: AudioStreamWAV
static var _body_impact_snap_stream: AudioStreamWAV
static var _helmet_impact_stream: AudioStreamWAV
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
		asp.bus = &"Effects" if AudioServer.get_bus_index(&"Effects") >= 0 else &"Master"
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

static func play_gunshot(
	tree: SceneTree,
	is_silenced: bool = false,
	world_position := Vector3(INF, INF, INF),
	force_direct := false,
	exclude: Array = [],
	weapon_id: String = ""
) -> void:
	var stream := gunshot_stream(is_silenced, weapon_id)
	var propagation := tree.root.get_node_or_null("AcousticPropagation")
	if propagation != null and propagation.has_method("play_event") and world_position.is_finite():
		var options := {
			"volume_db": -2.0 if is_silenced else 2.0,
			"pitch_scale": randf_range(0.97, 1.03),
			"exclude": exclude,
		}
		# Absence means resolve physics LOS. False is an explicit blocked-path
		# override in the acoustic contract, not the normal automatic mode.
		if force_direct:
			options["direct_clear"] = true
		propagation.call(
			"play_event",
			stream,
			world_position,
			&"weapon",
			options
		)
		return
	var player := _get_available_player(tree)
	player.bus = &"Effects" if AudioServer.get_bus_index(&"Effects") >= 0 else &"Master"
	player.stream = stream
	player.volume_db = -2.0 if is_silenced else 2.0
	player.pitch_scale = randf_range(0.95, 1.05)
	player.play()


static func play_body_impact(
	tree: SceneTree,
	world_position: Vector3,
	is_headshot := false
) -> void:
	var propagation := tree.root.get_node_or_null("AcousticPropagation")
	if propagation != null and propagation.has_method("play_layered_event"):
		var layers := body_impact_layers(is_headshot, true)
		propagation.call(
			"play_layered_event", layers, world_position, &"body_impact", {}
		)
		return
	var player := _get_available_player(tree)
	player.bus = &"Effects" if AudioServer.get_bus_index(&"Effects") >= 0 else &"Master"
	player.stream = _helmet_impact_stream if is_headshot else _body_impact_thump_stream
	player.volume_db = -2.0
	player.pitch_scale = randf_range(0.95, 1.05)
	player.play()

static func play_hit_confirm(tree: SceneTree, is_headshot: bool = false) -> void:
	var player := _get_available_player(tree)
	player.bus = &"UI" if AudioServer.get_bus_index(&"UI") >= 0 else &"Master"
	player.stream = _headshot_confirm_stream if is_headshot else _hit_confirm_stream
	player.volume_db = 1.0
	player.pitch_scale = 1.0
	player.play()

static func play_casing_clink(tree: SceneTree) -> void:
	var player := _get_available_player(tree)
	player.bus = &"Effects" if AudioServer.get_bus_index(&"Effects") >= 0 else &"Master"
	player.stream = _casing_stream
	player.volume_db = -8.0
	player.pitch_scale = randf_range(0.9, 1.1)
	player.play()


static func play_grenade_detonation(
	tree: SceneTree,
	world_position: Vector3,
	grenade_type: StringName = &"frag"
) -> void:
	var layers := grenade_explosion_layers(grenade_type)
	var propagation := tree.root.get_node_or_null("AcousticPropagation")
	if propagation != null and propagation.has_method("play_layered_event"):
		propagation.call(
			"play_layered_event",
			layers,
			world_position,
			&"explosion",
			{}
		)
		return
	# The acoustic autoload is present in normal gameplay. Keep a simple local
	# fallback for isolated grenade scenes and focused editor previews.
	for layer: Dictionary in layers:
		var player := _get_available_player(tree)
		player.bus = &"Effects" if AudioServer.get_bus_index(&"Effects") >= 0 else &"Master"
		player.stream = layer.get("stream") as AudioStream
		player.volume_db = float(layer.get("volume_db", 0.0))
		player.pitch_scale = float(layer.get("pitch_scale", 1.0))
		player.play()


static func gunshot_stream(is_silenced := false, weapon_id: String = "") -> AudioStreamWAV:
	_build_cached_streams()
	if _weapon_streams.has(weapon_id):
		return _weapon_streams[weapon_id] as AudioStreamWAV
	return _silenced_gunshot_stream if is_silenced else _gunshot_stream


static func _load_weapon_sound_bank() -> void:
	if _weapon_bank_loaded:
		return
	_weapon_bank_loaded = true
	if not FileAccess.file_exists(WEAPON_SOUND_BANK_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(WEAPON_SOUND_BANK_PATH))
	if not parsed is Dictionary or not bool(parsed.get("enabled", false)):
		return
	var entries: Dictionary = parsed.get("weapons", {})
	var use_cleaned := bool(parsed.get("use_cleaned_streams", false))
	for weapon_id: String in entries:
		var entry: Dictionary = entries[weapon_id]
		var path := String(entry.get("stream", ""))
		var cleaned_path := String(entry.get("cleaned_stream", ""))
		if use_cleaned and not cleaned_path.is_empty() and ResourceLoader.exists(cleaned_path, "AudioStreamWAV"):
			path = cleaned_path
		if not ResourceLoader.exists(path, "AudioStreamWAV"):
			push_warning("Weapon sound unavailable; keeping fallback: %s" % weapon_id)
			continue
		var stream := load(path) as AudioStreamWAV
		if stream != null and stream.get_length() > 0.0:
			_weapon_streams[weapon_id] = stream


static func body_impact_layers(
	is_headshot := false,
	randomize_pitch := false
) -> Array[Dictionary]:
	_build_cached_streams()
	var layers: Array[Dictionary] = [
		{
			"stream": _body_impact_thump_stream,
			"volume_db": -1.5 if is_headshot else 0.75,
			"pitch_scale": randf_range(0.94, 1.06) if randomize_pitch else 1.0,
		},
		{
			"stream": _body_impact_snap_stream,
			"volume_db": -5.0 if is_headshot else -9.0,
			"pitch_scale": randf_range(0.96, 1.08) if randomize_pitch else 1.03,
			"delay_seconds": 0.006,
		},
	]
	if is_headshot:
		layers.append({
			"stream": _helmet_impact_stream,
			"volume_db": -2.5,
			"pitch_scale": randf_range(0.96, 1.04) if randomize_pitch else 1.0,
			"delay_seconds": 0.003,
		})
	return layers


static func grenade_explosion_layers(
	grenade_type: StringName = &"frag"
) -> Array[Dictionary]:
	if grenade_type == &"flash":
		return [{
			"stream": FLASHBANG_DETONATION_STREAM,
			"volume_db": -1.5,
			"pitch_scale": 1.0,
		}]
	return [
		{
			"stream": FRAG_CORE_STREAM,
			"volume_db": 1.0,
			"pitch_scale": randf_range(0.97, 1.03),
		},
		{
			"stream": FRAG_DISTANT_TAIL_STREAM,
			"volume_db": -8.0,
			"pitch_scale": randf_range(0.96, 1.02),
			"delay_seconds": 0.035,
		},
	]


static func get_cached_resource_ids() -> Dictionary:
	return {
		"gunshot": _gunshot_stream.get_instance_id() if _gunshot_stream else 0,
		"silenced_gunshot": _silenced_gunshot_stream.get_instance_id() if _silenced_gunshot_stream else 0,
		"hit": _hit_confirm_stream.get_instance_id() if _hit_confirm_stream else 0,
		"headshot": _headshot_confirm_stream.get_instance_id() if _headshot_confirm_stream else 0,
		"casing": _casing_stream.get_instance_id() if _casing_stream else 0,
		"body_impact": _body_impact_thump_stream.get_instance_id() if _body_impact_thump_stream else 0,
		"helmet_impact": _helmet_impact_stream.get_instance_id() if _helmet_impact_stream else 0,
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
	_body_impact_thump_stream = null
	_body_impact_snap_stream = null
	_helmet_impact_stream = null
	_is_initialized = false
	_weapon_streams.clear()
	_weapon_bank_loaded = false


static func _build_cached_streams() -> void:
	# Warm the small shared bank once, not from disk on every accepted shot.
	_load_weapon_sound_bank()
	if _gunshot_stream != null:
		return
	# Preserve the Sound Lab's wide-band reference as the unknown-gun fallback.
	# Identified weapons use the shared imported bank above.
	_gunshot_stream = _build_acoustic_reference_shot()
	_silenced_gunshot_stream = _build_gunshot_stream(0.16)
	_hit_confirm_stream = _build_hit_confirm_stream(720.0)
	_headshot_confirm_stream = _build_hit_confirm_stream(1600.0)
	_casing_stream = _build_casing_stream(3700.0)
	_body_impact_thump_stream = _build_body_impact_stream(false)
	_body_impact_snap_stream = _build_body_snap_stream()
	_helmet_impact_stream = _build_body_impact_stream(true)


static func _build_acoustic_reference_shot() -> AudioStreamWAV:
	const SAMPLE_RATE := 44100
	var duration := 0.42
	var frame_count := int(duration * SAMPLE_RATE)
	var stream := _new_mono_stream(SAMPLE_RATE, frame_count)
	var buffer := stream.data
	for index in frame_count:
		var t := float(index) / SAMPLE_RATE
		var crack := randf_range(-1.0, 1.0) * exp(-t * 125.0)
		var body := (
			sin(TAU * lerpf(180.0, 72.0, minf(t * 8.0, 1.0)) * t)
			* exp(-t * 18.0)
		)
		var tail := randf_range(-1.0, 1.0) * exp(-t * 9.0) * 0.08
		var value := clampf(crack * 0.48 + body * 0.62 + tail, -1.0, 1.0)
		buffer.encode_s16(index * 2, int(value * 32767.0))
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


static func _build_body_impact_stream(helmet: bool) -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.14 if helmet else 0.20
	var frame_count := int(sample_rate * duration)
	var stream := _new_mono_stream(sample_rate, frame_count)
	var buffer := stream.data
	var filtered_noise := 0.0
	for i in range(frame_count):
		var t := float(i) / sample_rate
		var thump_frequency_start := 92.0 if helmet else 118.0
		var thump_frequency_end := 48.0 if helmet else 72.0
		var thump := (
			sin(
				TAU
				* lerpf(thump_frequency_start, thump_frequency_end, minf(t * 10.0, 1.0))
				* t
			)
			* exp(-t * (34.0 if helmet else 32.0))
		)
		var noise := randf_range(-1.0, 1.0)
		filtered_noise = lerpf(noise, filtered_noise, 0.88 if helmet else 0.76)
		var texture := filtered_noise * exp(-t * (58.0 if helmet else 42.0))
		# A head hit is a compact, low mechanical dud. Do not add a high-frequency
		# confirmation chime here: the world-positioned impact must remain the only
		# audible event so room acoustics and obstruction stay believable.
		var low_dud := (
			sin(TAU * 56.0 * t) * exp(-t * 38.0) * 0.48
			if helmet
			else 0.0
		)
		# Put the physical punch in the 82→56 Hz band so it survives ordinary
		# speakers, then compress it into a short muted "dud" instead of a boom.
		var body_low_frequency := lerpf(82.0, 56.0, minf(t * 6.5, 1.0))
		var body_low := (
			sin(TAU * body_low_frequency * t)
			* (1.0 - exp(-t * 115.0))
			* exp(-t * 22.0)
			if not helmet
			else 0.0
		)
		var mixed := (
			thump * (0.78 if helmet else 0.70)
			+ texture * (0.30 if helmet else 0.14)
			+ low_dud
			+ body_low * 0.74
		)
		# Soft limiting creates the low-mid harmonics that make the pulse tangible
		# without adding a metallic transient.
		var saturated := mixed / (1.0 + absf(mixed) * 0.30) * 1.24
		buffer.encode_s16(i * 2, int(clampf(saturated, -1.0, 1.0) * 32767.0))
	stream.data = buffer
	return stream


static func _build_body_snap_stream() -> AudioStreamWAV:
	var sample_rate := 22050
	var frame_count := int(sample_rate * 0.055)
	var stream := _new_mono_stream(sample_rate, frame_count)
	var buffer := stream.data
	var previous := 0.0
	for i in range(frame_count):
		var t := float(i) / sample_rate
		var noise := randf_range(-1.0, 1.0)
		previous = lerpf(noise, previous, 0.28)
		var snap := previous * exp(-t * 95.0)
		buffer.encode_s16(i * 2, int(clampf(snap * 0.72, -1.0, 1.0) * 32767.0))
	stream.data = buffer
	return stream
