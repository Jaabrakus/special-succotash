extends SceneTree
const Operator := preload("res://scripts/network/socom_network_operator.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var actor := Operator.new()
	actor.visual_runtime_enabled = false
	actor.set_local_input_enabled(false)
	root.add_child(actor)
	actor.set_physics_process(false)
	actor.velocity = Vector3(4, 0, 0)
	actor.rotation.y = 0.7
	actor.set_authoritative_snapshot(Vector3(-0.3, 0, 0), 0.0, Vector3.ZERO, 0, 100.0, true)
	assert(actor.position == Vector3.ZERO, "small snapshot must not move body in render callback")
	assert(actor.velocity == Vector3(4, 0, 0), "small correction preserves predicted velocity")
	assert(is_equal_approx(actor.rotation.y, 0.7), "small correction preserves current yaw")
	assert(actor.pending_position_correction == Vector3(-0.3, 0, 0))
	actor.velocity = Vector3.ZERO
	actor._physics_process(1.0 / 60.0)
	assert(actor.position.x < 0.0 and actor.position.x > -0.3, "physics applies a partial correction")
	assert(absf(actor.pending_position_correction.x) < 0.3, "pending correction decays")
	actor.set_authoritative_snapshot(Vector3(5, 0, 0), 0.0, Vector3.ZERO, 0, 75.0, true)
	assert(actor.position == Vector3(5, 0, 0), "large error retains authoritative snap")
	assert(actor.pending_position_correction == Vector3.ZERO)
	assert(actor.current_health == 75.0)
	actor.free()
	print("LOCAL_SNAPSHOT_SMOOTHING PASS")
	quit()
