class_name SocomTournamentModel
extends RefCounted

## Pure authoritative model for a 16-squad single-elimination 2v2 tournament
## (docs/GUNFIGHT_TOURNAMENT_PREPLAN.md, docs/SQUARE_DESIGN_LANGUAGE.md).
## No scene, node, or network access: the host drives this from RPCs, and the
## UI renders snapshots. The existing two-faction lobby is NOT replaced — it
## is the match pod this bracket assigns squads into.
##
## Lifecycle: registration -> running (bracket seeded) -> complete.

const SQUAD_SIZE := 2
const MAX_SQUADS := 16
const STATE_REGISTRATION := "registration"
const STATE_RUNNING := "running"
const STATE_COMPLETE := "complete"

# The five Houses of the Square; affiliation is squad flavor, never a side.
const HOUSES: Array[String] = ["SATOR", "AREPO", "TENET", "OPERA", "ROTAS"]

# Standard 16-slot single-elimination pairing: seed vs seed, arranged so the
# top and bottom halves converge in the final. Slots 0-3 render on the
# bracket's left half, slots 4-7 on the right.
const BRACKET_PAIRINGS: Array[Array] = [
	[1, 16], [8, 9], [5, 12], [4, 13], [6, 11], [3, 14], [7, 10], [2, 15],
]

var state: String = STATE_REGISTRATION
var squads: Dictionary = {}
var _squad_order: Array[String] = []
var pods: Array[Dictionary] = []
var _next_pod_number := 1


# --- Registration ---------------------------------------------------------


func register_squad(squad_name: String, captain_peer_id: int, house: String = "") -> Dictionary:
	if state != STATE_REGISTRATION:
		return {"ok": false, "reason": "REGISTRATION CLOSED"}
	var clean_name := squad_name.strip_edges()
	if clean_name.is_empty() or clean_name.length() > 24:
		return {"ok": false, "reason": "INVALID SQUAD NAME"}
	if squads.size() >= MAX_SQUADS:
		return {"ok": false, "reason": "BRACKET FULL"}
	for raw_squad: Variant in squads.values():
		if int((raw_squad as Dictionary).get("captain", 0)) == captain_peer_id:
			return {"ok": false, "reason": "ALREADY CAPTAIN"}
	var clean_house := house.to_upper()
	if clean_house != "" and not HOUSES.has(clean_house):
		clean_house = ""
	var squad_id := "squad_%d" % (squads.size() + 1)
	squads[squad_id] = {
		"id": squad_id,
		"name": clean_name,
		"house": clean_house,
		"captain": captain_peer_id,
		"members": [captain_peer_id],
		"ready": false,
		"seed": 0,
		"last_faction": -1,
	}
	_squad_order.append(squad_id)
	return {"ok": true, "squad_id": squad_id}


func join_squad(squad_id: String, peer_id: int) -> Dictionary:
	if state != STATE_REGISTRATION:
		return {"ok": false, "reason": "REGISTRATION CLOSED"}
	if not squads.has(squad_id):
		return {"ok": false, "reason": "NO SUCH SQUAD"}
	var squad: Dictionary = squads[squad_id]
	if (squad["members"] as Array).has(peer_id):
		return {"ok": false, "reason": "ALREADY MEMBER"}
	if (squad["members"] as Array).size() >= SQUAD_SIZE:
		return {"ok": false, "reason": "SQUAD FULL"}
	for raw_squad: Variant in squads.values():
		var other := raw_squad as Dictionary
		if String(other.get("id", "")) != squad_id and (other.get("members", []) as Array).has(peer_id):
			return {"ok": false, "reason": "ALREADY IN A SQUAD"}
	(squad["members"] as Array).append(peer_id)
	return {"ok": true}


func set_squad_ready(squad_id: String, ready: bool) -> Dictionary:
	if not squads.has(squad_id):
		return {"ok": false, "reason": "NO SUCH SQUAD"}
	squads[squad_id]["ready"] = ready
	return {"ok": true}


func registration_ready_to_lock() -> bool:
	if squads.size() != MAX_SQUADS:
		return false
	for raw_squad: Variant in squads.values():
		var squad := raw_squad as Dictionary
		if (squad["members"] as Array).size() != SQUAD_SIZE or not bool(squad["ready"]):
			return false
	return true


# --- Lock and bracket seeding ---------------------------------------------


## Locks registration and seeds the bracket. Seeds follow registration order
## (external ratings can reorder _squad_order before locking). The pairing
## template is fixed, so a given order always yields the same bracket.
func lock_registration() -> Dictionary:
	if state != STATE_REGISTRATION:
		return {"ok": false, "reason": "ALREADY LOCKED"}
	if not registration_ready_to_lock():
		return {"ok": false, "reason": "NOT READY"}
	for seed_index: int in _squad_order.size():
		squads[_squad_order[seed_index]]["seed"] = seed_index + 1
	pods.clear()
	_next_pod_number = 1
	for pairing: Array in BRACKET_PAIRINGS:
		pods.append(_make_pod(1, pods.size(), int(pairing[0]), int(pairing[1])))
	var round_sizes: Array[int] = [4, 2, 1]
	for offset: int in round_sizes.size():
		for slot: int in round_sizes[offset]:
			pods.append(_make_pod(offset + 2, slot, 0, 0))
	state = STATE_RUNNING
	return {"ok": true, "pods": pods.size()}


func _make_pod(round_number: int, slot: int, seed_a: int, seed_b: int) -> Dictionary:
	var number := _next_pod_number
	_next_pod_number += 1
	return {
		"number": number,
		"round": round_number,
		"slot": slot,
		"display_side": 0 if slot < 4 else 1,
		"seed_a": seed_a,
		"seed_b": seed_b,
		"squad_a": _squad_for_seed(seed_a),
		"squad_b": _squad_for_seed(seed_b),
		"winner": "",
		"state": "pending",
		"factions": {},
	}


func _squad_for_seed(seed: int) -> String:
	if seed <= 0 or seed > _squad_order.size():
		return ""
	return _squad_order[seed - 1]


# --- Pods, factions, advancement -------------------------------------------


## Assigns a pending pod's squads onto the map's two factions (team ids 0 and
## 1). Sides alternate round over round per squad, so no squad camps one face
## of the Square across the tournament.
func open_pod(number: int) -> Dictionary:
	var pod := _pod_by_number(number)
	if pod.is_empty():
		return {"ok": false, "reason": "NO SUCH POD"}
	if String(pod["state"]) != "pending" or String(pod["squad_a"]).is_empty() or String(pod["squad_b"]).is_empty():
		return {"ok": false, "reason": "POD NOT READY"}
	var faction_a := _faction_for(pod, "squad_a")
	var faction_b := 1 - faction_a
	var assignments := {}
	assignments[faction_a] = String(pod["squad_a"])
	assignments[faction_b] = String(pod["squad_b"])
	pod["factions"] = assignments
	pod["state"] = "live"
	squads[pod["squad_a"]]["last_faction"] = faction_a
	squads[pod["squad_b"]]["last_faction"] = faction_b
	return {"ok": true, "faction_0": assignments[0], "faction_1": assignments[1]}


func _faction_for(pod: Dictionary, squad_key: String) -> int:
	var squad_id := String(pod[squad_key])
	var last := int(squads[squad_id]["last_faction"])
	var base := 0 if squad_key == "squad_a" else 1
	if int(pod["round"]) >= 2 and last == base:
		return 1 - base
	return base


## Reports a completed pod and advances the winner. Only callable on a live
## pod; the winner must be one of its two squads.
func report_pod_result(number: int, winner_squad_id: String) -> Dictionary:
	var pod := _pod_by_number(number)
	if pod.is_empty():
		return {"ok": false, "reason": "NO SUCH POD"}
	if String(pod["state"]) != "live":
		return {"ok": false, "reason": "POD NOT LIVE"}
	if winner_squad_id != String(pod["squad_a"]) and winner_squad_id != String(pod["squad_b"]):
		return {"ok": false, "reason": "WINNER NOT IN POD"}
	pod["winner"] = winner_squad_id
	pod["state"] = "reported"
	if not _advance_winner(pod):
		state = STATE_COMPLETE
	return {"ok": true, "complete": state == STATE_COMPLETE}


func _advance_winner(pod: Dictionary) -> bool:
	var round_number := int(pod["round"])
	if round_number >= 4:
		return false
	var next_pods := _pods_in_round(round_number + 1)
	var slot := int(pod["slot"])
	var next: Dictionary = next_pods[slot / 2]
	var winner_seed := int(pod["seed_a"]) if String(pod["winner"]) == String(pod["squad_a"]) else int(pod["seed_b"])
	if slot % 2 == 0:
		next["seed_a"] = winner_seed
		next["squad_a"] = String(pod["winner"])
	else:
		next["seed_b"] = winner_seed
		next["squad_b"] = String(pod["winner"])
	return true


func _pod_by_number(number: int) -> Dictionary:
	for pod: Dictionary in pods:
		if int(pod["number"]) == number:
			return pod
	return {}


func _pods_in_round(round_number: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pod: Dictionary in pods:
		if int(pod["round"]) == round_number:
			result.append(pod)
	return result


# --- Snapshots --------------------------------------------------------------


func snapshot() -> Dictionary:
	return {
		"state": state,
		"squads": squads.duplicate(true),
		"pods": pods.duplicate(true),
		"champion": champion(),
	}


func champion() -> String:
	if state != STATE_COMPLETE:
		return ""
	for pod: Dictionary in pods:
		if int(pod["round"]) == 4:
			return String(pod["winner"])
	return ""
