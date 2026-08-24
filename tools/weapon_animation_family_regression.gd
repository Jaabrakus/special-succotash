extends SceneTree

const WeaponRigContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const WeaponAnimationProfile := preload(
	"res://scripts/weapons/weapon_animation_profile.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	var rifle := WeaponRigContract.normalize_config({
		"weapon_id": "test_rifle",
		"display_name": "Test Assault Rifle",
		"category": "Assault Rifles",
		"handling_profile": {
			"animation_slots": {"fire_standing": "custom_rifle_fire"},
			"reload_duration_seconds": 2.25,
		},
	})
	var handling: Dictionary = rifle.get("handling_profile", {})
	_expect(
		String(handling.get("family", "")) == WeaponAnimationProfile.FAMILY_TWO_HAND_RIFLE,
		"an assault-rifle pickup selects the two-handed rifle family"
	)
	_expect(
		bool(handling.get("support_hand_required", false)),
		"the two-handed family requires the support hand"
	)
	var animation_slots: Dictionary = handling.get("animation_slots", {})
	var locomotion_slots: Dictionary = handling.get("locomotion_slots", {})
	_expect(
		_all_slots_present(animation_slots, WeaponAnimationProfile.SLOT_ORDER),
		"the family supplies every rifle idle, fire, and reload slot"
	)
	_expect(
		_all_slots_present(locomotion_slots, WeaponAnimationProfile.LOCOMOTION_SLOT_ORDER),
		"the family supplies every rifle locomotion and posture slot"
	)
	_expect(
		String(animation_slots.get("fire_standing", "")) == "custom_rifle_fire"
		and is_equal_approx(float(handling.get("reload_duration_seconds", 0.0)), 2.25),
		"weapon-specific overrides survive family completion"
	)

	for weapon_path in [
		"res://config/weapons/assaultrifle_1.json",
		"res://config/weapons/assaultrifle_2.json",
		"res://config/weapons/assaultrifle_3.json",
		"res://config/weapons/assaultrifle_4.json",
	]:
		var config := WeaponRigContract.load_config(weapon_path)
		var profile: Dictionary = config.get("handling_profile", {})
		_expect(
			String(profile.get("family", "")) == WeaponAnimationProfile.FAMILY_TWO_HAND_RIFLE
			and _all_slots_present(
				profile.get("animation_slots", {}),
				WeaponAnimationProfile.SLOT_ORDER
			)
			and _all_slots_present(
				profile.get("locomotion_slots", {}),
				WeaponAnimationProfile.LOCOMOTION_SLOT_ORDER
			),
			"%s resolves to the complete two-handed rifle animation family" % weapon_path.get_file()
		)
	_finish()


func _all_slots_present(slots: Variant, required_slots: Array[String]) -> bool:
	if not slots is Dictionary:
		return false
	for slot_name in required_slots:
		if String((slots as Dictionary).get(slot_name, "")).is_empty():
			return false
	return true


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("WEAPON_ANIMATION_FAMILY_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("WEAPON_ANIMATION_FAMILY_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("WEAPON_ANIMATION_FAMILY_REGRESSION PASS")
		quit(0)
	else:
		print("WEAPON_ANIMATION_FAMILY_REGRESSION FAIL ", failures)
		quit(1)
