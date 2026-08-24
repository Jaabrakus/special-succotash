class_name SocomMotionMatchingPoseSearch
extends RefCounted

## Data-only pose search. CharacterBody3D remains authoritative. This class
## selects presentation frames and never moves the player, weapon, or camera.

const REQUIRED_FEATURES := [
	&"velocity", &"future_velocity", &"facing_delta",
	&"left_foot_position", &"right_foot_position",
	&"left_foot_velocity", &"right_foot_velocity",
]

var weights: Dictionary = {}
var samples: Array[Dictionary] = []
var continuing_pose_bias := 0.18
var minimum_switch_improvement := 0.08


func configure(schema: Dictionary, database: Array[Dictionary]) -> Array[String]:
	weights = (schema.get("weights", {}) as Dictionary).duplicate(true)
	continuing_pose_bias = maxf(float(schema.get("continuing_pose_bias", 0.18)), 0.0)
	minimum_switch_improvement = maxf(float(schema.get("minimum_switch_improvement", 0.08)), 0.0)
	samples.clear()
	var errors: Array[String] = []
	for feature in REQUIRED_FEATURES:
		if float(weights.get(String(feature), 0.0)) <= 0.0:
			errors.append("missing positive weight: %s" % feature)
	for index in range(database.size()):
		var sample := database[index]
		if String(sample.get("clip", "")).is_empty():
			errors.append("sample %d has no clip" % index)
			continue
		samples.append(sample.duplicate(true))
	return errors


func search(query: Dictionary, context: Dictionary = {}) -> Dictionary:
	var allowed_posture := StringName(context.get("posture", &""))
	var allowed_gait := StringName(context.get("gait", &""))
	var allowed_family := StringName(context.get("weapon_family", &""))
	var current_clip := StringName(context.get("current_clip", &""))
	var current_time := float(context.get("current_time", 0.0))
	var best: Dictionary = {}
	var best_cost := INF
	var continuing_cost := INF
	for sample in samples:
		if not _matches_context(sample, allowed_posture, allowed_gait, allowed_family):
			continue
		var cost := _feature_cost(query, sample)
		var is_continuing := (
			StringName(sample.get("clip", &"")) == current_clip
			and float(sample.get("time", 0.0)) >= current_time
		)
		if is_continuing:
			cost = maxf(0.0, cost - continuing_pose_bias)
			continuing_cost = minf(continuing_cost, cost)
		if cost < best_cost:
			best_cost = cost
			best = sample
	if best.is_empty():
		return {"matched": false, "reason": "NO_CONTEXT_CANDIDATES"}
	var switched := StringName(best.get("clip", &"")) != current_clip
	if switched and continuing_cost < INF and best_cost + minimum_switch_improvement >= continuing_cost:
		for sample in samples:
			if (
				StringName(sample.get("clip", &"")) == current_clip
				and _matches_context(sample, allowed_posture, allowed_gait, allowed_family)
			):
				var candidate_cost := _feature_cost(query, sample) - continuing_pose_bias
				if candidate_cost <= continuing_cost + 0.0001:
					best = sample
					best_cost = candidate_cost
					switched = false
					break
	return {
		"matched": true,
		"clip": StringName(best.get("clip", &"")),
		"time": float(best.get("time", 0.0)),
		"cost": best_cost,
		"switched": switched,
		"posture": StringName(best.get("posture", &"")),
		"gait": StringName(best.get("gait", &"")),
		"sample_id": StringName(best.get("id", &"")),
	}


func _matches_context(
	sample: Dictionary,
	posture: StringName,
	gait: StringName,
	weapon_family: StringName
) -> bool:
	return (
		(posture == &"" or StringName(sample.get("posture", &"")) == posture)
		and (gait == &"" or StringName(sample.get("gait", &"")) == gait)
		and (
			weapon_family == &""
			or StringName(sample.get("weapon_family", &"")) == weapon_family
		)
	)


func _feature_cost(query: Dictionary, sample: Dictionary) -> float:
	var total := 0.0
	for feature in REQUIRED_FEATURES:
		var key := String(feature)
		var weight := float(weights.get(key, 0.0))
		var query_value: Variant = query.get(key, Vector2.ZERO)
		var sample_value: Variant = sample.get(key, query_value)
		total += weight * _squared_distance(query_value, sample_value)
	return total


func _squared_distance(a: Variant, b: Variant) -> float:
	if a is Vector3 and b is Vector3:
		return (a as Vector3).distance_squared_to(b as Vector3)
	if a is Vector2 and b is Vector2:
		return (a as Vector2).distance_squared_to(b as Vector2)
	return pow(float(a) - float(b), 2.0)
