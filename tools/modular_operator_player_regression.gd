extends SceneTree

const ModularOperatorController := preload("res://scripts/player/modular_operator_controller.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var player_scene := load("res://scenes/player/modular_operator_player.tscn") as PackedScene
	_expect(player_scene != null, "modular operator player scene loads")
	if player_scene == null:
		_finish()
		return

	var player := player_scene.instantiate() as ModularOperatorController
	_expect(player != null, "modular player is ModularOperatorController")
	root.add_child(player)
	await process_frame
	await process_frame

	var skeleton := player.skeleton
	_expect(skeleton != null, "skeleton is live")
	if skeleton != null:
		_expect(skeleton.get_bone_count() >= 60, "skeleton has full bone rig (got %d)" % skeleton.get_bone_count())

	var target_pivot := player.target_pivot
	_expect(target_pivot != null, "target pivot exists")
	if target_pivot != null:
		_expect(target_pivot.has_node("SpineTargetWeaponAim"), "target pivot has SpineTargetWeaponAim")
		_expect(target_pivot.has_node("RHUpperArmWeaponTarget"), "target pivot has RHUpperArmWeaponTarget")
		_expect(target_pivot.has_node("RHWeaponTarget"), "target pivot has RHWeaponTarget")

	var weapon_holder := player.weapon_holder
	_expect(weapon_holder != null, "weapon holder exists")
	if weapon_holder != null:
		_expect(weapon_holder.has_node("LHikTarget"), "weapon holder has LHikTarget support grip")

	# Test Stances
	player.set_stance(ModularOperatorController.Stance.STANDING)
	_expect(is_equal_approx(player.target_pivot_y, 1.204), "standing target pivot is 1.204m")

	player.set_stance(ModularOperatorController.Stance.CROUCHING)
	_expect(is_equal_approx(player.target_pivot_y, 0.820), "crouch target pivot is 0.820m")

	player.set_stance(ModularOperatorController.Stance.PRONE)
	_expect(is_equal_approx(player.target_pivot_y, 0.220), "prone target pivot is 0.220m")

	# Test Weapon Modes
	player.set_weapon_mode(ModularOperatorController.WeaponMode.RIFLE)
	_expect(player.current_weapon_mode == ModularOperatorController.WeaponMode.RIFLE, "rifle mode is active")
	_expect(player.current_weapon_instance != null, "rifle instance is mounted")

	player.set_weapon_mode(ModularOperatorController.WeaponMode.PISTOL)
	_expect(player.current_weapon_mode == ModularOperatorController.WeaponMode.PISTOL, "pistol mode is active")
	_expect(player.current_weapon_instance != null, "pistol instance is mounted")

	player.set_weapon_mode(ModularOperatorController.WeaponMode.UNARMED)
	_expect(player.current_weapon_mode == ModularOperatorController.WeaponMode.UNARMED, "unarmed mode is active")
	_expect(player.current_weapon_instance == null, "unarmed has no mounted weapon")

	# Test Lab Scene
	var lab_scene := load("res://scenes/labs/modular_player_lab.tscn") as PackedScene
	_expect(lab_scene != null, "modular player lab scene loads")

	player.queue_free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("MODULAR_OPERATOR_PLAYER PASS %s" % message)
	else:
		push_error("MODULAR_OPERATOR_PLAYER FAIL %s" % message)
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("MODULAR_OPERATOR_PLAYER_REGRESSION PASS")
		quit(0)
	else:
		push_error("MODULAR_OPERATOR_PLAYER_REGRESSION FAIL %s" % str(_failures))
		quit(1)
