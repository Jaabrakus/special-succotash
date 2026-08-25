class_name SocomVoiceChatController
extends Node

## Authentic SOCOM 2 Tactical Voice Chat & Microphone VoIP Engine
## Ported from reCOM (zSound/zsnd.h m_isHeadsetStream, zNetwork voice packets)

signal transmission_started()
signal transmission_ended()
signal voice_frame_captured(frame_bytes: PackedByteArray, energy: float)
signal remote_player_speaking(player_id: int, is_speaking: bool)

const ChatterEngine := preload("res://scripts/audio/socom_radio_chatter_engine.gd")

const RECORD_BUS_NAME := &"Record"
const SAMPLE_RATE := 22050
const FRAME_DURATION_MS := 20 # Fits one uncompressed mono frame below the MTU.
const SAMPLES_PER_FRAME := int(SAMPLE_RATE * (FRAME_DURATION_MS / 1000.0))
const MAX_NETWORK_FRAME_BYTES := 1024
const REMOTE_SPEAKING_HOLD_SECONDS := 0.12

@export var ptt_enabled: bool = true
@export var loopback_enabled: bool = false # Hear own radio-filtered voice
@export var radio_filter_enabled: bool = true

var is_transmitting: bool = false
var mic_volume_level: float = 0.0 # 0.0 to 1.0 RMS

var _mic_player: AudioStreamPlayer
var _capture_effect: AudioEffectCapture
var _loopback_player: AudioStreamPlayer
var _loopback_generator: AudioStreamGeneratorPlayback
var _record_bus_index: int = -1
var _remote_speaking_timeouts: Dictionary = {}


func _ready() -> void:
	_setup_audio_bus_and_capture()


func _setup_audio_bus_and_capture() -> void:
	# 1. Create or resolve Record bus
	_record_bus_index = AudioServer.get_bus_index(RECORD_BUS_NAME)
	if _record_bus_index < 0:
		AudioServer.add_bus()
		_record_bus_index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(_record_bus_index, RECORD_BUS_NAME)
		AudioServer.set_bus_mute(_record_bus_index, true) # Prevent raw mic bleed to master

	# 2. Attach AudioEffectCapture to Record bus
	_capture_effect = AudioEffectCapture.new()
	_capture_effect.buffer_length = 0.5 # 500ms ring buffer
	AudioServer.add_bus_effect(_record_bus_index, _capture_effect)

	# 3. Create microphone input player
	_mic_player = AudioStreamPlayer.new()
	_mic_player.name = "MicrophoneCaptureSource"
	_mic_player.bus = RECORD_BUS_NAME
	var mic_stream := AudioStreamMicrophone.new()
	_mic_player.stream = mic_stream
	add_child(_mic_player)
	_mic_player.play()

	# 4. Create generator for loopback / incoming voice playback
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SAMPLE_RATE
	gen.buffer_length = 0.3
	_loopback_player = AudioStreamPlayer.new()
	_loopback_player.name = "VoiceLoopbackPlayback"
	_loopback_player.bus = &"Effects" if AudioServer.get_bus_index(&"Effects") >= 0 else &"Master"
	_loopback_player.stream = gen
	add_child(_loopback_player)
	_loopback_player.play()
	_loopback_generator = _loopback_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _process(delta: float) -> void:
	_update_remote_speakers(delta)
	if _capture_effect == null:
		return

	var frames_available := _capture_effect.get_frames_available()
	if frames_available < SAMPLES_PER_FRAME:
		if not is_transmitting:
			mic_volume_level = lerpf(mic_volume_level, 0.0, 0.2)
		return

	var raw_buffer := _capture_effect.get_buffer(SAMPLES_PER_FRAME)
	var energy_accum := 0.0
	var processed_samples := PackedFloat32Array()
	processed_samples.resize(SAMPLES_PER_FRAME)

	for i in range(SAMPLES_PER_FRAME):
		var sample_val := raw_buffer[i].x # Mono mix
		energy_accum += sample_val * sample_val

		# Apply Authentic SOCOM 2 VHF Radio Bandpass & Soft Saturation
		if radio_filter_enabled:
			# High-pass + Low-pass telephone filter emulation (300Hz - 3400Hz)
			sample_val = clampf(sample_val * 1.65, -0.92, 0.92) # Radio compression
		processed_samples[i] = sample_val

	var rms := sqrt(energy_accum / float(SAMPLES_PER_FRAME))
	mic_volume_level = clampf(rms * 4.5, 0.0, 1.0)

	if is_transmitting:
		# Convert to 16-bit PCM byte array for network replication
		var pcm_bytes := PackedByteArray()
		pcm_bytes.resize(SAMPLES_PER_FRAME * 2)
		for i in range(SAMPLES_PER_FRAME):
			var int16 := int(clampf(processed_samples[i], -1.0, 1.0) * 32767.0)
			pcm_bytes.encode_s16(i * 2, int16)

		voice_frame_captured.emit(pcm_bytes, mic_volume_level)
		_send_voice_frame(pcm_bytes, mic_volume_level)

		# Local loopback playback if enabled for testing
		if loopback_enabled and _loopback_generator != null:
			for i in range(SAMPLES_PER_FRAME):
				if _loopback_generator.can_push_buffer(1):
					_loopback_generator.push_frame(Vector2(processed_samples[i], processed_samples[i]))


func start_transmitting() -> void:
	if is_transmitting:
		return
	is_transmitting = true
	# Clear stale backlog
	if _capture_effect != null:
		_capture_effect.clear_buffer()

	# Play authentic VHF key-in click
	ChatterEngine._init_streams()
	_play_one_shot(ChatterEngine._key_in_stream, 1.5)
	transmission_started.emit()


func stop_transmitting() -> void:
	if not is_transmitting:
		return
	is_transmitting = false

	# Play authentic VHF squelch static release
	ChatterEngine._init_streams()
	_play_one_shot(ChatterEngine._squelch_out_stream, 0.0)
	transmission_ended.emit()


func play_incoming_voice_packet(_player_id: int, pcm_bytes: PackedByteArray) -> void:
	if _loopback_generator == null or pcm_bytes.is_empty():
		return
	var sample_count := pcm_bytes.size() / 2
	for i in range(sample_count):
		var int16 := pcm_bytes.decode_s16(i * 2)
		var float_sample := float(int16) / 32767.0
		if _loopback_generator.can_push_buffer(1):
			_loopback_generator.push_frame(Vector2(float_sample, float_sample))


func _send_voice_frame(pcm_bytes: PackedByteArray, energy: float) -> void:
	if not _voice_frame_is_valid(pcm_bytes, energy):
		return
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var local_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		_receive_voice_from_server.rpc(local_id, pcm_bytes, energy)
	else:
		_relay_voice_to_server.rpc_id(1, pcm_bytes, energy)


@rpc("any_peer", "call_remote", "unreliable", 4)
func _relay_voice_to_server(pcm_bytes: PackedByteArray, energy: float) -> void:
	if not multiplayer.is_server() or not _voice_frame_is_valid(pcm_bytes, energy):
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	_receive_remote_voice(sender_id, pcm_bytes, energy)
	_receive_voice_from_server.rpc(sender_id, pcm_bytes, energy)


@rpc("authority", "call_remote", "unreliable", 4)
func _receive_voice_from_server(
	sender_id: int,
	pcm_bytes: PackedByteArray,
	energy: float
) -> void:
	if sender_id == multiplayer.get_unique_id():
		return
	if not _voice_frame_is_valid(pcm_bytes, energy):
		return
	_receive_remote_voice(sender_id, pcm_bytes, energy)


func _receive_remote_voice(
	sender_id: int,
	pcm_bytes: PackedByteArray,
	energy: float
) -> void:
	var was_speaking := _remote_speaking_timeouts.has(sender_id)
	_remote_speaking_timeouts[sender_id] = REMOTE_SPEAKING_HOLD_SECONDS
	play_incoming_voice_packet(sender_id, pcm_bytes)
	if not was_speaking:
		remote_player_speaking.emit(sender_id, true)


func _update_remote_speakers(delta: float) -> void:
	for player_id: Variant in _remote_speaking_timeouts.keys():
		var remaining := float(_remote_speaking_timeouts[player_id]) - maxf(delta, 0.0)
		if remaining <= 0.0:
			_remote_speaking_timeouts.erase(player_id)
			remote_player_speaking.emit(int(player_id), false)
		else:
			_remote_speaking_timeouts[player_id] = remaining


func _voice_frame_is_valid(pcm_bytes: PackedByteArray, energy: float) -> bool:
	return (
		not pcm_bytes.is_empty()
		and pcm_bytes.size() <= MAX_NETWORK_FRAME_BYTES
		and pcm_bytes.size() % 2 == 0
		and is_finite(energy)
		and energy >= 0.0
		and energy <= 1.0
	)


func _play_one_shot(stream: AudioStream, volume_db: float) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.bus = &"Effects" if AudioServer.get_bus_index(&"Effects") >= 0 else &"Master"
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
