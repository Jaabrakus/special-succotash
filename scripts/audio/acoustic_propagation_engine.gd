class_name AcousticPropagationEngine
extends Node3D

## Client-side acoustic presentation. This node never owns bullet, damage, or movement authority.

signal route_solved(route: Dictionary)
signal event_culled(event_class: StringName, reason: StringName)

const Profile := preload("res://scripts/audio/acoustic_propagation_profile.gd")
const Solver := preload("res://scripts/audio/acoustic_propagation_solver.gd")
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const VOICE_COUNT := 24
const MAX_EVENTS_PER_FRAME := 14

var profile: AcousticPropagationProfile
var solver: AcousticPropagationSolver
var listener: Node3D
var acoustic_zones: Array[Dictionary] = []
var acoustic_portals: Array[Dictionary] = []
var propagation_enabled := true
var debug_routes_enabled := false
var _players: Array[AudioStreamPlayer3D] = []
var _voice_priorities: Dictionary = {}
var _events_this_frame := 0
var _statistics := {
	"requested": 0, "played": 0, "culled_range": 0, "culled_budget": 0,
	"direct": 0, "portal": 0, "blocked": 0,
}


func _ready() -> void:
	add_to_group("acoustic_propagation_engine")
	profile = Profile.new()
	profile.load_from_file()
	solver = Solver.new()
	_ensure_audio_buses()
	for index in VOICE_COUNT:
		var player := AudioStreamPlayer3D.new()
		player.name = "AcousticVoice%02d" % index
		player.max_distance = 320.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
		player.attenuation_filter_cutoff_hz = 20500.0
		player.max_polyphony = 1
		add_child(player)
		_players.append(player)
		_voice_priorities[player.get_instance_id()] = 0


func _process(_delta: float) -> void:
	_events_this_frame = 0


func set_listener(listener_node: Node3D) -> void:
	listener = listener_node


func set_debug_routes_enabled(enabled: bool) -> void:
	debug_routes_enabled = enabled


func refresh_effects() -> void:
	_ensure_audio_buses()


func configure_world(zones: Array[Dictionary], portals: Array[Dictionary]) -> void:
	acoustic_zones = zones.duplicate(true)
	acoustic_portals = portals.duplicate(true)


func configure_map(document: Dictionary, listener_node: Node3D = null) -> void:
	if listener_node != null:
		listener = listener_node
	var explicit_zones: Array[Dictionary] = []
	var ambience_zones: Array[Dictionary] = []
	var portals: Array[Dictionary] = []
	var grouped_objects: Dictionary = {}
	var portal_objects: Array[Dictionary] = []
	for object: Dictionary in document.get("objects", []):
		var type_name := StringName(object.get("type", ""))
		var properties: Dictionary = object.get("properties", {})
		var group_id := StringName(properties.get("group_id", ""))
		if not group_id.is_empty():
			var members: Array = grouped_objects.get(group_id, [])
			members.append(object)
			grouped_objects[group_id] = members
		if type_name in [&"acoustic_room", &"ambience_zone"]:
			if type_name == &"ambience_zone" and not bool(properties.get("acoustic_enabled", false)):
				continue
			var zone := {
				"id": StringName(properties.get("acoustic_zone_id", object.get("id", ""))),
				"position": MapDocument.data_to_vector(object.get("position", {})),
				"rotation_degrees": MapDocument.data_to_vector(object.get("rotation_degrees", {})),
				"size": MapDocument.data_to_vector(object.get("size", {}), Vector3.ONE),
			}
			if type_name == &"acoustic_room":
				explicit_zones.append(zone)
			else:
				ambience_zones.append(zone)
		elif type_name in [&"acoustic_portal", &"doorway_wall", &"window_wall"]:
			portal_objects.append(object)

	var inferred_zones: Dictionary = {}
	for portal_object: Dictionary in portal_objects:
		var properties: Dictionary = portal_object.get("properties", {})
		var from_zone := StringName(properties.get("acoustic_from_zone", ""))
		var to_zone := StringName(properties.get("acoustic_to_zone", ""))
		var group_id := StringName(properties.get("group_id", ""))
		if from_zone.is_empty() and not group_id.is_empty():
			var inferred: Dictionary = _infer_group_room(
				group_id,
				grouped_objects.get(group_id, []) as Array
			)
			if not inferred.is_empty():
				inferred_zones[group_id] = inferred
				from_zone = group_id
		if to_zone.is_empty() and not from_zone.is_empty():
			to_zone = &"outside"
		if from_zone.is_empty() or to_zone.is_empty():
			continue
		portals.append({
			"id": String(portal_object.get("id", "")),
			"from_zone": from_zone,
			"to_zone": to_zone,
			"position": MapDocument.data_to_vector(portal_object.get("position", {})),
			"open": bool(properties.get("acoustic_open", true)),
			"bidirectional": bool(properties.get("acoustic_bidirectional", true)),
			"loss_db": float(properties.get(
				"acoustic_loss_db", profile.get_float(&"portal_loss_db", -2.5)
			)),
		})

	var zones: Array[Dictionary] = explicit_zones
	for inferred: Dictionary in inferred_zones.values():
		zones.append(inferred)
	# Interior rooms must win before broad ambience volumes when zones overlap.
	zones.append_array(ambience_zones)
	configure_world(zones, portals)


func _infer_group_room(group_id: StringName, members: Array) -> Dictionary:
	var horizontal_surfaces: Array[Dictionary] = []
	for raw_member: Variant in members:
		if not raw_member is Dictionary:
			continue
		var member := raw_member as Dictionary
		if StringName(member.get("type", "")) in [&"roof", &"platform", &"floor"]:
			horizontal_surfaces.append(member)
	if horizontal_surfaces.size() < 2:
		return {}
	horizontal_surfaces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return MapDocument.data_to_vector(a.get("position", {})).y < MapDocument.data_to_vector(b.get("position", {})).y
	)
	var lower := horizontal_surfaces.front() as Dictionary
	var upper := horizontal_surfaces.back() as Dictionary
	var lower_position := MapDocument.data_to_vector(lower.get("position", {}))
	var upper_position := MapDocument.data_to_vector(upper.get("position", {}))
	var lower_size := MapDocument.data_to_vector(lower.get("size", {}), Vector3.ONE).abs()
	var upper_size := MapDocument.data_to_vector(upper.get("size", {}), Vector3.ONE).abs()
	var floor_y := lower_position.y + lower_size.y * 0.5
	var ceiling_y := upper_position.y - upper_size.y * 0.5
	if ceiling_y - floor_y < 1.0:
		return {}
	var minimum_x := maxf(
		lower_position.x - lower_size.x * 0.5,
		upper_position.x - upper_size.x * 0.5
	)
	var maximum_x := minf(
		lower_position.x + lower_size.x * 0.5,
		upper_position.x + upper_size.x * 0.5
	)
	var minimum_z := maxf(
		lower_position.z - lower_size.z * 0.5,
		upper_position.z - upper_size.z * 0.5
	)
	var maximum_z := minf(
		lower_position.z + lower_size.z * 0.5,
		upper_position.z + upper_size.z * 0.5
	)
	if maximum_x - minimum_x < 1.0 or maximum_z - minimum_z < 1.0:
		return {}
	return {
		"id": group_id,
		"position": Vector3(
			(minimum_x + maximum_x) * 0.5,
			(floor_y + ceiling_y) * 0.5,
			(minimum_z + maximum_z) * 0.5
		),
		"rotation_degrees": Vector3.ZERO,
		"size": Vector3(
			maximum_x - minimum_x,
			ceiling_y - floor_y,
			maximum_z - minimum_z
		),
	}


func play_event(
	stream: AudioStream,
	source_position: Vector3,
	event_class: StringName = &"foley",
	options: Dictionary = {}
) -> Dictionary:
	_statistics.requested = int(_statistics.requested) + 1
	if stream == null or not propagation_enabled:
		return {}
	if _events_this_frame >= MAX_EVENTS_PER_FRAME:
		_statistics.culled_budget = int(_statistics.culled_budget) + 1
		event_culled.emit(event_class, &"frame_budget")
		return {}
	var listener_position := _listener_position()
	if options.has("listener_position"):
		listener_position = options.listener_position
	if not listener_position.is_finite():
		event_culled.emit(event_class, &"no_listener")
		return {}
	var policy := profile.policy_for(event_class)
	var distance := source_position.distance_to(listener_position)
	var max_distance := float(options.get("max_distance_m", policy.get("max_distance_m", 45.0)))
	if distance > max_distance:
		_statistics.culled_range = int(_statistics.culled_range) + 1
		event_culled.emit(event_class, &"range")
		return {}
	_events_this_frame += 1
	var direct_result := _direct_path_result(source_position, listener_position, options)
	var direct_clear := bool(options.get("direct_clear", direct_result.is_empty()))
	var source_zone := StringName(options.get("source_zone", _zone_at(source_position)))
	var listener_zone := StringName(options.get("listener_zone", _zone_at(listener_position)))
	var route := solver.solve(
		source_zone, listener_zone, source_position, listener_position,
		acoustic_portals, direct_clear, profile
	)
	var maximum_hops := int(options.get("max_portal_hops", policy.get("max_portal_hops", 2)))
	if StringName(route.get("kind", &"")) == &"portal" and int(route.get("portal_hops", 0)) > maximum_hops:
		route = solver.solve(source_zone, listener_zone, source_position, listener_position, [], false, profile)
	var policy_delay_scale := float(options.get("delay_scale", policy.get("delay_scale", 1.0)))
	route["delay_seconds"] = float(route.get("delay_seconds", 0.0)) * policy_delay_scale
	route["volume_db"] = (
		float(route.get("volume_db", 0.0)) + float(policy.get("volume_bias_db", 0.0))
		+ float(options.get("volume_db", 0.0))
	)
	route["event_class"] = event_class
	route["priority"] = int(options.get("priority", policy.get("priority", 25)))
	route["pitch_scale"] = float(options.get("pitch_scale", 1.0))
	route["extra_delay_seconds"] = float(options.get("extra_delay_seconds", 0.0))
	if StringName(route.get("kind", &"")) == &"blocked" and not direct_result.is_empty():
		_apply_blocker_material(route, direct_result.get("collider") as Node)
	_queue_route(stream, route)
	route_solved.emit(route)
	var kind := String(route.get("kind", "blocked"))
	if _statistics.has(kind):
		_statistics[kind] = int(_statistics[kind]) + 1
	return route


func play_layered_event(
	layers: Array[Dictionary],
	source_position: Vector3,
	event_class: StringName,
	options: Dictionary = {}
) -> Array[Dictionary]:
	var routes: Array[Dictionary] = []
	for layer: Dictionary in layers:
		var stream := layer.get("stream") as AudioStream
		if stream == null:
			continue
		var layer_options := options.duplicate(true)
		layer_options["volume_db"] = float(options.get("volume_db", 0.0)) + float(layer.get("volume_db", 0.0))
		layer_options["pitch_scale"] = float(layer.get("pitch_scale", options.get("pitch_scale", 1.0)))
		layer_options["extra_delay_seconds"] = float(layer.get("delay_seconds", 0.0))
		var route := play_event(stream, source_position, event_class, layer_options)
		if not route.is_empty():
			routes.append(route)
	return routes


func preview_event(
	stream: AudioStream,
	source_position: Vector3,
	source_zone: StringName,
	listener_position: Vector3,
	listener_zone: StringName,
	portals: Array[Dictionary],
	direct_clear: bool,
	options: Dictionary = {}
) -> Dictionary:
	var route := solver.solve(
		source_zone, listener_zone, source_position, listener_position,
		portals, direct_clear, profile
	)
	route["event_class"] = &"weapon"
	route["priority"] = 100
	route["volume_db"] = float(route.get("volume_db", 0.0)) + float(options.get("volume_db", 0.0))
	route["pitch_scale"] = float(options.get("pitch_scale", 1.0))
	route["extra_delay_seconds"] = float(options.get("delay_seconds", 0.0))
	_queue_route(stream, route)
	route_solved.emit(route)
	return route


func statistics() -> Dictionary:
	return _statistics.duplicate(true)


func reset_statistics() -> void:
	for key: Variant in _statistics:
		_statistics[key] = 0


func _queue_route(stream: AudioStream, route: Dictionary) -> void:
	var delay := float(route.get("delay_seconds", 0.0)) + float(route.get("extra_delay_seconds", 0.0))
	if delay > 0.002:
		var timer := get_tree().create_timer(delay)
		timer.timeout.connect(_play_route.bind(stream, route))
	else:
		_play_route(stream, route)


func _play_route(stream: AudioStream, route: Dictionary) -> void:
	if stream == null or _players.is_empty() or not is_inside_tree():
		return
	var priority := int(route.get("priority", 25))
	var player := _claim_player(priority)
	if player == null:
		_statistics.culled_budget = int(_statistics.culled_budget) + 1
		return
	player.stream = stream
	player.global_position = route.get("emission_position", global_position)
	player.volume_db = clampf(float(route.get("volume_db", 0.0)), -48.0, 8.0)
	player.pitch_scale = clampf(float(route.get("pitch_scale", 1.0)), 0.65, 1.45)
	player.max_distance = float(profile.policy_for(StringName(route.get("event_class", &"foley"))).get("max_distance_m", 45.0))
	match StringName(route.get("kind", &"direct")):
		&"portal": player.bus = &"AcousticPortal"
		&"blocked":
			player.bus = _blocked_bus_name(StringName(route.get("blocker_material", &"concrete")))
		_:
			player.bus = (
				&"AcousticWeaponDirect"
				if StringName(route.get("event_class", &"")) == &"weapon"
				else &"AcousticDirect"
			)
	player.play()
	_statistics.played = int(_statistics.played) + 1


func _claim_player(priority: int) -> AudioStreamPlayer3D:
	for player: AudioStreamPlayer3D in _players:
		if not player.playing:
			_voice_priorities[player.get_instance_id()] = priority
			return player
	var lowest: AudioStreamPlayer3D
	var lowest_priority := 1000000
	for player: AudioStreamPlayer3D in _players:
		var voice_priority := int(_voice_priorities.get(player.get_instance_id(), 0))
		if voice_priority < lowest_priority:
			lowest = player
			lowest_priority = voice_priority
	if lowest == null or priority < lowest_priority:
		return null
	lowest.stop()
	_voice_priorities[lowest.get_instance_id()] = priority
	return lowest


func _listener_position() -> Vector3:
	if listener != null and is_instance_valid(listener):
		return listener.global_position
	var viewport := get_viewport()
	if viewport != null:
		var active_camera := viewport.get_camera_3d()
		if active_camera != null:
			return active_camera.global_position
	return Vector3(INF, INF, INF)


func _direct_path_result(source_position: Vector3, listener_position: Vector3, options: Dictionary) -> Dictionary:
	if bool(options.get("direct_clear", false)):
		return {}
	var viewport := get_viewport()
	if viewport == null or viewport.world_3d == null or source_position.distance_to(listener_position) <= 0.12:
		return {}
	var query := PhysicsRayQueryParameters3D.create(source_position, listener_position)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = int(options.get("collision_mask", 0x7fffffff))
	var exclude: Variant = options.get("exclude", [])
	if exclude is Array:
		query.exclude = exclude
	return viewport.world_3d.direct_space_state.intersect_ray(query)


func _zone_at(world_position: Vector3) -> StringName:
	for zone: Dictionary in acoustic_zones:
		var position: Vector3 = zone.get("position", Vector3.ZERO)
		var rotation: Vector3 = zone.get("rotation_degrees", Vector3.ZERO)
		var size: Vector3 = zone.get("size", Vector3.ONE)
		var transform := Transform3D(Basis.from_euler(rotation * PI / 180.0), position)
		var local := transform.affine_inverse() * world_position
		if absf(local.x) <= size.x * 0.5 and absf(local.y) <= size.y * 0.5 and absf(local.z) <= size.z * 0.5:
			return StringName(zone.get("id", ""))
	return &"outside"


func _apply_blocker_material(route: Dictionary, collider: Node) -> void:
	var material_name := _surface_name(collider)
	var material := profile.material_for(material_name)
	if material.is_empty():
		return
	route["volume_db"] = minf(float(route.get("volume_db", 0.0)), float(material.get("loss_db", -12.0)))
	route["lowpass_hz"] = minf(float(route.get("lowpass_hz", 1350.0)), float(material.get("lowpass_hz", 1100.0)))
	route["blocker_material"] = material_name


func _surface_name(collider: Node) -> StringName:
	if collider == null:
		return &"concrete"
	for key in [&"surface_audio", &"surface_type", &"material_type"]:
		if collider.has_meta(key):
			return StringName(String(collider.get_meta(key)).to_lower())
	var source := collider.name.to_lower()
	for candidate in [&"metal", &"wood", &"glass", &"foliage", &"concrete"]:
		if source.contains(String(candidate)):
			return candidate
	return &"concrete"


func _ensure_audio_buses() -> void:
	_ensure_bus(&"AcousticDirect", 20500.0, false)
	_ensure_bus(&"AcousticWeaponDirect", 20500.0, true)
	_ensure_bus(&"AcousticPortal", profile.get_float(&"portal_lowpass_hz", 7200.0), true)
	_ensure_bus(&"AcousticBlocked", profile.get_float(&"blocked_lowpass_hz", 1350.0), true)
	for material_name: String in profile.material_names():
		var material := profile.material_for(StringName(material_name))
		_ensure_bus(
			_blocked_bus_name(StringName(material_name)),
			float(material.get("lowpass_hz", profile.get_float(&"blocked_lowpass_hz", 1350.0))),
			true
		)
	# Clear-path gunfire still needs its near-field pressure reflection. This is
	# the acoustic character heard in the Sound Lab, without falsely applying a
	# wall low-pass filter to an outdoor shot.
	var weapon_bus_index := AudioServer.get_bus_index(&"AcousticWeaponDirect")
	if weapon_bus_index >= 0 and AudioServer.get_bus_effect_count(weapon_bus_index) >= 2:
		var weapon_reverb := AudioServer.get_bus_effect(
			weapon_bus_index, 1
		) as AudioEffectReverb
		if weapon_reverb != null:
			weapon_reverb.wet = profile.get_float(&"early_reflection_gain", 0.34)
			weapon_reverb.room_size = 0.42
			weapon_reverb.predelay_msec = 18.0


func _blocked_bus_name(material_name: StringName) -> StringName:
	return StringName("AcousticBlocked_%s" % String(material_name).to_pascal_case())


func _ensure_bus(bus_name: StringName, cutoff_hz: float, add_reverb: bool) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, &"Master")
	if AudioServer.get_bus_effect_count(index) == 0:
		AudioServer.add_bus_effect(index, AudioEffectLowPassFilter.new())
	var lowpass := AudioServer.get_bus_effect(index, 0) as AudioEffectLowPassFilter
	if lowpass != null:
		lowpass.cutoff_hz = cutoff_hz
	if add_reverb and AudioServer.get_bus_effect_count(index) < 2:
		var new_reverb := AudioEffectReverb.new()
		new_reverb.dry = 1.0
		new_reverb.room_size = 0.62
		new_reverb.predelay_msec = 35.0
		AudioServer.add_bus_effect(index, new_reverb)
	if add_reverb:
		var reverb := AudioServer.get_bus_effect(index, 1) as AudioEffectReverb
		if reverb != null:
			reverb.wet = profile.get_float(&"reverb_wet", 0.24)
