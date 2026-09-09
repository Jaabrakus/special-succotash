extends SceneTree

const AnimationProfile := preload(
	"res://scripts/player/operator_animation_profile.gd"
)
const AnimationLibraryCache := preload(
	"res://scripts/player/operator_animation_library_cache.gd"
)
const StateCollector := preload(
	"res://scripts/runtime/playtest_state_collector.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	var test_profile = AnimationProfile.new()
	test_profile.load_project_map()
	var test_fingerprint := AnimationLibraryCache.new().fingerprint_for(test_profile)
	_expect(
		test_fingerprint == _canonical_fingerprint(test_profile),
		"the cache fingerprint uses lexical String ordering"
	)

	var collector = root.get_node_or_null("PlaytestStateCollector")
	if collector == null:
		collector = StateCollector.new()
		collector.name = "PlaytestStateCollector"
		root.add_child(collector)
	var collected: Dictionary = collector.call("collect_saved_state")
	_expect(
		bool(collected.get("ok", false)),
		"the launcher can collect the canonical saved animation map"
	)
	var launcher_profile = AnimationProfile.new()
	launcher_profile.load_project_map()
	var launcher_fingerprint := AnimationLibraryCache.new().fingerprint_for(
		launcher_profile
	)
	_expect(
		launcher_fingerprint == test_fingerprint,
		"launcher-collected and direct test profiles share one fingerprint"
	)

	var ensured: Dictionary = collector.call("ensure_saved_state")
	_expect(
		bool(ensured.get("ok", false)),
		"canonical main can consume the collected saved-state bundle"
	)
	var main_profile = AnimationProfile.new()
	main_profile.load_project_map()
	var main_fingerprint := AnimationLibraryCache.new().fingerprint_for(main_profile)
	_expect(
		main_fingerprint == test_fingerprint,
		"canonical-main and direct test profiles share one fingerprint"
	)

	var reordered_profile = AnimationProfile.new()
	reordered_profile.load_project_map()
	for property_name in [
		"clip_paths",
		"mirrored_clips",
		"leg_mirrored_clips",
		"clip_aliases",
	]:
		_reverse_dictionary(reordered_profile, property_name)
	_expect(
		AnimationLibraryCache.new().fingerprint_for(reordered_profile)
			== test_fingerprint,
		"dictionary insertion order cannot change the cache fingerprint"
	)

	_expect(
		OS.get_cmdline_user_args().has("--build-animation-cache"),
		"the cache regression runs with --build-animation-cache"
	)
	if OS.get_cmdline_user_args().has("--build-animation-cache"):
		# Seed the exact fast path that previously made a packaged build return
		# before OperatorAssetRuntime could rebuild and call store().
		AnimationLibraryCache.shared_libraries.clear()
		AnimationLibraryCache.shared_sources.clear()
		var seeded_library := AnimationLibrary.new()
		seeded_library.add_animation(&"seeded_cache", Animation.new())
		AnimationLibraryCache.shared_libraries[test_fingerprint] = seeded_library
		var animation_player := AnimationPlayer.new()
		var adopted: Dictionary = AnimationLibraryCache.new().adopt(
			test_profile,
			animation_player
		)
		_expect(
			adopted.is_empty(),
			"packaged build mode bypasses an adoptable in-memory cache"
		)
		_expect(
			animation_player.get_animation_library_list().is_empty(),
			"packaged build mode leaves the builder ready to publish a new library"
		)
		animation_player.free()

	collector.call("deactivate_bundle")
	if failures.is_empty():
		print("OPERATOR_ANIMATION_CACHE_REGRESSION PASS fingerprint=%s" % test_fingerprint)
		quit(0)
		return
	for failure in failures:
		push_error("OPERATOR_ANIMATION_CACHE_REGRESSION: %s" % failure)
	quit(1)


func _reverse_dictionary(profile, property_name: String) -> void:
	var source: Dictionary = profile.get(property_name) as Dictionary
	var names: Array = source.keys()
	names.reverse()
	var reversed: Dictionary = {}
	for name in names:
		reversed[name] = source[name]
	profile.set(property_name, reversed)


func _canonical_fingerprint(profile) -> String:
	var entries: Array[String] = [
		"schema:%d" % AnimationLibraryCache.CACHE_SCHEMA,
	]
	entries.append("target_rig:" + FileAccess.get_sha256(AnimationLibraryCache.TARGET_RIG_PATH))
	entries.append("source_jump:" + JSON.stringify(profile.source_jump))
	entries.append("gait_alignment:%s:%s" % [profile.locomotion.get("grounded_gait_alignment", false), profile.locomotion.get("gait_support_height_m", 0.05)])
	var clip_names: Array[String] = []
	for raw_clip_name in profile.clip_paths.keys():
		clip_names.append(String(raw_clip_name))
	clip_names.sort()
	for clip_name_text in clip_names:
		var clip_name := StringName(clip_name_text)
		entries.append("%s=%s:%s:%.4f" % [
			clip_name_text,
			String(profile.clip_paths[clip_name]),
			str(profile.is_looping(clip_name)),
			profile.pose_yaw_offset_degrees(clip_name),
		])
	for property_name in ["mirrored_clips", "leg_mirrored_clips", "clip_aliases"]:
		var routes: Dictionary = profile.get(property_name) as Dictionary
		var route_names: Array[String] = []
		for raw_route_name in routes.keys():
			route_names.append(String(raw_route_name))
		route_names.sort()
		for route_name in route_names:
			entries.append("%s:%s=%s" % [
				property_name,
				route_name,
				String(routes[StringName(route_name)]),
			])
	return "|".join(entries).sha256_text()


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
