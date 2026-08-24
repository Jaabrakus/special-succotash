extends SceneTree

const RotationControlScript := preload(
	"res://scripts/labs/gunsmith/gunsmith_rotation_orbit_control.gd"
)

var failures: Array[String] = []
var axis_events: Array = []
var direction_events: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var control = RotationControlScript.new()
	root.add_child(control)
	control.connect("axis_delta_requested", Callable(self, "_on_axis_delta"))
	control.connect("hand_direction_delta_requested", Callable(self, "_on_direction_delta"))
	control.call("set_display_state", true, {"pitch": 12.0, "yaw": -8.0, "roll": 20.0})
	_expect(bool(control.hand_mode), "hand display mode is applied")
	_expect(is_equal_approx(float(control.axis_values.get("roll", 0.0)), 20.0), "display values are applied")

	var roll_press := InputEventMouseButton.new()
	roll_press.button_index = MOUSE_BUTTON_LEFT
	roll_press.pressed = true
	roll_press.position = Vector2(92.0, 56.0)
	control._gui_input(roll_press)
	var roll_motion := InputEventMouseMotion.new()
	roll_motion.position = Vector2(98.0, 56.0)
	roll_motion.relative = Vector2(6.0, 0.0)
	control._gui_input(roll_motion)
	_expect(not axis_events.is_empty() and String(axis_events.back()[0]) == "roll", "roll ring emits a roll delta")

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(98.0, 56.0)
	control._gui_input(release)

	var direction_press := InputEventMouseButton.new()
	direction_press.button_index = MOUSE_BUTTON_LEFT
	direction_press.pressed = true
	direction_press.position = Vector2(160.0, 56.0)
	control._gui_input(direction_press)
	var direction_motion := InputEventMouseMotion.new()
	direction_motion.position = Vector2(170.0, 51.0)
	direction_motion.relative = Vector2(10.0, -5.0)
	control._gui_input(direction_motion)
	_expect(not direction_events.is_empty(), "direction pad emits yaw and pitch deltas")
	if not direction_events.is_empty():
		_expect(is_equal_approx(float(direction_events.back()[0]), 7.5), "direction pad scales yaw consistently")
		_expect(is_equal_approx(float(direction_events.back()[1]), 3.25), "direction pad scales pitch consistently")

	control.queue_free()
	if failures.is_empty():
		print("GUNSMITH_ROTATION_ORBIT_CONTROL_REGRESSION PASS")
		quit(0)
	else:
		push_error("GUNSMITH_ROTATION_ORBIT_CONTROL_REGRESSION FAIL %s" % failures)
		quit(1)


func _on_axis_delta(axis_name: String, delta_degrees: float) -> void:
	axis_events.append([axis_name, delta_degrees])


func _on_direction_delta(yaw_delta: float, pitch_delta: float) -> void:
	direction_events.append([yaw_delta, pitch_delta])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
