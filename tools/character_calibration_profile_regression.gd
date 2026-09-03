extends SceneTree

const PROFILE := preload(
	"res://scripts/labs/character_calibration/character_calibration_profile.gd"
)
const PROFILE_PATH := (
	"res://config/character_retarget_profiles/military_tactical_suit_v1.json"
)

var failures: Array[String] = []


func _initialize() -> void:
	var profile := PROFILE.load_profile(PROFILE_PATH)
	_expect(not profile.is_empty(), "tactical-suit calibration profile loads")
	_expect(PROFILE.validate(profile).is_empty(), "tactical-suit calibration profile validates")
	_expect(int(profile.get("schema_version", 0)) == 1, "schema version is explicit")
	_expect(int(profile.get("version", 0)) == 1, "character calibration version is explicit")
	for side in ["left", "right"]:
		var original := PROFILE.get_forearm_twist_share(profile, side)
		_expect(is_equal_approx(original, 0.72), "%s twist share loads" % side)
		PROFILE.set_forearm_twist_share(profile, side, 0.8)
		_expect(is_equal_approx(PROFILE.get_forearm_twist_share(profile, side), 0.8), "%s twist share is adjustable" % side)
		var side_twist := (profile["twist"] as Dictionary)[side] as Dictionary
		_expect(is_equal_approx(float(side_twist["hand_share"]), 0.2), "%s hand share remains complementary" % side)
		PROFILE.set_forearm_twist_share(profile, side, original)
	var broken := profile.duplicate(true)
	(broken["anatomy"] as Dictionary).erase("right_leg")
	_expect(not PROFILE.validate(broken).is_empty(), "missing foot chain is rejected")
	if failures.is_empty():
		print("CHARACTER_CALIBRATION_PROFILE_REGRESSION PASS")
		quit(0)
		return
	print("CHARACTER_CALIBRATION_PROFILE_REGRESSION FAIL %s" % str(failures))
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("CHARACTER_CALIBRATION_PROFILE_CHECK PASS: %s" % message)
	else:
		failures.append(message)
		push_error("CHARACTER_CALIBRATION_PROFILE_CHECK FAIL: %s" % message)
