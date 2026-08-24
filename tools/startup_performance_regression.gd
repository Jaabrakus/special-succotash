extends SceneTree

const TrainingScene := preload("res://main.tscn")
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const Warmup := preload("res://scripts/runtime/playable_resource_warmup.gd")
const Mannequin := preload("res://scripts/player/test_mannequin.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var active_map := MapDocument.load_active()
	var warmup_started := Time.get_ticks_usec()
	await Warmup.warm_for_play(self, "res://main.tscn", active_map)
	var warmup_ms := float(Time.get_ticks_usec() - warmup_started) / 1000.0
	_expect(
		Warmup.last_requested_paths.has("res://main.tscn"),
		"warmup includes the playable scene"
	)
	_expect(
		Warmup.last_requested_paths.has(
			"res://assets/textures/environment/original_materials/warm_masonry_albedo_v1.png"
		),
		"warmup includes large authored map materials"
	)
	_expect(
		ResourceLoader.exists(
			"res://assets/animations/cache/operator_animation_library.res"
		),
		"the playable build ships a processed operator animation cache"
	)
	ProjectSettings.set_setting("socom/session/public_training", true)
	var startup_started := Time.get_ticks_usec()
	var training := TrainingScene.instantiate()
	root.add_child(training)
	var startup_ms := float(Time.get_ticks_usec() - startup_started) / 1000.0
	await process_frame
	var player := training.get_node_or_null("Player")
	var driver = training.find_child("ProductionAnimation", true, false)
	_expect(player != null, "warmed playable startup creates the authoritative player")
	_expect(driver != null, "warmed playable startup adopts the cached operator rig")
	var first_library = driver.get("dynamic_anim_lib") if driver != null else null
	var replica := Mannequin.new()
	replica.name = "StartupCacheReplica"
	root.add_child(replica)
	var replica_driver = replica.get("production_animation")
	var replica_library = (
		replica_driver.get("dynamic_anim_lib") if replica_driver != null else null
	)
	_expect(
		first_library != null and first_library == replica_library,
		"additional lobby operators share one processed animation library"
	)
	_expect(
		Warmup.held_resources.is_empty(),
		"temporary warm references release only after playable startup adopts them"
	)
	print("STARTUP_PERFORMANCE_METRIC warmup_ms=%.2f playable_ready_ms=%.2f resources=%d" % [
		warmup_ms,
		startup_ms,
		Warmup.last_requested_paths.size(),
	])
	training.queue_free()
	replica.queue_free()
	await process_frame
	if failures.is_empty():
		print("STARTUP_PERFORMANCE_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("STARTUP_PERFORMANCE_REGRESSION: %s" % failure)
	quit(1)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
