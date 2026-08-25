class_name SocomWeaponOwnershipContract
extends RefCounted

## One visual ownership rule shared by gameplay and Gunsmith previews.
## Gameplay remains authoritative for the reticle and shot result. This policy
## only decides whether the rendered weapon is placed by the aim solver or is
## temporarily carried by an authored action.

const READY_SOLVER := &"READY_SOLVER"
const RELOAD_RIGHT_HAND := &"RELOAD_RIGHT_HAND"
const MOBILITY_CHEST_CARRY := &"MOBILITY_CHEST_CARRY"
# Compatibility symbol for older tools. Mobility no longer lets the animated
# wrist move the rifle. The chest carry owns the weapon and both hands use IK.
const MOBILITY_RIGHT_HAND := MOBILITY_CHEST_CARRY
const GRENADE_ACTION := &"GRENADE_ACTION"
const RECOVERY_TO_READY := &"RECOVERY_TO_READY"
const RELAXED_RIFLE_LOCOMOTION := &"RELAXED_RIFLE_LOCOMOTION"
# Compatibility name retained for older callers. The rifle is visible and
# attached to the right hand; it is not actually holstered in this state.
const HOLSTERED_ANIMATION := RELAXED_RIFLE_LOCOMOTION

const ARMS_WEAPON_SOCKETS := &"WEAPON_SOCKETS"
const ARMS_ACTION_CLIP := &"ACTION_CLIP"
const ARMS_BASE_ANIMATION := &"BASE_ANIMATION"

# Compatibility names used by the existing Gunsmith UI.
const OWNER_WEAPON_MASTER: StringName = READY_SOLVER
const OWNER_ANIMATED_RIGHT_HAND: StringName = RELOAD_RIGHT_HAND

const SUPPORT_IK_TO_WEAPON: StringName = &"IK_TO_WEAPON"
const SUPPORT_ANIMATION_FREE: StringName = &"ANIMATION_FREE"
const SUPPORT_ANIMATION: StringName = SUPPORT_ANIMATION_FREE
const SUPPORT_FREE: StringName = SUPPORT_ANIMATION_FREE

const BODY_CHARACTER := &"CHARACTER_BODY"
const AIM_CAMERA_RETICLE := &"CAMERA_RETICLE"
const SHOT_SERVER_WEAPON := &"SERVER_WEAPON"
const TORSO_POSTURE_AIM := &"POSTURE_AIM"
const LEGS_LOCOMOTION := &"LOCOMOTION"

const FIRE_ACCEPTED := &"FIRE_ACCEPTED"
const ENTER_READY_AIM := "ENTER_READY_AIM"
const RAIL_TO_BLUE_LINE := "RAIL_TO_BLUE_LINE"
const STABLE_CHEST := &"STABLE_CHEST"
const MAX_READY_WEIGHT_STEP := 0.35


static func sanitize_presentation_plan(raw_plan: Dictionary) -> Dictionary:
	var plan := raw_plan.duplicate(true)
	var effects: Array = (plan.get("effects", []) as Array).duplicate()
	var blocked_effects: Array[String] = []
	if StringName(plan.get("event", &"")) == FIRE_ACCEPTED:
		while RAIL_TO_BLUE_LINE in effects:
			effects.erase(RAIL_TO_BLUE_LINE)
			blocked_effects.append(RAIL_TO_BLUE_LINE)
		if ENTER_READY_AIM not in effects:
			effects.append(ENTER_READY_AIM)
	plan["effects"] = effects
	plan["blocked_effects"] = blocked_effects
	plan["ownership_contract"] = "ONE_OWNER_PER_REGION"
	return plan


static func bounded_ready_weight(
	current: float,
	target: float,
	response: float,
	delta: float
) -> float:
	var safe_current := clampf(current, 0.0, 1.0)
	var safe_target := clampf(target, 0.0, 1.0)
	var blended := lerpf(
		safe_current,
		safe_target,
		1.0 - exp(-maxf(response, 0.0) * maxf(delta, 0.0))
	)
	return safe_current + clampf(
		blended - safe_current,
		-MAX_READY_WEIGHT_STEP,
		MAX_READY_WEIGHT_STEP
	)


static func presentation_conflicts(plan: Dictionary, weapon_pose: Dictionary) -> Array[String]:
	var conflicts: Array[String] = []
	var event_name := StringName(plan.get("event", &""))
	var effects: Array = plan.get("effects", [])
	if event_name == FIRE_ACCEPTED:
		if RAIL_TO_BLUE_LINE in effects:
			conflicts.append("fire requested event-owned blue-line placement")
		if bool(weapon_pose.get("rail_to_blue_line_event_active", false)):
			conflicts.append("fire activated event-owned blue-line placement")
		if StringName(weapon_pose.get("gun_placement_anchor_space", STABLE_CHEST)) != STABLE_CHEST:
			conflicts.append("fire weapon anchor left the stable chest frame")
	var pose_owners: Dictionary = weapon_pose.get("pose_owners", {})
	if (
		StringName(pose_owners.get("right_arm", &"")) == ARMS_ACTION_CLIP
		and bool(weapon_pose.get("weapon_solver_owned", false))
	):
		conflicts.append("action clip and weapon solver both own the right arm")
	return conflicts


static func resolve(
	movement_state: StringName,
	requested_action: StringName,
	ready_weight: float,
	action_follow_active: bool
) -> StringName:
	var action_text := String(requested_action).to_lower()
	if "reload" in action_text:
		return RELOAD_RIGHT_HAND
	if "grenade" in action_text:
		return GRENADE_ACTION
	# Dive and roll keep the authored full-body action, but the stable chest carry
	# owns the rifle. Both palms follow its sockets after the animation sample.
	# A normal jump keeps the reticle/Gunsmith solver active.
	if movement_state in [&"DIVING", &"ROLLING"]:
		return MOBILITY_CHEST_CARRY
	if action_follow_active:
		return RECOVERY_TO_READY
	# Jump clips own only the lower body. Preserve the rifle state that entered
	# the jump instead of automatically raising a relaxed gun into Aim Idle.
	if movement_state in [&"AIRBORNE", &"LANDING"]:
		return READY_SOLVER if ready_weight > 0.001 else RELAXED_RIFLE_LOCOMOTION
	if ready_weight > 0.001:
		return READY_SOLVER
	return HOLSTERED_ANIMATION


static func runtime_policy(
	movement_state: StringName,
	requested_action: StringName,
	requested_action_may_own_weapon: bool
) -> Dictionary:
	var action := requested_action if requested_action_may_own_weapon else &""
	var owner := resolve(movement_state, action, 1.0, false)
	return _policy_for_owner(owner, false, &"")


static func preview_policy(slot_name: String, clip_name: StringName = &"") -> Dictionary:
	var semantic_name := slot_name.to_lower()
	var posture := _posture_from_slot(semantic_name)
	var action_name := String(clip_name).to_lower()
	# Clip semantics win for full-body mobility. This prevents a clip named, for
	# example, "jump shooting" from being mistaken for a normal fire overlay
	# just because the browser inferred a fire slot from one word.
	if _contains_any(action_name, ["jump", "dive", "roll", "fall", "land"]):
		return _policy_for_owner(MOBILITY_CHEST_CARRY, false, posture)
	if semantic_name.begins_with("reload_"):
		return _policy_for_owner(RELOAD_RIGHT_HAND, false, posture)
	if semantic_name.begins_with("fire_"):
		return _policy_for_owner(READY_SOLVER, false, posture)
	if semantic_name.begins_with("idle_"):
		if action_name.is_empty() or _contains_any(action_name, ["aim", "ready"]):
			return _policy_for_owner(READY_SOLVER, false, posture)
		return _policy_for_name(action_name, posture)
	if "grenade" in action_name:
		return _policy_for_owner(GRENADE_ACTION, false, posture)
	if _contains_any(action_name, ["dive", "roll"]):
		return _policy_for_owner(MOBILITY_CHEST_CARRY, false, posture)
	return _policy_for_name(action_name, posture)


static func _policy_for_name(raw_name: String, posture: StringName = &"") -> Dictionary:
	var action_name := raw_name.to_lower()
	# Full-body mobility keeps the authored right-hand carry even when a clip
	# name also contains words such as "rifle" or "shooting".  Preview Fire may
	# show its reticle feedback, but it must not move the airborne weapon.
	if _contains_any(action_name, ["jump", "dive", "roll", "fall", "land"]):
		return _policy_for_owner(MOBILITY_CHEST_CARRY, false, posture)
	# Ordinary firing is a recoil/pose layer. The reticle-driven weapon remains
	# authoritative and both hands are re-solved after the animation sample.
	if _contains_any(action_name, ["aim", "ready", "fire", "shoot", "recoil"]):
		return _policy_for_owner(READY_SOLVER, false, posture)
	# Relaxed rifle locomotion is a full authored pose. The animation owns its
	# torso and both arms while the visible weapon remains on the canonical
	# right-hand attachment. Ready Aim is a separate state selected above.
	if _contains_any(action_name, [
		"idle", "walk", "run", "sprint", "strafe", "shuffle", "start", "stop", "turn",
		"prone", "crawl", "crouch", "kneel"
	]):
		return _policy_for_owner(RELAXED_RIFLE_LOCOMOTION, false, posture)
	return _policy_for_owner(MOBILITY_CHEST_CARRY, false, posture)


static func action_owns_arms(owner: StringName) -> bool:
	return owner in [RELOAD_RIGHT_HAND, MOBILITY_CHEST_CARRY, GRENADE_ACTION]


static func weapon_follows_right_hand(owner: StringName) -> bool:
	return owner == RELOAD_RIGHT_HAND


static func weapon_uses_action_follow(owner: StringName) -> bool:
	# Reload is authored around the canonical right-palm attachment. Keeping the
	# rifle under BoneAttachment3D lets the clip rotate and translate the hand
	# without a second world-space transform owner chasing it a frame later.
	return owner == MOBILITY_CHEST_CARRY


static func ready_solver_owns_weapon(owner: StringName) -> bool:
	return owner in [READY_SOLVER, RECOVERY_TO_READY]


static func uses_stable_chest_translation(owner: StringName) -> bool:
	return owner == MOBILITY_CHEST_CARRY


static func arm_owner(owner: StringName) -> StringName:
	if owner == MOBILITY_CHEST_CARRY:
		return ARMS_WEAPON_SOCKETS
	if action_owns_arms(owner):
		return ARMS_ACTION_CLIP
	if ready_solver_owns_weapon(owner):
		return ARMS_WEAPON_SOCKETS
	return ARMS_BASE_ANIMATION


static func support_hand_owner(owner: StringName, reload_support_regrip: bool) -> StringName:
	if owner == RELOAD_RIGHT_HAND and reload_support_regrip:
		return SUPPORT_IK_TO_WEAPON
	if owner == MOBILITY_CHEST_CARRY:
		return SUPPORT_IK_TO_WEAPON
	if action_owns_arms(owner):
		return SUPPORT_ANIMATION_FREE
	# A two-hand rifle locomotion clip supplies the natural shoulder, trigger
	# arm, and carry motion. The rifle remains on the animated right hand, then
	# the final support-hand pass restores the left palm to the saved foregrip.
	# Releasing this hand for ordinary idle/walk/run clips made valid retargets
	# look broken whenever source and operator arm proportions differed.
	if ready_solver_owns_weapon(owner) or owner == RELAXED_RIFLE_LOCOMOTION:
		return SUPPORT_IK_TO_WEAPON
	return SUPPORT_ANIMATION_FREE


static func resolve_pose_owners(
	movement_state: StringName,
	requested_action: StringName,
	ready_weight: float,
	action_follow_active: bool,
	reload_support_regrip: bool = false,
	posture: StringName = &""
) -> Dictionary:
	var owner := resolve(
		movement_state,
		requested_action,
		ready_weight,
		action_follow_active
	)
	var action_text := String(requested_action).to_lower()
	var action_torso := owner in [RELOAD_RIGHT_HAND, MOBILITY_CHEST_CARRY, GRENADE_ACTION]
	var action_legs := owner == MOBILITY_CHEST_CARRY or (
		owner == GRENADE_ACTION and posture != &"CROUCHED"
	)
	return {
		"authoritative_body": BODY_CHARACTER,
		"aim": AIM_CAMERA_RETICLE,
		"shot": SHOT_SERVER_WEAPON,
		"weapon": owner,
		"right_arm": arm_owner(owner),
		"left_arm": support_hand_owner(owner, reload_support_regrip),
		"torso": ARMS_ACTION_CLIP if action_torso else TORSO_POSTURE_AIM,
		"legs": ARMS_ACTION_CLIP if action_legs else LEGS_LOCOMOTION,
		"action": StringName(action_text),
	}


static func ownership_conflicts(
	owners: Dictionary,
	observed_weapon_owner: StringName = &"",
	observed_support_hand_owner: StringName = &""
) -> Array[String]:
	var conflicts: Array[String] = []
	for region in [
		"authoritative_body", "aim", "shot", "weapon",
		"right_arm", "left_arm", "torso", "legs",
	]:
		if StringName(owners.get(region, &"")) == &"":
			conflicts.append("%s has no owner" % region)
	if StringName(owners.get("authoritative_body", &"")) != BODY_CHARACTER:
		conflicts.append("animation attempted to own the authoritative body")
	if StringName(owners.get("aim", &"")) != AIM_CAMERA_RETICLE:
		conflicts.append("animation attempted to own aim")
	if StringName(owners.get("shot", &"")) != SHOT_SERVER_WEAPON:
		conflicts.append("animation attempted to own shot authority")
	if (
		observed_weapon_owner != &""
		and StringName(owners.get("weapon", &"")) != observed_weapon_owner
	):
		conflicts.append("declared weapon owner does not match the active solver")
	if (
		observed_support_hand_owner != &""
		and StringName(owners.get("left_arm", &"")) != observed_support_hand_owner
	):
		conflicts.append("declared left-arm owner does not match support-hand IK")
	return conflicts


static func _policy_for_owner(
	owner: StringName,
	reload_support_regrip: bool,
	posture: StringName
) -> Dictionary:
	var owners := resolve_pose_owners(
		&"DIVING" if owner == MOBILITY_CHEST_CARRY else &"STANDING",
		_reload_action_for_owner(owner),
		1.0 if owner in [READY_SOLVER, RECOVERY_TO_READY] else 0.0,
		owner == RECOVERY_TO_READY,
		reload_support_regrip,
		posture
	)
	# resolve_pose_owners cannot infer a grenade from a generic owner without an
	# action name. Preserve the already-resolved canonical owner explicitly.
	owners["weapon"] = owner
	owners["right_arm"] = arm_owner(owner)
	owners["left_arm"] = support_hand_owner(owner, reload_support_regrip)
	if owner == GRENADE_ACTION:
		owners["torso"] = ARMS_ACTION_CLIP
		owners["legs"] = ARMS_BASE_ANIMATION if posture == &"CROUCHED" else ARMS_ACTION_CLIP
	return {
		"weapon_owner": owner,
		"resolved_owner": owner,
		"support_hand": support_hand_owner(owner, reload_support_regrip),
		"pose_owners": owners,
		"ownership_conflicts": ownership_conflicts(owners),
	}


static func _reload_action_for_owner(owner: StringName) -> StringName:
	if owner == RELOAD_RIGHT_HAND:
		return &"reload"
	if owner == GRENADE_ACTION:
		return &"grenade"
	return &""


static func _posture_from_slot(slot_name: String) -> StringName:
	if "crouch" in slot_name:
		return &"CROUCHED"
	if "prone" in slot_name:
		return &"PRONE"
	return &"STANDING"


static func _contains_any(value: String, needles: Array[String]) -> bool:
	for needle in needles:
		if needle in value:
			return true
	return false
