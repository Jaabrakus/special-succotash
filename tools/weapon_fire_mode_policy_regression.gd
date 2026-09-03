extends SceneTree

const FireModePolicy := preload("res://scripts/weapons/weapon_fire_mode_policy.gd")


func _initialize() -> void:
	print("--- Running Weapon Fire Mode Policy Regression ---")
	_test_completed_burst_requires_release()
	_test_press_during_burst_does_not_queue_another_burst()
	_test_cancelling_a_burst_clears_its_rearm_latch()
	print("WEAPON_FIRE_MODE_POLICY_REGRESSION PASS")
	quit(0)


func _test_completed_burst_requires_release() -> void:
	var policy := FireModePolicy.new()
	policy.configure(["burst"], "burst", 3)
	for round_index in 3:
		assert(
			policy.should_attempt_shot(round_index == 0, true, 30 - round_index),
			"Burst must continue through round %d" % (round_index + 1)
		)
		policy.notify_shot_result({"fired": true})
	assert(not policy.has_pending_burst(), "Completed burst must have no remaining rounds")
	assert(
		not policy.should_attempt_shot(true, true, 27),
		"A press while the completed burst is still held must not start another burst"
	)
	assert(
		not policy.should_attempt_shot(false, false, 27),
		"Release should only re-arm the trigger; it must not fire"
	)
	assert(
		policy.should_attempt_shot(true, true, 27),
		"A fresh press after release must begin the next burst"
	)
	print("✓ Completed bursts require release before re-arm")


func _test_press_during_burst_does_not_queue_another_burst() -> void:
	var policy := FireModePolicy.new()
	policy.configure(["burst"], "burst", 3)
	assert(policy.should_attempt_shot(true, true, 30), "First burst round did not start")
	policy.notify_shot_result({"fired": true})
	assert(
		policy.should_attempt_shot(true, true, 29),
		"An extra press during the burst may only advance its current second round"
	)
	policy.notify_shot_result({"fired": true})
	assert(policy.should_attempt_shot(false, true, 28), "Third round did not continue")
	policy.notify_shot_result({"fired": true})
	assert(
		not policy.should_attempt_shot(false, true, 27),
		"Extra presses during a burst must not queue a fourth shot or a new burst"
	)
	print("✓ Mid-burst presses cannot queue another burst")


func _test_cancelling_a_burst_clears_its_rearm_latch() -> void:
	var policy := FireModePolicy.new()
	policy.configure(["burst"], "burst", 2)
	assert(policy.should_attempt_shot(true, true, 30), "Burst did not begin")
	policy.notify_shot_result({"fired": true})
	policy.cancel_pending_burst()
	assert(not policy.has_pending_burst(), "Cancelled burst must not remain pending")
	assert(
		policy.should_attempt_shot(true, true, 29),
		"Reload or weapon-state cancellation must not leave the trigger permanently blocked"
	)
	print("✓ Cancellation clears burst re-arm state")
