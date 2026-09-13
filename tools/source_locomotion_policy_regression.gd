extends SceneTree

## Read-only proof of the native range inputs and explicitly linear adapter.
## The source controller graph owns selection; this test has no gameplay writer.
## Cached Animation metadata is restored after each malformed-input case and
## is never saved. Original PS2 weighting/phase-contact parity is not asserted.
const Policy := preload("res://scripts/player/operator_source_locomotion_policy.gd")
const Profile := preload("res://scripts/player/operator_animation_profile.gd")
const Graph := preload("res://scripts/player/operator_locomotion_blend_tree.gd")
const RANGES := {
	"walk/forward": Vector2(0.0, 4.0), "walk/backward": Vector2(0.0, 2.8),
	"walk/left": Vector2(0.0, 2.3), "walk/right": Vector2(0.0, 2.8),
	"jog/forward": Vector2(2.0, 6.15), "jog/backward": Vector2(2.0, 3.7),
	"jog/left": Vector2(0.9, 4.5), "jog/right": Vector2(1.0, 5.0),
	"run/forward": Vector2(4.01, 6.5), "run/backward": Vector2(2.0, 3.7),
	"run/left": Vector2(2.5, 6.5), "run/right": Vector2(3.0, 6.5),
}
var failures: Array[String] = []
var completed_cases := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	var profile := Profile.new()
	profile.load_project_map()
	var graph := Graph.new()
	graph.profile = profile
	graph.modern_enabled = true
	graph.weapon_handling_profile = {"family": "TWO_HAND_RIFLE"}
	graph._configure_source_controller(profile.clip_paths)
	var policy = graph.source_policy
	_check(policy.complete(), "all twelve canonical rifle slots supply valid native ranges")
	_check(policy.entries.get("walk/forward", {}).get("source") == "seal_walk_alert", "saved rifle forward walk uses source alert walk")
	_check(policy.entries.get("jog/forward", {}).get("source") == "seal_jog_alert", "saved rifle forward jog uses source alert jog")
	for key: String in RANGES:
		var entry: Dictionary = policy.entries.get(key, {})
		_check(is_equal_approx(float(entry.get("start", -1.0)), RANGES[key].x) and is_equal_approx(float(entry.get("end", -1.0)), RANGES[key].y), "verified native A/B range " + key)
	_check_weights(policy)
	_check_invalid_metadata(profile)
	_check_preflight(graph, profile)
	_check(completed_cases == 3, "all policy cases finish without interrupted calls")
	print("SOURCE_LOCOMOTION_POLICY_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " native_ranges=", RANGES.size(), " ", failures)
	quit(0 if failures.is_empty() else 1)


func _check_weights(policy: RefCounted) -> void:
	_check(policy.selected_clip(Vector2(0, 1), 0.0, 0.0) == &"source_walk_alert", "pure walk selects saved source alert clip")
	_check(policy.selected_clip(Vector2(0, 1), 1.0, 0.0) == &"jog_forward", "pure jog selects saved source jogging clip")
	_check(policy.selected_clip(Vector2(0, 1), 0.0, 1.0) == &"run_forward", "pure run selects canonical running clip")
	_check(policy.selected_clip(Vector2.LEFT, 1.0, 0.0) == &"jog_left", "lateral jog selection follows native left strafe")
	_check(policy.tier_blends(Vector2(0, 1), 2.0) == Vector2.ZERO, "forward jog starts at two meters per second")
	_check(policy.tier_blends(Vector2(0, 1), 6.5) == Vector2.ONE, "forward reaches full run at 6.5 meters per second")
	_check(policy.tier_blends(Vector2.LEFT, 4.5).is_equal_approx(Vector2(1.0, 0.5)), "left source range reaches jog and half run at 4.5")
	_check(policy.tier_blends(Vector2(0, -1), 2.85).is_equal_approx(Vector2(0.5, 0.5)), "backward shared A/B range gives equal jog/run blend amounts")
	for frame in 72:
		var direction := Vector2.from_angle(float(frame) * TAU / 72.0)
		var weights: Dictionary = Policy.directional_weights(direction)
		var sum := 0.0
		for weight: float in weights.values():
			_check(is_finite(weight) and weight >= 0.0 and weight <= 1.0, "direction weights are finite bounded")
			sum += weight
		_check(absf(sum - 1.0) < 0.000001, "direction weights form a partition of unity")
		for speed: float in [-1.0, 0.0, 2.0, 4.0, 6.5, 100.0]:
			var tiers: Vector2 = policy.tier_blends(direction, speed)
			_check(tiers.is_finite() and tiers.x >= 0.0 and tiers.x <= 1.0 and tiers.y >= 0.0 and tiers.y <= 1.0, "all cardinal/diagonal speed bands remain finite bounded")
			var shifted: Vector2 = policy.tier_blends(direction * 0.25, speed)
			_check(tiers.is_equal_approx(shifted), "heading weights do not multiply analog speed twice")
	var diagonal: Vector2 = policy.tier_blends(Vector2(-1, 1), 4.0)
	var cardinal_mean: Vector2 = (policy.tier_blends(Vector2.LEFT, 4.0) + policy.tier_blends(Vector2(0, 1), 4.0)) * 0.5
	_check(diagonal.is_equal_approx(cardinal_mean), "equal diagonal interpolates its two cardinal source ranges")
	for direction in [Vector2(NAN, 0), Vector2(INF, 0)]:
		_check(policy.tier_blends(direction, 4.0) == Vector2.ZERO, "invalid heading fails closed")
	for speed: float in [NAN, INF, -INF]:
		_check(policy.tier_blends(Vector2(0, 1), speed) == Vector2.ZERO, "invalid speed fails closed")
	var incomplete := Policy.new()
	incomplete.entries = policy.entries.duplicate(true)
	incomplete.entries.erase("jog/left")
	_check(not incomplete.complete() and incomplete.tier_blends(Vector2.LEFT, 6.5) == Vector2.ZERO, "incomplete cardinal metadata fails closed")
	completed_cases += 1


func _check_invalid_metadata(profile: RefCounted) -> void:
	var path := String(profile.clip_paths[&"jog_forward"])
	var animation := load(path) as Animation
	var original_marker: Variant = animation.get_meta("seal_reference")
	var original_settings: Variant = animation.get_meta("source_settings")
	for row: Dictionary in [
		{"label": "false source marker", "marker": false, "settings": {"transition_speed_A": 1.0, "transition_speed_B": 4.0}},
		{"label": "nonboolean source marker", "marker": "true", "settings": {"transition_speed_A": 1.0, "transition_speed_B": 4.0}},
		{"label": "nondictionary settings", "marker": true, "settings": []},
		{"label": "missing range endpoint", "marker": true, "settings": {"transition_speed_A": 1.0}},
		{"label": "nonnumeric range", "marker": true, "settings": {"transition_speed_A": "1.0", "transition_speed_B": 4.0}},
		{"label": "negative range", "marker": true, "settings": {"transition_speed_A": -1.0, "transition_speed_B": 4.0}},
		{"label": "empty range", "marker": true, "settings": {"transition_speed_A": 4.0, "transition_speed_B": 4.0}},
		{"label": "reversed range", "marker": true, "settings": {"transition_speed_A": 4.0, "transition_speed_B": 1.0}},
		{"label": "nonfinite start", "marker": true, "settings": {"transition_speed_A": NAN, "transition_speed_B": 4.0}},
		{"label": "nonfinite endpoint", "marker": true, "settings": {"transition_speed_A": 1.0, "transition_speed_B": INF}},
	]:
		animation.set_meta("seal_reference", row.marker)
		animation.set_meta("source_settings", row.settings)
		var policy := Policy.new()
		policy.register(&"jog", &"forward", &"jog_forward", path)
		animation.set_meta("seal_reference", original_marker)
		animation.set_meta("source_settings", original_settings)
		_check(policy.entries.is_empty(), String(row.label) + " is rejected")
	var missing := Policy.new()
	missing.register(&"jog", &"forward", &"missing", "res://assets/animations/missing-source-range.tres")
	_check(missing.entries.is_empty(), "missing resource is rejected")
	completed_cases += 1


func _check_preflight(graph: RefCounted, profile: RefCounted) -> void:
	graph._configure_source_controller(profile.clip_paths)
	_check(graph.source_controller_active, "valid source metadata activates the complete graph")
	profile.locomotion.source_three_tier = false
	graph._configure_source_controller(profile.clip_paths)
	_check(not graph.source_controller_active, "disabled source opt-in preserves prior graph")
	profile.locomotion.source_three_tier = true
	profile.locomotion.preserve_source_locomotion = false
	graph._configure_source_controller(profile.clip_paths)
	_check(not graph.source_controller_active, "non-source presentation preserves prior graph")
	profile.locomotion.preserve_source_locomotion = true
	graph.modern_enabled = false
	graph._configure_source_controller(profile.clip_paths)
	_check(not graph.source_controller_active, "legacy animation route preserves prior graph")
	graph.modern_enabled = true
	graph.weapon_handling_profile.family = "TWO_HAND_PISTOL"
	graph._configure_source_controller(profile.clip_paths)
	_check(not graph.source_controller_active, "pistol route preserves prior graph")
	graph.weapon_handling_profile.family = "TWO_HAND_RIFLE"
	var available: Dictionary = {&"run_forward": profile.clip_paths[&"run_forward"]}
	available.merge(profile.clip_paths)
	available.erase(&"jog_left")
	graph._configure_source_controller(available)
	_check(not graph.source_controller_active, "missing jog cannot become an arbitrary first available source clip")
	var original_path := String(profile.clip_paths[&"jog_forward"])
	profile.clip_paths[&"jog_forward"] = "res://assets/animations/missing-source-range.tres"
	graph._configure_source_controller(profile.clip_paths)
	_check(not graph.source_controller_active and graph.source_grounded_clip == &"", "missing source metadata disables graph and clears stale selection")
	profile.clip_paths[&"jog_forward"] = original_path
	graph._configure_source_controller(profile.clip_paths)
	_check(graph.source_controller_active, "restored valid metadata can enable the graph again")
	profile.load_project_map("res://config/animation_presets/seal_pistol_hybrid.json")
	graph._configure_source_controller(profile.clip_paths)
	_check(not graph.source_controller_active and not bool(profile.locomotion.get("source_three_tier", false)), "older preset clears source opt-in")
	completed_cases += 1


func _check(condition: bool, label: String) -> void:
	if not condition and not failures.has(label):
		failures.append(label)
		push_error("SOURCE_LOCOMOTION_POLICY " + label)
