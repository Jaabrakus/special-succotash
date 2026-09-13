extends SceneTree

const Graph = preload("res://scripts/player/operator_locomotion_blend_tree.gd")
const NATIVE := "res://assets/animations/seal_reference/"
var failures: Array[String] = []
var fixtures: Array[Resource] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Graph.source_clip_classification_cache.clear()
	for name in ["seal_jog", "seal_jog_alert", "seal_walk_alert02", "seal_stand_alert01", "seal_stand_alert02", "seal_mv_reload", "seal_crouch_reload", "seal_prone_reload"]:
		_check(Graph.is_source_clip(NATIVE + name + ".tres"), "native metadata accepted " + name)
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_animation_map.json"))
	var processed := 0
	for path: String in map.clips.values():
		if path.begins_with("res://assets/animations/seal_gameplay/") or path.begins_with("res://assets/animations/seal_firing_reference/"):
			processed += 1
			_check(Graph.is_source_clip(path), "existing processed source retained " + path)
	_check(processed > 50, "broad existing processed coverage")
	for path in [
		"res://assets/animations/seal_gameplay/jump_coherent_run.tres",
		"res://assets/animations/seal_gameplay/jump_coherent_air.tres",
		"res://assets/animations/seal_gameplay/jump_running_air.tres",
	]:
		var clip := load(path) as Animation
		_check(not clip.has_meta("source_name") and clip.has_meta("source_asset"), "derived jump fixture has indirect provenance")
		_check(Graph.is_source_clip(path), "derived jump remains source")
	for path in [
		"", "seal_jog", "user://assets/animations/seal_reference/seal_jog.tres",
		"res://assets/animations/seal_reference/../mixamo/seal_jog.tres",
		"res://assets/animations/seal_reference_fake/seal_jog.tres",
		NATIVE + "seal_does_not_exist.tres", NATIVE + "seal_jog.fbx",
		"res://assets/animations/seal_gameplay/does_not_exist.tres",
		"res://assets/animations/mixamo/Reloading.fbx",
		"res://assets/external/agls_intake/imported/weapon_reload/ALSP2_Reload_Pistol.scn",
	]:
		_check(not Graph.is_source_clip(path), "foreign/invalid rejected " + path)
	# Unsaved resources exercise metadata validation without replacing any real
	# file. take_over_path makes these fixtures visible to ResourceLoader only
	# in this process; retained references keep them alive during the assertions.
	var absent_marker := _fixture("seal_classification_missing_marker")
	absent_marker.set_meta("source_name", "seal_classification_missing_marker")
	_check(not Graph.is_source_clip(absent_marker.resource_path), "name alone is not source")
	var absent_name := _fixture("seal_classification_missing_name")
	absent_name.set_meta("seal_reference", true)
	_check(not Graph.is_source_clip(absent_name.resource_path), "marker alone is not source")
	var mismatch := _fixture("seal_classification_mismatched_name")
	mismatch.set_meta("seal_reference", true)
	mismatch.set_meta("source_name", "seal_jog")
	_check(not Graph.is_source_clip(mismatch.resource_path), "source name must match native filename")
	var wrong_marker_type := _fixture("seal_classification_string_marker")
	wrong_marker_type.set_meta("seal_reference", "true")
	wrong_marker_type.set_meta("source_name", "seal_classification_string_marker")
	_check(not Graph.is_source_clip(wrong_marker_type.resource_path), "source marker must be boolean")
	var not_animation := Resource.new()
	not_animation.take_over_path(NATIVE + "seal_classification_wrong_resource.tres")
	not_animation.set_meta("seal_reference", true)
	not_animation.set_meta("source_name", "seal_classification_wrong_resource")
	fixtures.append(not_animation)
	_check(not Graph.is_source_clip(not_animation.resource_path), "metadata on non-Animation resource rejected")
	var cached := _fixture("seal_classification_cache_probe")
	cached.set_meta("seal_reference", true)
	cached.set_meta("source_name", "seal_classification_cache_probe")
	_check(Graph.is_source_clip(cached.resource_path), "valid native metadata accepted")
	var cache_count: int = Graph.source_clip_classification_cache.size()
	cached.set_meta("seal_reference", false)
	for index in 1000:
		_check(Graph.is_source_clip(cached.resource_path), "repeat query returns cached classification")
	_check(Graph.source_clip_classification_cache.size() == cache_count, "repeated queries do not grow cache")
	Graph.source_clip_classification_cache.erase(cached.resource_path)
	_check(not Graph.is_source_clip(cached.resource_path), "uncached query rechecks changed metadata")
	print("SOURCE_CLIP_CLASSIFICATION ", "PASS" if failures.is_empty() else "FAIL", " processed_routes=", processed, " cache_entries=", Graph.source_clip_classification_cache.size(), " failures=", failures)
	quit(0 if failures.is_empty() else 1)


func _fixture(name: String) -> Animation:
	var resource := Animation.new()
	resource.take_over_path(NATIVE + name + ".tres")
	fixtures.append(resource)
	return resource


func _check(ok: bool, label: String) -> void:
	if not ok and not label in failures:
		failures.append(label)
