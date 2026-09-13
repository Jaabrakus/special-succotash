extends SceneTree
const Envelope := preload("res://scripts/weapons/reticle_bloom_envelope.gd")
const Ballistics := preload("res://scripts/weapons/weapon_ballistics.gd")

func _initialize() -> void:
	var profile := {"base_gap_px": 10.0, "max_gap_px": 50.0, "weapon_category": "Assault Rifles"}
	for posture in [&"STANDING", &"CROUCHED", &"PRONE"]:
		assert(Envelope.gap_for(profile, 0, posture) == 10.0)
		var expected: float = {&"STANDING": 50.0, &"CROUCHED": 40.0, &"PRONE": 32.0}[posture]
		assert(is_equal_approx(Envelope.gap_for(profile, 1, posture), expected))
		var gun := Ballistics.new()
		gun.configure_bloom_envelope({"reticle": profile, "category": "Assault Rifles"})
		gun.current_posture = posture
		gun.current_movement_speed_norm = 1.0
		gun.visual_bloom_input = 1.0
		gun.bloom_gap_px = 50.0
		gun._process(1.0)
		assert(is_equal_approx(gun.bloom_gap_px, expected))
		assert(is_equal_approx(gun.get_bloom_tangent_limit(), Envelope.tangent_limit(profile, expected)))
		gun.current_is_airborne = true
		gun._process(1.0)
		assert(is_equal_approx(gun.bloom_gap_px, 50.0), "Airborne gets no crouch/prone bonus")
		gun.free()
	print("STANCE_BLOOM_CAP_PASS: shared cap, baseline preserved, airborne unchanged")
	quit()
