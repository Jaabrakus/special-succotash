extends SceneTree

const RuntimeAudio := preload("res://scripts/audio/lab_leak_audio_engine.gd")


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
	var gameplay_shot := RuntimeAudio.gunshot_stream(false)
	if gameplay_shot == null or gameplay_shot.mix_rate != 44100:
		push_error("Gameplay does not use the approved 44.1 kHz Sound Lab rifle shot")
		quit(1)
		return
	var shot_duration := float(gameplay_shot.data.size()) / 2.0 / float(gameplay_shot.mix_rate)
	if absf(shot_duration - 0.42) > 0.01:
		push_error("Gameplay rifle shot does not match the approved Sound Lab duration")
		quit(1)
		return
	var frag_layers := RuntimeAudio.grenade_explosion_layers(&"frag")
	var flash_layers := RuntimeAudio.grenade_explosion_layers(&"flash")
	if frag_layers.size() != 2 or flash_layers.size() != 1:
		push_error("Licensed grenade detonation layers did not load")
		quit(1)
		return
	var body_layers := RuntimeAudio.body_impact_layers(false)
	var body_thump := body_layers[0].get("stream") as AudioStream
	if body_thump == null or body_thump.get_length() < 0.19:
		push_error("Body impact is missing its compact low-frequency pressure pulse")
		quit(1)
		return
	print(
		"SOUND_ENGINE_PROFILE_PASS animations=%d surfaces=%d sand_energy=%.2f concrete_energy=%.2f rifle_shot=%.2fs@%dHz grenade_layers=%d/%d body_thump=%.2fs"
		% [profile.animations.size(), surface_profile.surfaces.size(), sand_energy, concrete_energy, shot_duration, gameplay_shot.mix_rate, frag_layers.size(), flash_layers.size(), body_thump.get_length()]
	)
	quit(0)
