class_name TacticalGrenadeProfile
extends RefCounted

## One saved contract for the Grenade Lab, playable range, and server runtime.

const CONFIG_PATH := "res://config/tactical_grenade_profile.json"

const DEFAULT_PROFILE := {
	"schema_version": 1,
	"common": {
		"fuse_seconds": 3.0,
		"bounce_restitution": 0.38,
		"mass_kg": 0.40,
	},
	"throw": {
		"overhand_speed": 16.0,
		"underhand_speed": 6.4,
		"overhand_lift": 0.28,
		"underhand_lift": 0.06,
		"minimum_overhand_speed": 9.0,
		"minimum_underhand_speed": 4.2,
		"full_throw_charge_seconds": 0.78,
		"maximum_hold_seconds": 1.25,
		"full_throw_playback_speed": 1.15,
		"quick_throw_playback_speed": 2.05,
		"recovery_blend_seconds": 0.12,
	},
	"smoke": {
		"maximum_radius": 6.5,
		"sprout_seconds": 1.35,
		"dense_seconds": 15.0,
		"dissipate_seconds": 6.0,
		"particle_amount": 320,
		"particle_lifetime": 5.2,
		"emission_radius": 3.5,
		"puff_size_min": 2.4,
		"puff_size_max": 4.9,
		"visual_opacity": 0.30,
	},
	"flash": {
		"effective_radius": 18.0,
		"intensity_multiplier": 1.0,
	},
	"frag": {
		"blast_radius": 7.0,
		"maximum_damage": 120.0,
		"impulse_strength": 14.0,
		"debris_count": 12,
		"blast_effect_seconds": 1.0,
		"blast_smoke_particles": 220,
		"blast_smoke_opacity": 0.24,
	},
}


static func load_profile() -> Dictionary:
	var bundled := SocomPlaytestStateCollector.bundled_state("tactical_grenades")
	if not bundled.is_empty():
		return normalize(bundled)
	if not FileAccess.file_exists(CONFIG_PATH):
		return normalize({})
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
	return normalize(parsed as Dictionary if parsed is Dictionary else {})


static func save_profile(raw: Dictionary) -> bool:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(normalize(raw), "  ") + "\n")
	file.close()
	return true


static func normalize(raw: Dictionary) -> Dictionary:
	var profile: Dictionary = DEFAULT_PROFILE.duplicate(true)
	profile["schema_version"] = maxi(1, int(raw.get("schema_version", 1)))
	var common := _section(raw, "common")
	var throw_values := _section(raw, "throw")
	var smoke := _section(raw, "smoke")
	var flash := _section(raw, "flash")
	var frag := _section(raw, "frag")

	profile["common"] = {
		"fuse_seconds": clampf(float(common.get("fuse_seconds", 3.0)), 1.0, 8.0),
		"bounce_restitution": clampf(float(common.get("bounce_restitution", 0.38)), 0.0, 0.95),
		"mass_kg": clampf(float(common.get("mass_kg", 0.40)), 0.10, 2.0),
	}
	profile["throw"] = {
		"overhand_speed": clampf(float(throw_values.get("overhand_speed", 16.0)), 4.0, 30.0),
		"underhand_speed": clampf(float(throw_values.get("underhand_speed", 6.4)), 2.0, 16.0),
		"overhand_lift": clampf(float(throw_values.get("overhand_lift", 0.28)), 0.0, 0.80),
		"underhand_lift": clampf(float(throw_values.get("underhand_lift", 0.06)), 0.0, 0.50),
		"minimum_overhand_speed": clampf(float(throw_values.get("minimum_overhand_speed", 9.0)), 2.0, 20.0),
		"minimum_underhand_speed": clampf(float(throw_values.get("minimum_underhand_speed", 4.2)), 1.0, 12.0),
		"full_throw_charge_seconds": clampf(float(throw_values.get("full_throw_charge_seconds", 0.78)), 0.10, 2.0),
		"maximum_hold_seconds": clampf(float(throw_values.get("maximum_hold_seconds", 1.25)), 0.25, 3.0),
		"full_throw_playback_speed": clampf(float(throw_values.get("full_throw_playback_speed", 1.15)), 0.50, 2.0),
		"quick_throw_playback_speed": clampf(float(throw_values.get("quick_throw_playback_speed", 2.05)), 0.75, 3.0),
		"recovery_blend_seconds": clampf(float(throw_values.get("recovery_blend_seconds", 0.12)), 0.04, 0.30),
	}
	profile["smoke"] = {
		"maximum_radius": clampf(float(smoke.get("maximum_radius", 6.5)), 2.0, 12.0),
		"sprout_seconds": clampf(float(smoke.get("sprout_seconds", 1.35)), 0.25, 5.0),
		"dense_seconds": clampf(float(smoke.get("dense_seconds", 15.0)), 2.0, 40.0),
		"dissipate_seconds": clampf(float(smoke.get("dissipate_seconds", 6.0)), 1.0, 20.0),
		"particle_amount": clampi(int(smoke.get("particle_amount", 320)), 48, 800),
		"particle_lifetime": clampf(float(smoke.get("particle_lifetime", 5.2)), 1.0, 12.0),
		"emission_radius": clampf(float(smoke.get("emission_radius", 3.5)), 0.5, 8.0),
		"puff_size_min": clampf(float(smoke.get("puff_size_min", 2.4)), 0.4, 8.0),
		"puff_size_max": clampf(float(smoke.get("puff_size_max", 4.9)), 0.8, 12.0),
		"visual_opacity": clampf(float(smoke.get("visual_opacity", 0.30)), 0.05, 0.75),
	}
	(profile["smoke"] as Dictionary)["puff_size_max"] = maxf(
		float((profile["smoke"] as Dictionary).puff_size_min),
		float((profile["smoke"] as Dictionary).puff_size_max)
	)
	profile["flash"] = {
		"effective_radius": clampf(float(flash.get("effective_radius", 18.0)), 3.0, 35.0),
		"intensity_multiplier": clampf(float(flash.get("intensity_multiplier", 1.0)), 0.10, 2.0),
	}
	profile["frag"] = {
		"blast_radius": clampf(float(frag.get("blast_radius", 7.0)), 2.0, 15.0),
		"maximum_damage": clampf(float(frag.get("maximum_damage", 120.0)), 10.0, 300.0),
		"impulse_strength": clampf(float(frag.get("impulse_strength", 14.0)), 0.0, 40.0),
		"debris_count": clampi(int(frag.get("debris_count", 12)), 0, 40),
		"blast_effect_seconds": clampf(float(frag.get("blast_effect_seconds", 1.0)), 0.25, 1.50),
		"blast_smoke_particles": clampi(int(frag.get("blast_smoke_particles", 220)), 24, 500),
		"blast_smoke_opacity": clampf(float(frag.get("blast_smoke_opacity", 0.24)), 0.04, 0.55),
	}
	return profile


static func _section(raw: Dictionary, key: String) -> Dictionary:
	var value: Variant = raw.get(key, {})
	return value as Dictionary if value is Dictionary else {}
