class_name AcousticPropagationSolver
extends RefCounted

const Profile := preload("res://scripts/audio/acoustic_propagation_profile.gd")


func solve(
	source_zone: StringName,
	listener_zone: StringName,
	source_position: Vector3,
	listener_position: Vector3,
	portals: Array[Dictionary],
	direct_clear: bool,
	profile: AcousticPropagationProfile
) -> Dictionary:
	var direct_distance := source_position.distance_to(listener_position)
	if direct_clear:
		return _route(
			&"direct", [source_position, listener_position], direct_distance, 0, 0.0,
			20500.0, source_position, profile
		)
	var portal_route := _find_portal_route(
		source_zone, listener_zone, source_position, listener_position, portals, profile
	)
	if not portal_route.is_empty():
		return portal_route
	return _route(
		&"blocked", [source_position, listener_position], direct_distance, 0,
		profile.get_float(&"blocked_loss_db", -18.0),
		profile.get_float(&"blocked_lowpass_hz", 1350.0), source_position, profile
	)


func _find_portal_route(
	source_zone: StringName,
	listener_zone: StringName,
	source_position: Vector3,
	listener_position: Vector3,
	portals: Array[Dictionary],
	profile: AcousticPropagationProfile
) -> Dictionary:
	if source_zone.is_empty() or listener_zone.is_empty():
		return {}
	# A blocked ray within one zone has not crossed a doorway. Without an
	# authored alternate zone path, retain conservative wall transmission.
	if source_zone == listener_zone:
		return {}
	var frontier: Array[Dictionary] = [{
		"zone": source_zone,
		"points": [source_position],
		"distance": 0.0,
		"loss_db": 0.0,
		"hops": 0,
	}]
	var best_cost: Dictionary = {source_zone: 0.0}
	var max_hops := profile.get_int(&"max_portal_hops", 6)
	var max_distance := profile.get_float(&"max_path_meters", 160.0)
	while not frontier.is_empty():
		frontier.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.distance) < float(b.distance))
		var state: Dictionary = frontier.pop_front()
		var zone := StringName(state.zone)
		if zone == listener_zone:
			var points: Array = state.points.duplicate()
			var last_point: Vector3 = points[-1]
			var total_distance := float(state.distance) + last_point.distance_to(listener_position)
			if total_distance > max_distance:
				return {}
			points.append(listener_position)
			return _route(
				&"portal", points, total_distance, int(state.hops), float(state.loss_db),
				profile.get_float(&"portal_lowpass_hz", 7200.0), last_point, profile
			)
		if int(state.hops) >= max_hops:
			continue
		for portal: Dictionary in portals:
			if not bool(portal.get("open", true)):
				continue
			var from_zone := StringName(portal.get("from_zone", ""))
			var to_zone := StringName(portal.get("to_zone", ""))
			var next_zone := StringName()
			if zone == from_zone:
				next_zone = to_zone
			elif zone == to_zone and bool(portal.get("bidirectional", true)):
				next_zone = from_zone
			if next_zone.is_empty():
				continue
			var point: Vector3 = portal.get("position", Vector3.ZERO)
			var previous: Vector3 = state.points[-1]
			var next_distance := float(state.distance) + previous.distance_to(point)
			if next_distance > max_distance:
				continue
			var next_hops := int(state.hops) + 1
			var cost := next_distance + float(next_hops) * 2.0
			if best_cost.has(next_zone) and float(best_cost[next_zone]) <= cost:
				continue
			best_cost[next_zone] = cost
			var next_points: Array = state.points.duplicate()
			next_points.append(point)
			frontier.append({
				"zone": next_zone,
				"points": next_points,
				"distance": next_distance,
				"loss_db": float(state.loss_db)
					+ float(portal.get("loss_db", profile.get_float(&"portal_loss_db", -2.5))),
				"hops": next_hops,
			})
	return {}


func _route(
	kind: StringName,
	points: Array,
	distance: float,
	hops: int,
	volume_db: float,
	lowpass_hz: float,
	emission_position: Vector3,
	profile: AcousticPropagationProfile
) -> Dictionary:
	var speed := maxf(profile.get_float(&"speed_of_sound_mps", 343.0), 1.0)
	return {
		"kind": kind,
		"points": points,
		"distance_m": distance,
		"delay_seconds": distance / speed * profile.get_float(&"delay_scale", 1.0),
		"portal_hops": hops,
		"volume_db": volume_db,
		"lowpass_hz": lowpass_hz,
		"emission_position": emission_position,
	}
