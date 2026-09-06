class_name SocomArenaRuntimePlan
extends RefCounted

## Reads the tournament domain owner only; never receives the multiplayer scene.
static func peers(session, arena_id: int) -> Array[int]:
	var result: Array[int] = []
	if session == null or arena_id < 0 or arena_id >= session.coordinator.active_arena_count:
		return result
	var match = session.coordinator.arena_sub_matches[arena_id]
	for raw_id in match.pair_a_peers + match.pair_b_peers:
		if int(raw_id) > 0:
			result.append(int(raw_id))
	return result

static func roster(session, arena_id: int) -> Array:
	var result: Array = []
	for peer_id in peers(session, arena_id):
		result.append({"peer_id": peer_id, "team": int(session.team_for_peer(peer_id)),
			"spawn": Vector3(session.spawn_for_peer(peer_id))})
	return result

static func deployment(session, arena_id: int) -> Array:
	var result := roster(session, arena_id)
	if result.is_empty():
		return result
	var match = session.coordinator.arena_sub_matches[arena_id]
	for entry: Dictionary in result:
		entry["combat_eligible"] = match.is_peer_combat_eligible(int(entry.peer_id))
	return result
