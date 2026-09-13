extends SceneTree

func _init() -> void:
	var rig := preload("res://scripts/camera/socom_camera.gd").new()
	rig.camera = Camera3D.new()
	rig.add_child(rig.camera)
	assert(not rig.profile.pitch_zoom_enabled)
	rig.aim_pitch = -0.6
	for step in 11:
		rig.downward_aim_amount = step / 10.0
		rig.downward_crane_amount = step / 10.0
		rig.current_fov = rig.profile.vertical_fov
		rig.composition_controller.update_dynamic_fov(1.0)
		assert(is_equal_approx(rig.camera.fov, rig.profile.vertical_fov))
		assert(rig.aim_pitch == -0.6)
	rig.downward_aim_amount = 0.0
	rig.boom_compression = 1.0
	rig.composition_controller.update_dynamic_fov(1.0)
	assert(rig.camera.fov > rig.profile.vertical_fov, "close-wall lens widening remains")
	var posture := preload("res://scripts/player/operator_posture_layer.gd").new()
	assert(is_equal_approx(posture.torso_pitch_weight(&"STANDING", 0.0), 0.4))
	assert(is_equal_approx(posture.torso_pitch_weight(&"CROUCHED", 0.0), 0.4))
	assert(posture.torso_pitch_weight(&"PRONE", 0.0) == 0.0)
	assert(posture.torso_pitch_weight(&"STANDING", 1.0) == 1.0)
	var first: float = posture.advance_look_pitch(-0.7, true, 1.0 / 60)
	assert(first < 0.0 and first > -0.7)
	for frame in 90: posture.advance_look_pitch(-0.7, true, 1.0 / 60)
	assert(absf(posture.smoothed_look_pitch + 0.7) < 0.001)
	assert(posture.advance_look_pitch(0.7, false, 0.016) == 0.0, "authored actions keep pitch ownership")
	rig.free()
	print("LOOK_PITCH_PRESENTATION PASS")
	quit()
