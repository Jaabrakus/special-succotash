class_name SocomMapGameplayContract
extends RefCounted

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")


static func mission_rules(document: Dictionary) -> Dictionary:
	return MapDocument.normalize_gameplay(document.get("gameplay", {}))


static func round_rules(document: Dictionary) -> Dictionary:
	var rules := mission_rules(document)
	return {
		"time_limit_seconds": int(rules["round_time_seconds"]),
		"maximum_rounds": int(rules["maximum_rounds"]),
		"rounds_to_win": int(rules["rounds_to_win"]),
		"win_by_elimination": bool(rules["elimination_wins_round"]),
		"win_by_bomb_detonation": bool(rules["bomb_detonation_wins_round"]),
		"timeout_result": String(rules["round_timeout_result"]),
	}


static func markers(document: Dictionary, type_name: StringName) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for object: Dictionary in MapDocument.normalize(document).get("objects", []):
		if StringName(object.get("type", "")) == type_name:
			matches.append(object.duplicate(true))
	return matches


static func marker_positions(document: Dictionary, type_name: StringName) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for object: Dictionary in markers(document, type_name):
		positions.append(MapDocument.data_to_vector(object.get("position", {})))
	return positions


static func demolition_layout(document: Dictionary) -> Dictionary:
	return {
		"alpha_spawns": marker_positions(document, &"team_alpha_spawn"),
		"bravo_spawns": marker_positions(document, &"team_bravo_spawn"),
		"bomb_pickups": marker_positions(document, &"bomb_pickup"),
		"alpha_targets": marker_positions(document, &"alpha_bomb_site"),
		"bravo_targets": marker_positions(document, &"bravo_bomb_site"),
		"rules": mission_rules(document),
	}
