extends SceneTree

const CARRY := preload("res://scripts/player/operator_two_hand_weapon_carry.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var weapon := Node3D.new()
	stage.add_child(weapon)
	weapon.rotation_degrees = Vector3(78.0, -35.0, 112.0)

	var trigger := _marker(weapon, "Socket_RightHand", Vector3.ZERO)
	var support := _marker(weapon, "Socket_LeftHand", Vector3(0.0, 0.0, -0.45))
	var barrel := _marker(weapon, "Socket_BarrelBase", Vector3.ZERO)
	var muzzle := _marker(weapon, "Socket_Muzzle", Vector3(0.0, 0.0, -0.80))
	var optic := _marker(weapon, "Socket_Optic", Vector3(0.0, 0.12, -0.10))

	var trigger_target := Vector3(1.0, 1.4, -2.0)
	var support_target := trigger_target + Vector3(0.55, 0.0, 0.0)
	var result := CARRY.place(
		weapon,
		trigger,
		support,
		barrel,
		muzzle,
		optic,
		trigger_target,
		support_target,
		Vector3.UP,
		Vector3.RIGHT
	)
	var barrel_direction := (muzzle.global_position - barrel.global_position).normalized()
	var rail_up := (optic.global_position - barrel.global_position)
	rail_up -= barrel_direction * rail_up.dot(barrel_direction)
	rail_up = rail_up.normalized()
	_expect(bool(result.get("applied", false)), "two-hand carry solve is applied")
	_expect(
		trigger.global_position.distance_to(trigger_target) <= 0.0001,
		"trigger socket remains on the animated right palm"
	)
	_expect(
		rad_to_deg(barrel_direction.angle_to(Vector3.RIGHT)) <= 0.05,
		"barrel follows the right-to-left hand direction"
	)
	_expect(
		rad_to_deg(rail_up.angle_to(Vector3.UP)) <= 0.05,
		"optic rail remains upright"
	)

	# The pass runs every rendered frame. Reapplying the same hand sample must
	# not accumulate an extra rotation or translation.
	var first_transform := weapon.global_transform
	CARRY.place(
		weapon,
		trigger,
		support,
		barrel,
		muzzle,
		optic,
		trigger_target,
		support_target,
		Vector3.UP,
		Vector3.RIGHT
	)
	_expect(
		weapon.global_transform.origin.distance_to(first_transform.origin) <= 0.0001,
		"repeated carry solves do not accumulate translation"
	)
	var repeated_rotation_error := weapon.global_transform.basis.get_rotation_quaternion().angle_to(
		first_transform.basis.get_rotation_quaternion()
	)
	print("TWO_HAND_WEAPON_CARRY_METRIC repeated_rotation_error_deg=%.6f" % rad_to_deg(repeated_rotation_error))
	_expect(
		repeated_rotation_error <= 0.001,
		"repeated carry solves do not accumulate rotation"
	)

	stage.queue_free()
	if failures.is_empty():
		print("TWO_HAND_WEAPON_CARRY_REGRESSION PASS")
		quit(0)
	else:
		push_error("TWO_HAND_WEAPON_CARRY_REGRESSION FAIL %s" % str(failures))
		quit(1)


func _marker(parent: Node3D, marker_name: String, position: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.position = position
	parent.add_child(marker)
	return marker


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("TWO_HAND_WEAPON_CARRY_CHECK PASS " + message)
	else:
		failures.append(message)
		push_error("TWO_HAND_WEAPON_CARRY_CHECK FAIL " + message)
