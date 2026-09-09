class_name SocomOperatorAnimationLibraryCache
extends RefCounted

## Shares the immutable, processed animation library across operators and loads
## a fingerprinted packaged cache on cold startup. Asset retargeting remains in
## the asset runtime; cache lifetime and persistence live here.

# Schema 2 invalidates libraries that cached AGLS pistol actions after the old
# Mixamo-only retarget removed every Unreal-named track.
const CACHE_SCHEMA := 6
const TARGET_RIG_PATH := "res://assets/characters/ps1_dual_source_rig/ps1_dual_source_rig.scn"
const PACKAGED_PATH := "res://assets/animations/cache/operator_animation_library.res"
const USER_PATH := "user://operator_animation_library.res"

static var shared_libraries: Dictionary = {}
static var shared_sources: Dictionary = {}


func adopt(profile, animation_player: AnimationPlayer) -> Dictionary:
	# A packaged-cache build must process the canonical source map and reach
	# store(). Adopting an existing user cache here makes the command succeed
	# without ever publishing the requested res:// artifact.
	if OS.get_cmdline_user_args().has("--build-animation-cache"):
		return {}
	var fingerprint := fingerprint_for(profile)
	var library: AnimationLibrary = shared_libraries.get(fingerprint)
	if library == null:
		for cache_path in [USER_PATH, PACKAGED_PATH]:
			if not ResourceLoader.exists(cache_path):
				continue
			var candidate := load(cache_path) as AnimationLibrary
			if (
				candidate != null
				and String(candidate.get_meta("socom_fingerprint", "")) == fingerprint
			):
				library = candidate
				break
	if library == null:
		return {}
	var available: Dictionary = {}
	for clip_name: StringName in library.get_animation_list():
		available[clip_name] = true
	var raw_sources: Variant = shared_sources.get(
		fingerprint,
		library.get_meta("socom_source_animation_names", {})
	)
	var sources := (
		(raw_sources as Dictionary).duplicate(true)
		if raw_sources is Dictionary
		else {}
	)
	shared_libraries[fingerprint] = library
	shared_sources[fingerprint] = sources.duplicate(true)
	animation_player.add_animation_library("", library)
	return {
		"fingerprint": fingerprint,
		"library": library,
		"available_clips": available,
		"source_animation_names": sources,
	}


func store(profile, library: AnimationLibrary, sources: Dictionary) -> void:
	var fingerprint := fingerprint_for(profile)
	library.set_meta("socom_fingerprint", fingerprint)
	library.set_meta("socom_source_animation_names", sources.duplicate(true))
	shared_libraries[fingerprint] = library
	shared_sources[fingerprint] = sources.duplicate(true)
	var building_packaged := OS.get_cmdline_user_args().has("--build-animation-cache")
	var save_path := PACKAGED_PATH if building_packaged else USER_PATH
	# The editor keeps the process-level cache alive between operator spawns.
	# Exported builds persist caches generated from user-authored animation maps.
	if (
		save_path == USER_PATH
		and (OS.has_feature("editor") or DisplayServer.get_name() == "headless")
	):
		return
	var save_error := ResourceSaver.save(library, save_path)
	if save_error != OK:
		push_warning("Could not save operator animation cache: %s" % error_string(save_error))
	elif building_packaged:
		print("OPERATOR_ANIMATION_CACHE_BUILD fingerprint=%s animations=%d path=%s" % [
			fingerprint,
			library.get_animation_list().size(),
			save_path,
		])


func fingerprint_for(profile) -> String:
	var entries: Array[String] = ["schema:%d" % CACHE_SCHEMA]
	entries.append("target_rig:" + FileAccess.get_sha256(TARGET_RIG_PATH))
	entries.append("source_jump:" + JSON.stringify(profile.source_jump))
	entries.append("gait_alignment:%s:%s" % [profile.locomotion.get("grounded_gait_alignment", false), profile.locomotion.get("gait_support_height_m", 0.05)])
	# StringName ordering depends on the process' interning order. Canonicalize to
	# ordinary strings before sorting so launcher, main.tscn, and regression
	# processes produce the same fingerprint for identical animation data.
	var clip_names: Array[String] = []
	for raw_clip_name in profile.clip_paths.keys():
		clip_names.append(String(raw_clip_name))
	clip_names.sort()
	for clip_name_text in clip_names:
		var clip_name := StringName(clip_name_text)
		entries.append("%s=%s:%s:%.4f" % [
			clip_name_text,
			String(profile.clip_paths[clip_name]),
			str(profile.is_looping(clip_name)),
			profile.pose_yaw_offset_degrees(clip_name),
		])
	for property_name in ["mirrored_clips", "leg_mirrored_clips", "clip_aliases"]:
		var routes: Dictionary = profile.get(property_name) as Dictionary
		var routes_by_name: Dictionary = {}
		for raw_route_name in routes.keys():
			routes_by_name[String(raw_route_name)] = routes[raw_route_name]
		var route_names: Array = routes_by_name.keys()
		route_names.sort()
		for route_name in route_names:
			entries.append("%s:%s=%s" % [
				property_name,
				String(route_name),
				String(routes_by_name[route_name]),
			])
	return "|".join(entries).sha256_text()
