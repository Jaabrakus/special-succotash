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
	_expect(material_before == material_after, "repeated impacts preserve the normal body material")
	_expect(int(material_after.get("meshes", 0)) > 0, "visible target meshes are checked")
	_expect(dummy.current_health < dummy.max_health, "bullet damage remains active")
	for mesh in dummy.soldier_meshes:
		_expect(mesh.material_override == dummy.normal_material, "ordinary and critical bullets never highlight the body")
	var health_before := dummy.current_health
	dummy.take_explosion_damage(10.0, Vector3.ZERO)
	_expect(dummy.current_health == health_before - 10.0, "explosion damage remains active")
	for mesh in dummy.soldier_meshes:
		_expect(mesh.material_override == dummy.normal_material and not dummy.normal_material.emission_enabled, "explosions do not highlight the body")
	var reticle := preload("res://scripts/ui/socom_dynamic_reticle.gd").new()
	root.add_child(reticle)
	reticle.notify_hit()
	_expect(is_equal_approx(reticle.hit_marker_timer, 0.15), "red hit X still activates")
	if "--render" in OS.get_cmdline_user_args():
		reticle.set_process(false)
		reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var camera := Camera3D.new()
		host.add_child(camera)
		camera.position = Vector3(0, 1.3, 4)
		camera.look_at(Vector3(0, 1.0, 0))
		camera.current = true
		var light := DirectionalLight3D.new()
		host.add_child(light)
		light.rotation_degrees = Vector3(-30, -30, 0)
		light.light_energy = 2.0
		dummy.health_label.visible = false
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/hit-x-no-body-highlight.png")
	reticle.queue_free()
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
