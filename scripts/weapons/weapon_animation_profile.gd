class_name SocomWeaponAnimationProfile
extends RefCounted

## Weapon-specific visual animation routing. Gameplay movement, shot authority,
## and camera aim stay outside this profile so the same data is multiplayer-safe.

const FAMILY_ONE_HAND := "ONE_HAND"
const FAMILY_TWO_HAND_PISTOL := "TWO_HAND_PISTOL"
const FAMILY_TWO_HAND_RIFLE := "TWO_HAND_RIFLE"
const FAMILY_LONG_GUN := "LONG_GUN"
const FAMILY_HEAVY := "HEAVY"

const FAMILIES: Array[String] = [
	FAMILY_ONE_HAND,
	FAMILY_TWO_HAND_PISTOL,
	FAMILY_TWO_HAND_RIFLE,
	FAMILY_LONG_GUN,
	FAMILY_HEAVY,
]

const SLOT_ORDER: Array[String] = [
	"idle_standing",
	"idle_crouched",
	"idle_prone",
	"ready_standing",
	"ready_crouched",
	"fire_standing",
	"fire_crouched",
	"fire_prone",
	"reload_standing",
	"reload_crouched",
	"reload_prone",
]

const SLOT_LABELS := {
	"idle_standing": "Standing idle",
	"idle_crouched": "Crouched idle",
	"idle_prone": "Prone idle",
	"ready_standing": "Standing ready / recovery",
	"ready_crouched": "Crouched ready / recovery",
	"fire_standing": "Standing fire",
	"fire_crouched": "Crouched fire",
	"fire_prone": "Prone fire",
	"reload_standing": "Standing reload",
	"reload_crouched": "Crouched reload",
	"reload_prone": "Prone reload",
}

const LOCOMOTION_SLOT_ORDER: Array[String] = [
	"walk_forward", "walk_backward", "walk_left", "walk_right",
	"walk_forward_left", "walk_forward_right", "walk_back_left", "walk_back_right",
	"run_forward", "run_backward", "run_left", "run_right",
	"run_forward_left", "run_forward_right", "run_back_left", "run_back_right",
	"jump", "stand_to_crouch", "crouch_to_stand",
]

const RIFLE_SLOTS := {
	"idle_standing": "aim_idle",
	"idle_crouched": "idle_crouch",
	"idle_prone": "idle_prone",
	"ready_standing": "aim_idle",
	"ready_crouched": "aim_idle_crouch",
	"fire_standing": "combat_fire",
	"fire_crouched": "crouch_fire",
	"fire_prone": "prone_fire",
	"reload_standing": "reload",
	"reload_crouched": "reload",
	"reload_prone": "prone_reload",
}

const PISTOL_SLOTS := {
	"idle_standing": "pistol_idle",
	"idle_crouched": "pistol_idle_kneeling",
	"idle_prone": "idle_prone",
	"ready_standing": "pistol_idle",
	"ready_crouched": "pistol_idle_kneeling",
	"fire_standing": "pistol_fire",
	"fire_crouched": "pistol_fire",
	"fire_prone": "pistol_fire",
	"reload_standing": "pistol_reload",
	"reload_crouched": "pistol_reload",
	"reload_prone": "pistol_reload_hold_prone",
}

const RIFLE_LOCOMOTION := {
	"walk_forward": "walk_forward",
	"walk_backward": "walk_backward",
	"walk_left": "walk_left",
	"walk_right": "walk_right",
	"walk_forward_left": "walk_forward_left",
	"walk_forward_right": "walk_forward_right",
	"walk_back_left": "walk_back_left",
	"walk_back_right": "walk_back_right",
	"run_forward": "run_forward",
	"run_backward": "run_backward",
	"run_left": "run_left",
	"run_right": "run_right",
	"run_forward_left": "run_forward_left",
	"run_forward_right": "run_forward_right",
	"run_back_left": "run_back_left",
	"run_back_right": "run_back_right",
	"jump": "jump_loop",
	"stand_to_crouch": "crouch_start",
	"crouch_to_stand": "crouch_to_stand",
}

const PISTOL_LOCOMOTION := {
	"walk_forward": "pistol_walk_forward",
	"walk_backward": "pistol_walk_backward",
	"walk_left": "pistol_strafe_left",
	"walk_right": "pistol_strafe_right",
	"walk_forward_left": "pistol_walk_forward_left",
	"walk_forward_right": "pistol_walk_forward_right",
	"walk_back_left": "pistol_walk_back_left",
	"walk_back_right": "pistol_walk_back_right",
	"run_forward": "pistol_run_forward",
	"run_backward": "pistol_run_backward",
	"run_left": "pistol_strafe_left",
	"run_right": "pistol_strafe_right",
	"run_forward_left": "pistol_run_forward_left",
	"run_forward_right": "pistol_run_forward_right",
	"run_back_left": "pistol_run_back_left",
	"run_back_right": "pistol_run_back_right",
	"jump": "pistol_jump",
	"stand_to_crouch": "pistol_stand_to_kneel",
	"crouch_to_stand": "pistol_kneel_to_stand",
}


static func infer_family(weapon_name: String, category: String) -> String:
	var category_text := category.to_lower()
	var searchable := (weapon_name + " " + category).to_lower()
	# Category is authoritative when a catalog name contains an ammunition token.
	# In particular, 9mm_sub is a submachine gun, not a pistol whose name happens
	# to include 9mm.
	if "submachine" in category_text or "smg" in category_text:
		return FAMILY_TWO_HAND_RIFLE
	if "pistol" in searchable or "revolver" in searchable or "9mm" in searchable:
		return FAMILY_TWO_HAND_PISTOL
	if "sniper" in searchable or "shotgun" in searchable:
		return FAMILY_LONG_GUN
	if "heavy" in searchable or "launcher" in searchable:
		return FAMILY_HEAVY
	return FAMILY_TWO_HAND_RIFLE


static func build_default(family: String, available_clips: Dictionary = {}) -> Dictionary:
	var source: Dictionary = PISTOL_SLOTS if family in [FAMILY_ONE_HAND, FAMILY_TWO_HAND_PISTOL] else RIFLE_SLOTS
	var slots := source.duplicate(true)
	var locomotion_source: Dictionary = PISTOL_LOCOMOTION if family in [FAMILY_ONE_HAND, FAMILY_TWO_HAND_PISTOL] else RIFLE_LOCOMOTION
	var locomotion_slots := locomotion_source.duplicate(true)
	var uses_shared_fire_recovery := family in FAMILIES
	if not available_clips.is_empty():
		for slot_name in SLOT_ORDER:
			var clip_name := String(slots.get(slot_name, ""))
			if clip_name != "" and not available_clips.has(StringName(clip_name)) and not available_clips.has(clip_name):
				slots[slot_name] = ""
		for slot_name in LOCOMOTION_SLOT_ORDER:
			var clip_name := String(locomotion_slots.get(slot_name, ""))
			if clip_name != "" and not available_clips.has(StringName(clip_name)) and not available_clips.has(clip_name):
				locomotion_slots[slot_name] = ""
	return {
		"mapping_version": 1,
		"family": family,
		"support_hand_required": family != FAMILY_ONE_HAND,
		"locomotion_family": "PISTOL" if family in [FAMILY_ONE_HAND, FAMILY_TWO_HAND_PISTOL] else "RIFLE",
		# Every weapon family keeps its posture-matched ready pose selected for the
		# bounded FIRE_RECOVERY interval. Recoil, muzzle flash, and ballistics remain
		# accepted-shot effects; a separate authored fire OneShot is not selected.
		"standing_fire_uses_aim_idle": uses_shared_fire_recovery,
		"crouched_fire_uses_aim_idle": uses_shared_fire_recovery,
		"animation_slots": slots,
		"locomotion_slots": locomotion_slots,
	}


static func normalized_profile(
	family: String,
	saved_profile: Dictionary = {},
	available_clips: Dictionary = {}
) -> Dictionary:
	var safe_family := family if family in FAMILIES else FAMILY_TWO_HAND_RIFLE
	var normalized := build_default(safe_family, available_clips)
	for raw_key in saved_profile.keys():
		var key := String(raw_key)
		if key not in ["animation_slots", "locomotion_slots"]:
			normalized[key] = saved_profile[raw_key]
	for section_name in ["animation_slots", "locomotion_slots"]:
		var merged: Dictionary = (normalized[section_name] as Dictionary).duplicate(true)
		var saved_section: Variant = saved_profile.get(section_name, {})
		if saved_section is Dictionary:
			merged.merge((saved_section as Dictionary).duplicate(true), true)
		normalized[section_name] = merged
	# The standing ready slot is optional in existing saved profiles. Preserve
	# their former idle-as-ready route, including a weapon-specific idle override.
	# Crouched ready retains its established family fallback when not authored.
	var raw_saved_slots: Variant = saved_profile.get("animation_slots", {})
	var saved_slots: Dictionary = raw_saved_slots if raw_saved_slots is Dictionary else {}
	if String(saved_slots.get("ready_standing", "")).is_empty():
		var animation_slots: Dictionary = normalized["animation_slots"]
		animation_slots["ready_standing"] = animation_slots.get("idle_standing", "")
	normalized["family"] = safe_family
	normalized["support_hand_required"] = (
		bool(saved_profile.get("support_hand_required", safe_family != FAMILY_ONE_HAND))
	)
	normalized["locomotion_family"] = String(saved_profile.get(
		"locomotion_family",
		"PISTOL" if safe_family in [FAMILY_ONE_HAND, FAMILY_TWO_HAND_PISTOL] else "RIFLE"
	))
	# Stable accepted-shot recovery is a family policy, not an asset calibration.
	# Ignore legacy per-weapon false values that can restore a malformed fire take
	# after an otherwise valid model/socket profile is equipped.
	normalized["standing_fire_uses_aim_idle"] = true
	normalized["crouched_fire_uses_aim_idle"] = true
	return normalized


static func validate(profile: Dictionary, available_clips: Dictionary = {}) -> Dictionary:
	var slots: Dictionary = profile.get("animation_slots", {})
	var missing: Array[String] = []
	var mapped := 0
	for slot_name in SLOT_ORDER:
		var clip_name := String(slots.get(slot_name, ""))
		if clip_name == "" or (
			not available_clips.is_empty()
			and not available_clips.has(StringName(clip_name))
			and not available_clips.has(clip_name)
		):
			missing.append(slot_name)
		else:
			mapped += 1
	var locomotion_slots: Dictionary = profile.get("locomotion_slots", {})
	var locomotion_missing: Array[String] = []
	var locomotion_mapped := 0
	for slot_name in LOCOMOTION_SLOT_ORDER:
		var clip_name := String(locomotion_slots.get(slot_name, ""))
		if clip_name == "" or (
			not available_clips.is_empty()
			and not available_clips.has(StringName(clip_name))
			and not available_clips.has(clip_name)
		):
			locomotion_missing.append(slot_name)
		else:
			locomotion_mapped += 1
	return {
		"mapped": mapped,
		"total": SLOT_ORDER.size(),
		"missing": missing,
		"complete": missing.is_empty(),
		"locomotion_mapped": locomotion_mapped,
		"locomotion_total": LOCOMOTION_SLOT_ORDER.size(),
		"locomotion_missing": locomotion_missing,
		"locomotion_complete": locomotion_missing.is_empty(),
	}


static func clip_for(profile: Dictionary, intent: String, posture: String) -> StringName:
	var slots: Dictionary = profile.get("animation_slots", {})
	var posture_key := posture.to_lower()
	var key := "%s_%s" % [intent, posture_key]
	return StringName(slots.get(key, ""))


static func locomotion_clip_for(profile: Dictionary, gait: String, direction: String) -> StringName:
	var slots: Dictionary = profile.get("locomotion_slots", {})
	return StringName(slots.get("%s_%s" % [gait, direction], ""))
