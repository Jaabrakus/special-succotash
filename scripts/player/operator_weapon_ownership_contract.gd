class_name SocomOperatorWeaponOwnershipContract
extends RefCounted

## Compatibility shim. New gameplay and tool code use the shared contract.
const Shared := preload("res://scripts/player/weapon_ownership_contract.gd")

const READY_SOLVER := Shared.READY_SOLVER
const RELOAD_RIGHT_HAND := Shared.RELOAD_RIGHT_HAND
const MOBILITY_CHEST_CARRY := Shared.MOBILITY_CHEST_CARRY
const MOBILITY_RIGHT_HAND := Shared.MOBILITY_RIGHT_HAND
const GRENADE_ACTION := Shared.GRENADE_ACTION
const RECOVERY_TO_READY := Shared.RECOVERY_TO_READY
const HOLSTERED_ANIMATION := Shared.HOLSTERED_ANIMATION
const RELAXED_RIFLE_LOCOMOTION := Shared.RELAXED_RIFLE_LOCOMOTION
const ARMS_WEAPON_SOCKETS := Shared.ARMS_WEAPON_SOCKETS
const ARMS_ACTION_CLIP := Shared.ARMS_ACTION_CLIP
const ARMS_BASE_ANIMATION := Shared.ARMS_BASE_ANIMATION
const SUPPORT_IK_TO_WEAPON := Shared.SUPPORT_IK_TO_WEAPON
const SUPPORT_ANIMATION_FREE := Shared.SUPPORT_ANIMATION_FREE


static func resolve(
	movement_state: StringName,
	requested_action: StringName,
	ready_weight: float,
	action_follow_active: bool
) -> StringName:
	return Shared.resolve(movement_state, requested_action, ready_weight, action_follow_active)


static func action_owns_arms(owner: StringName) -> bool:
	return Shared.action_owns_arms(owner)


static func weapon_follows_right_hand(owner: StringName) -> bool:
	return Shared.weapon_follows_right_hand(owner)


static func weapon_uses_action_follow(owner: StringName) -> bool:
	return Shared.weapon_uses_action_follow(owner)


static func uses_stable_chest_translation(owner: StringName) -> bool:
	return Shared.uses_stable_chest_translation(owner)


static func arm_owner(owner: StringName) -> StringName:
	return Shared.arm_owner(owner)


static func support_hand_owner(owner: StringName, reload_support_regrip: bool) -> StringName:
	return Shared.support_hand_owner(owner, reload_support_regrip)
