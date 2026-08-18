extends RefCounted

## One visual ownership rule shared by gameplay and Gunsmith previews.
## Gameplay remains authoritative for the reticle and shot result. This policy
## only decides whether the rendered weapon is placed by the aim solver or is
## temporarily carried by an authored right-hand animation.

# Preserve the existing public/debug state name used by the camera workbench
# and regression recordings. Conceptually this is the weapon/reticle master.
const OWNER_WEAPON_MASTER: StringName = &"AIM_MASTER"
const OWNER_ANIMATED_RIGHT_HAND: StringName = &"ANIMATED_RIGHT_HAND"

const SUPPORT_IK_TO_WEAPON: StringName = &"IK_TO_WEAPON"
const SUPPORT_ANIMATION: StringName = &"ANIMATION"
const SUPPORT_FREE: StringName = &"FREE"


static func runtime_policy(
	movement_state: StringName,
	requested_action: StringName,
	requested_action_may_own_weapon: bool
) -> Dictionary:
	if movement_state in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]:
		return _animated_policy(requested_action)
	if requested_action == &"" or not requested_action_may_own_weapon:
		return _weapon_master_policy()
	return _policy_for_name(String(requested_action))


static func preview_policy(slot_name: String, clip_name: StringName = &"") -> Dictionary:
	var semantic_name := slot_name.to_lower()
	if semantic_name.begins_with("reload_"):
		return _animated_policy(StringName(semantic_name))
	if semantic_name.begins_with("idle_") or semantic_name.begins_with("fire_"):
		return _weapon_master_policy()
	return _policy_for_name(String(clip_name))


static func _policy_for_name(raw_name: String) -> Dictionary:
	var action_name := raw_name.to_lower()
	# Ordinary firing is a recoil/pose layer. The reticle-driven weapon remains
	# authoritative and both hands are re-solved after the animation sample.
	if _contains_any(action_name, ["idle", "fire", "shoot", "recoil"]):
		return _weapon_master_policy()
	# These are lower-body or locomotion sources. Their authored arm tracks are
	# intentionally replaced by the post-animation weapon/hand solve.
	if _contains_any(action_name, [
		"walk", "run", "strafe", "shuffle", "start", "stop", "turn"
	]):
		return _weapon_master_policy()
	return _animated_policy(StringName(action_name))


static func _animated_policy(action_name: StringName) -> Dictionary:
	var lowered := String(action_name).to_lower()
	return {
		"weapon_owner": OWNER_ANIMATED_RIGHT_HAND,
		"support_hand": SUPPORT_FREE if "reload" in lowered else SUPPORT_ANIMATION,
	}


static func _weapon_master_policy() -> Dictionary:
	return {
		"weapon_owner": OWNER_WEAPON_MASTER,
		"support_hand": SUPPORT_IK_TO_WEAPON,
	}


static func _contains_any(value: String, needles: Array[String]) -> bool:
	for needle in needles:
		if needle in value:
			return true
	return false
