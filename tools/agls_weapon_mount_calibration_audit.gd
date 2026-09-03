extends SceneTree

## Read-only live calibration probe. It derives the local weapon-axis adapter
## required to make the imported M4 bore face the camera-owned convergence
## point while the AGLS ik_hand_gun helper owns the mount.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		push_error("AGLS_WEAPON_MOUNT_CALIBRATION_AUDIT FAIL main scene")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	for _frame in range(45):
		await process_frame
	var player := scene.get_node("Player") as CharacterBody3D
	var mannequin := player.get_node("Mannequin")
	var driver = mannequin.get_node("ProductionAnimation")
	mannequin.set_process(false)
	var target := player.global_position + Vector3(0.0, 1.35, -25.0)
	driver.call(
		"set_visual_inputs",
		Vector2(0.0, 1.0), &"STANDING", 0.0, 0.0, 1.0, false, 0.0,
		0.65, &"LOCOMOTION", 0.0, &"WALK", 2.0,
		target, Vector2(0.0, 1.0), 1.0, &"SUSTAINED", 0.0
	)
	for _frame in range(12):
		await process_frame
	var mounted_weapon := driver.get("weapon_node") as Node3D
	if mounted_weapon == null:
		push_error("AGLS_WEAPON_MOUNT_CALIBRATION_AUDIT FAIL mounted weapon")
		quit(1)
		return
	var initial_mount_basis := mounted_weapon.basis
	var weapon_model := mounted_weapon.find_child("WeaponMesh", true, false) as Node3D
	var initial_model_basis := weapon_model.basis if weapon_model != null else Basis.IDENTITY
	for iteration in range(8):
		var muzzle: Vector3 = mannequin.call("get_active_muzzle_position")
		var barrel: Vector3 = mannequin.call("get_active_barrel_direction")
		var desired := muzzle.direction_to(target)
		var error_deg := rad_to_deg(barrel.angle_to(desired))
		print("AGLS_WEAPON_MOUNT_CALIBRATION iteration=%d error_deg=%.6f local_rotation_deg=%s barrel=%s desired=%s" % [
			iteration,
			error_deg,
			mounted_weapon.rotation_degrees,
			barrel,
			desired,
		])
		if error_deg <= 0.001:
			break
		var correction := Quaternion(barrel, desired)
		var current := mounted_weapon.global_transform
		mounted_weapon.global_transform = Transform3D(
			Basis(correction) * current.basis,
			current.origin
		)
	var compensated_model_basis := (
		mounted_weapon.basis.inverse() * initial_mount_basis * initial_model_basis
	).orthonormalized()
	print(
		"AGLS_WEAPON_MOUNT_CALIBRATION_AUDIT PASS derived_local_rotation_deg=%s compensated_model_rotation_deg=%s" % [
			mounted_weapon.rotation_degrees,
			compensated_model_basis.get_euler(EULER_ORDER_YXZ) * (180.0 / PI),
		]
	)
	quit(0)
