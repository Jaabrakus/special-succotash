extends SceneTree

const TracerSystem := preload("res://scripts/weapons/lab_leak_tracer_system.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var stage := Node3D.new()
	stage.name = "BodyHitVfxRegressionStage"
	root.add_child(stage)
	current_scene = stage
	TracerSystem.initialize(stage)
	var blood_emitters := stage.find_children(
		"PooledBloodEmitter_*", "CPUParticles3D", true, false
	)
	var blood_marks := stage.find_children(
		"PooledBloodEntry_*", "MeshInstance3D", true, false
	)
	_expect(blood_emitters.size() == 8, "body-hit particles are preallocated")
	_expect(blood_marks.size() == 32, "red entry marks are preallocated")
	TracerSystem.spawn_body_hit_effect(
		self, Vector3(1.0, 1.4, -2.0), Vector3.FORWARD, true
	)
	await process_frame
	var active_emitter := blood_emitters[0] as CPUParticles3D
	var active_mark := blood_marks[0] as MeshInstance3D
	_expect(active_emitter.emitting, "confirmed damage starts directional blood particles")
	_expect(active_emitter.amount == 14, "head damage uses the stronger bounded splatter")
	_expect(active_mark.visible, "confirmed damage shows a red bullet-entry mark")
	var expected_mark_position := Vector3(1.0, 1.4, -2.0) + Vector3.FORWARD * 0.006
	_expect(
		active_mark.global_position.distance_to(expected_mark_position) <= 0.001,
		"entry mark is offset from the confirmed hit surface"
	)
	stage.queue_free()
	if failures.is_empty():
		print("BODY_HIT_VFX_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("BODY_HIT_VFX_CHECK FAIL %s" % failure)
	quit(1)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
