extends SceneTree

const ReloadCoordinator := preload("res://scripts/runtime/weapon_reload_coordinator.gd")
const AutoReloadPolicy := preload("res://scripts/weapons/weapon_auto_reload_policy.gd")

class FakeDriver:
	extends Node
	signal action_completed(clip_name: StringName)
	signal action_cancelled(clip_name: StringName)

	func weapon_reload_duration_seconds() -> float:
		return 0.25


class FakeMannequin:
	extends Node
	var production_animation: Node
	var play_count := 0

	func play_operator_semantic_action_timed(_action: StringName, _duration: float, _blend: float) -> bool:
		play_count += 1
		return true


class FakeWeaponController:
	extends Node
	signal ammo_changed(rounds_in_magazine: int, reserve_rounds: int)
	var magazine := 1
	var reserve := 6
	var reload_commits := 0

	func get_ammo_snapshot() -> Dictionary:
		return {"rounds_in_magazine": magazine, "reserve_ammo": reserve}

	func request_reload() -> bool:
		reload_commits += 1
		magazine = reserve
		reserve = 0
		ammo_changed.emit(magazine, reserve)
		return true


var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_expect(AutoReloadPolicy.should_start(0, 12, false), "shared policy starts at zero rounds with reserve ammo")
	_expect(not AutoReloadPolicy.should_start(0, 0, false), "shared policy does not reload without reserve ammo")
	_expect(not AutoReloadPolicy.should_start(0, 12, true), "shared policy does not restart an active reload")
	var player := Node.new()
	root.add_child(player)
	var driver := FakeDriver.new()
	var mannequin := FakeMannequin.new()
	mannequin.name = "Mannequin"
	mannequin.production_animation = driver
	mannequin.add_child(driver)
	player.add_child(mannequin)
	var weapon := FakeWeaponController.new()
	root.add_child(weapon)
	var coordinator = ReloadCoordinator.new()
	root.add_child(coordinator)
	coordinator.configure(player, weapon)

	weapon.magazine = 0
	weapon.reserve = 6
	weapon.ammo_changed.emit(0, 6)
	await process_frame
	_expect(bool(coordinator.pending), "empty magazine starts the authored reload")
	_expect(mannequin.play_count == 1, "auto reload starts exactly one animation")
	weapon.ammo_changed.emit(0, 6)
	await process_frame
	_expect(mannequin.play_count == 1, "repeated empty-ammo updates do not restart reload")
	driver.action_completed.emit(&"reload")
	_expect(weapon.reload_commits == 1 and weapon.magazine == 6, "ammo transfers only when the reload animation completes")
	weapon.magazine = 0
	weapon.reserve = 0
	weapon.ammo_changed.emit(0, 0)
	await process_frame
	_expect(mannequin.play_count == 1, "zero reserve does not start an empty reload")

	coordinator.queue_free()
	weapon.queue_free()
	player.queue_free()
	if failures.is_empty():
		print("WEAPON_AUTO_RELOAD_REGRESSION PASS")
		quit(0)
	else:
		push_error("WEAPON_AUTO_RELOAD_REGRESSION FAIL %s" % failures)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
