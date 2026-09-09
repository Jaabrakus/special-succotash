extends SceneTree

const MAP := "res://config/animation_presets/seal_gameplay_candidate.json"
const FIRING := "res://assets/animations/seal_firing_reference/"
const COMPOSER := preload("res://tools/extend_seal_locomotion_candidate.gd")

func _initialize() -> void:
	extend_candidate()
	quit()

static func extend_candidate() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIRING + "manifest.json"))
	assert(not map.locomotion.get("source_firing_locomotion", false), "Firing routes already installed")
	for name: String in manifest.entries:
		var entry: Dictionary = manifest.entries[name]
		map.clips[name] = entry.get("composed_path", entry.path)
	# Source table names these fast lateral strafes, not fp_90-degree runs.
	# Partial pistol arms retain their samples over the corresponding rifle legs.
	for side: String in ["l", "r"]:
		var rifle_name := "seal_" + side + "strafe_fast"
		var pistol_name := "seal_p_" + side + "strafe_fast"
		for name: String in [rifle_name, pistol_name]:
			var path := FIRING + name + "_locomotion.tres"
			assert(not FileAccess.file_exists(path), "Preserve existing firing asset: " + path)
			var source := load("res://assets/animations/seal_reference/" + name + ".tres") as Animation
			var base := load("res://assets/animations/seal_reference/" + rifle_name + ".tres") as Animation
			var clip := COMPOSER.compose(source, base) if name == pistol_name else source.duplicate(true) as Animation
			assert(ResourceSaver.save(clip, path) == OK)
			map.clips[name] = path
	for family: String in ["TWO_HAND_RIFLE", "TWO_HAND_PISTOL"]:
		var pistol := family == "TWO_HAND_PISTOL"
		var prefix := "seal_pfp_" if pistol else "seal_fp_"
		var slots: Dictionary = map.family_animation_slots.get(family, {})
		for pair in [["standing", "stand"], ["crouched", "crouch"], ["prone", "prone"]]:
			slots["ready_" + pair[0]] = prefix + pair[1]
			slots["ready_" + pair[0] + "_moving"] = prefix + pair[1]
		for gait: String in ["walk", "run", "crouch"]:
			var source_gait := "crouchwalk" if gait == "crouch" else gait
			slots["locomotion_ready/" + gait + "_forward"] = prefix + source_gait
			slots["locomotion_ready/" + gait + "_backward"] = prefix + source_gait + "_bw"
			for side: String in ["left", "right"]:
				var name := ""
				if gait == "crouch":
					name = ("pistol_" if pistol else "") + "crouch_" + side
				elif gait == "walk":
					name = ("pistol_strafe_" if pistol else "walk_") + side
				else:
					name = ("seal_p_" if pistol else "seal_") + side.left(1) + "strafe_fast"
				slots["locomotion_ready/" + gait + "_" + side] = name
		map.family_animation_slots[family] = slots
	map.locomotion.source_firing_locomotion = true
	map.locomotion.source_upright_weapon = true
	var file := FileAccess.open(MAP, FileAccess.WRITE)
	file.store_string(JSON.stringify(map, "\t") + "\n")
	file.close()
	print("SEAL_FIRING_ROUTES PASS imported=", manifest.entries.size(), " main_map_unchanged=true")
