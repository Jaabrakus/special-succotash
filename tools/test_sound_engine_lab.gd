extends SceneTree


func _init() -> void:
	var surface_profile := SurfaceAudioProfile.new()
	if not surface_profile.load_from_file():
		push_error("Surface audio profile did not load")
		quit(1)
		return
	var surface_errors := surface_profile.validate()
	if not surface_errors.is_empty():
		for error in surface_errors:
			push_error(error)
		quit(1)
		return
	if surface_profile.surface_for_name("Soft Sand Ground") != &"sand":
		push_error("Sand surface alias did not resolve")
		quit(1)
		return
	if surface_profile.event_layers(&"metal", &"grenade_impact").is_empty():
		push_error("Metal grenade impact has no audio layers")
		quit(1)
		return
	var sand_energy := float(surface_profile.physics_for(&"sand").get("energy_retention", 1.0))
	var concrete_energy := float(surface_profile.physics_for(&"concrete").get("energy_retention", 0.0))
	if sand_energy >= concrete_energy:
		push_error("Sand must retain less grenade energy than concrete")
		quit(1)
		return
	var profile := AudioAnimationEventProfile.new()
	if not profile.load_from_file():
		push_error("Audio animation profile did not load")
		quit(1)
		return
	var errors := profile.validate()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		quit(1)
		return
	print(
		"SOUND_ENGINE_PROFILE_PASS animations=%d surfaces=%d sand_energy=%.2f concrete_energy=%.2f"
		% [profile.animations.size(), surface_profile.surfaces.size(), sand_energy, concrete_energy]
	)
	quit(0)
