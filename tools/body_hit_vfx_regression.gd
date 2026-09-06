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
	var blood_smoke := stage.find_children(
		"PooledBloodSmoke_*", "CPUParticles3D", true, false
	)
	_expect(blood_emitters.size() == 8, "body-hit particles are preallocated")
	_expect(blood_marks.size() == 32, "red entry marks are preallocated")
	_expect(blood_smoke.size() == 12, "red blood smoke particles are preallocated")
	TracerSystem.spawn_body_hit_effect(
		self, Vector3(1.0, 1.4, -2.0), Vector3.FORWARD, true
	)
	await process_frame
	var active_emitter := blood_emitters[0] as CPUParticles3D
	var active_mark := blood_marks[0] as MeshInstance3D
	var active_smoke := blood_smoke[0] as CPUParticles3D
	_expect(active_emitter.emitting, "confirmed damage starts directional blood particles")
	_expect(active_emitter.amount == 14, "head damage uses the stronger bounded splatter")
	_expect(active_mark.visible, "confirmed damage shows a red bullet-entry mark")
	_expect(active_smoke.emitting, "confirmed damage starts red blood smoke puff")
	_expect(active_smoke.amount == 10, "head damage uses larger blood smoke amount")
	var smoke_mat := (active_smoke.mesh as QuadMesh).material as StandardMaterial3D
	_expect(
		smoke_mat != null and smoke_mat.albedo_color.r > 0.50 and smoke_mat.albedo_color.g < 0.10,
		"blood smoke is tinted red for blood"
	)
	var expected_mark_position := Vector3(1.0, 1.4, -2.0) + Vector3.FORWARD * 0.006
	_expect(
		active_mark.global_position.distance_to(expected_mark_position) <= 0.001,
		"entry mark is offset from the confirmed hit surface"
	)

	# Verify spawn_impact_effect with is_player routes to blood smoke
	TracerSystem.spawn_impact_effect(
		self, Vector3(2.0, 1.2, -1.0), Vector3.UP, true
	)
	await process_frame
	var second_smoke := blood_smoke[1] as CPUParticles3D
	_expect(second_smoke.emitting, "spawn_impact_effect with is_player triggers red blood smoke")
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
