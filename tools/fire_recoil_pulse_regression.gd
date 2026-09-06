extends SceneTree

const Pulse := preload("res://scripts/player/operator_fire_recoil_pulse.gd")

func _initialize() -> void:
	var pulse := Pulse.new()
	assert(is_zero_approx(pulse.weight()))
	pulse.trigger()
	pulse.advance(pulse.attack)
	assert(is_equal_approx(pulse.weight(), 1.0))
	assert(pulse.offset(&"PRONE") < pulse.offset(&"STANDING"))
	pulse.advance(0.04)
	var previous := pulse.weight()
	pulse.trigger()
	assert(is_equal_approx(previous, pulse.weight()))
	for frame in range(300):
		if frame % 4 == 0:
			pulse.trigger()
		pulse.advance(1.0 / 60.0)
		assert(pulse.weight() >= 0.0 and pulse.weight() <= 1.0)
	pulse.advance(1.0)
	assert(is_zero_approx(pulse.weight()))
	print("FIRE_RECOIL_PULSE PASS: bounded, continuous retrigger, prone scale, settled zero")
	quit()
