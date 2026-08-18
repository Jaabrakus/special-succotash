extends SceneTree

const AudioEngine := preload("res://scripts/audio/lab_leak_audio_engine.gd")
const TargetDummy := preload("res://scripts/combat/lab_leak_target_dummy.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	AudioEngine.initialize(host)
	var audio_before := AudioEngine.get_cached_resource_ids()
	for index in range(96):
		AudioEngine.play_hit_confirm(self, index % 8 == 0)
	var audio_after := AudioEngine.get_cached_resource_ids()
	_expect(audio_before == audio_after, "hit audio reuses the startup stream and voice pools")

	var dummy := TargetDummy.new()
	dummy.max_health = 1000000.0
	dummy.current_health = dummy.max_health
	host.add_child(dummy)
	for _frame in range(4):
		await process_frame
	var material_before: Dictionary = dummy.get_cached_hit_feedback_ids()
	var start_usec := Time.get_ticks_usec()
	for index in range(256):
		dummy.take_bullet_damage_region(
			1.0,
			&"HEAD" if index % 8 == 0 else &"TORSO",
			dummy.global_position + Vector3.UP,
			Vector3.UP,
			Vector3(0.0, 1.0, 4.0)
		)
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	var material_after: Dictionary = dummy.get_cached_hit_feedback_ids()
	_expect(material_before == material_after, "repeated impacts reuse the dummy's three cached materials")
	_expect(int(material_after.get("meshes", 0)) > 0, "cached material swaps cover the visible target meshes")
	_expect(elapsed_usec < 250000, "256 hit reactions finish without a hit-path performance spike")
	print("HIT_FEEDBACK_BENCHMARK 256_hits_usec=", elapsed_usec)

	AudioEngine.shutdown()
	host.queue_free()
	await process_frame
	await process_frame
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("HIT_FEEDBACK_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("HIT_FEEDBACK_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("HIT_FEEDBACK_PERFORMANCE_REGRESSION PASS")
		quit(0)
	else:
		print("HIT_FEEDBACK_PERFORMANCE_REGRESSION FAIL ", failures)
		quit(1)
