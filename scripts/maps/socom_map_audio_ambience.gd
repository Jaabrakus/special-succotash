class_name SocomMapAudioAmbience
extends Node

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")

var listener: Node3D
var zones: Array[Dictionary] = []
var active_zone_id := ""
var active_player: AudioStreamPlayer
var standby_player: AudioStreamPlayer
var check_accumulator := 0.0


func configure(document: Dictionary, listener_node: Node3D) -> void:
	listener = listener_node
	zones.clear()
	for object: Dictionary in MapDocument.normalize(document).get("objects", []):
		if String(object.get("type", "")) == "ambience_zone":
			zones.append(object.duplicate(true))
	if active_player == null:
		active_player = AudioStreamPlayer.new()
		active_player.name = "MapAmbienceA"
		add_child(active_player)
		standby_player = AudioStreamPlayer.new()
		standby_player.name = "MapAmbienceB"
		add_child(standby_player)
	set_process(listener != null and not zones.is_empty())


func _process(delta: float) -> void:
	check_accumulator += delta
	if check_accumulator < 0.15 or listener == null:
		return
	check_accumulator = 0.0
	var zone := _zone_at(listener.global_position)
	var zone_id := String(zone.get("id", ""))
	if zone_id != active_zone_id:
		active_zone_id = zone_id
		_transition_to_zone(zone)


func _zone_at(world_position: Vector3) -> Dictionary:
	for zone: Dictionary in zones:
		var position := MapDocument.data_to_vector(zone.get("position", {}))
		var rotation := MapDocument.data_to_vector(zone.get("rotation_degrees", {}))
		var size := MapDocument.data_to_vector(zone.get("size", {}), Vector3.ONE)
		var transform := Transform3D(Basis.from_euler(rotation * PI / 180.0), position)
		var local := transform.affine_inverse() * world_position
		if absf(local.x) <= size.x * 0.5 and absf(local.y) <= size.y * 0.5 and absf(local.z) <= size.z * 0.5:
			return zone
	return {}


func _transition_to_zone(zone: Dictionary) -> void:
	var properties: Dictionary = zone.get("properties", {})
	var stream_path := String(properties.get("audio_stream", ""))
	var target_volume := float(properties.get("volume_db", -8.0))
	if stream_path.is_empty() or not ResourceLoader.exists(stream_path):
		_fade_out(active_player)
		return
	var stream := load(stream_path) as AudioStream
	if stream == null:
		return
	standby_player.stream = stream
	standby_player.volume_db = -60.0
	standby_player.play()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(standby_player, "volume_db", target_volume, 1.25)
	if active_player.playing:
		tween.tween_property(active_player, "volume_db", -60.0, 1.25)
	var previous := active_player
	active_player = standby_player
	standby_player = previous
	tween.chain().tween_callback(standby_player.stop)


func _fade_out(player: AudioStreamPlayer) -> void:
	if player == null or not player.playing:
		return
	var tween := create_tween()
	tween.tween_property(player, "volume_db", -60.0, 0.8)
	tween.tween_callback(player.stop)
