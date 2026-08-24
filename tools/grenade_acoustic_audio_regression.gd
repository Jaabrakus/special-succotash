extends SceneTree

const RuntimeAudio := preload("res://scripts/audio/lab_leak_audio_engine.gd")
const Profile := preload("res://scripts/audio/acoustic_propagation_profile.gd")


func _init() -> void:
	var failures: Array[String] = []
	var frag_layers := RuntimeAudio.grenade_explosion_layers(&"frag")
	var flash_layers := RuntimeAudio.grenade_explosion_layers(&"flash")
	if frag_layers.size() != 2:
		failures.append("frag detonation must have a close core and distant tail")
	if flash_layers.size() != 1:
		failures.append("flashbang detonation must have its dedicated source")
	for layer: Dictionary in frag_layers + flash_layers:
		var stream := layer.get("stream") as AudioStream
		if stream == null or stream.get_length() < 0.5:
			failures.append("grenade detonation contains a missing or truncated stream")
	var profile := Profile.new()
	if not profile.load_from_file():
		failures.append("acoustic propagation profile did not load")
	else:
		var explosion_policy := profile.policy_for(&"explosion")
		if int(explosion_policy.get("priority", 0)) < 90:
			failures.append("explosions are not protected by the high-priority voice budget")
		if float(explosion_policy.get("max_distance_m", 0.0)) < 250.0:
			failures.append("explosion propagation range is below the tactical-map budget")
		if int(explosion_policy.get("max_portal_hops", 0)) < 4:
			failures.append("explosions cannot travel through enough map portals")
	var runtime_source := _read("res://scripts/audio/lab_leak_audio_engine.gd")
	var frag_source := _read("res://scripts/tactical/frag_grenade.gd")
	var flash_source := _read("res://scripts/tactical/flashbang_grenade.gd")
	var lab_source := _read("res://scripts/labs/sound_engine_lab.gd")
	if '"play_layered_event"' not in runtime_source or '&"explosion"' not in runtime_source:
		failures.append("grenade layers bypass shared acoustic propagation")
	if "play_grenade_detonation" not in frag_source:
		failures.append("frag detonation does not request its blast audio")
	if "play_grenade_detonation" not in flash_source:
		failures.append("flashbang detonation does not request its blast audio")
	if "Frag Detonation" not in lab_source or "Flashbang Detonation" not in lab_source:
		failures.append("Sound Lab does not expose both grenade previews")
	if failures.is_empty():
		print(
			"GRENADE_ACOUSTIC_AUDIO_PASS frag_layers=%d flash_layers=%d range=%.0fm portals=%d"
			% [
				frag_layers.size(),
				flash_layers.size(),
				float(profile.policy_for(&"explosion").get("max_distance_m", 0.0)),
				int(profile.policy_for(&"explosion").get("max_portal_hops", 0)),
			]
		)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""
