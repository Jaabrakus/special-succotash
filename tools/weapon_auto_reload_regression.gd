extends SceneTree

const ReloadCoordinator := preload("res://scripts/runtime/weapon_reload_coordinator.gd")
const AutoReloadPolicy := preload("res://scripts/weapons/weapon_auto_reload_policy.gd")

class FakeDriver:
	extends Node
	signal action_completed(clip_name: StringName)
	signal action_cancelled(clip_name: StringName)
	var play_count := 0

	func weapon_reload_duration_seconds() -> float:
		return 0.25

	func present_event(event_name: StringName, _context: Dictionary) -> Dictionary:
		if event_name != &"RELOAD_STARTED":
			return {"applied": false}
		play_count += 1
		return {"applied": true}


class FakePlayer:
	extends Node
	var movement_state := &"STANDING"

	func get_motion_state_name() -> StringName:
		return movement_state


class FakeMannequin:
	extends Node
	var production_animation: Node


class FakeWeaponController:
	extends Node
	signal ammo_changed(rounds_in_magazine: int, reserve_rounds: int)
	var magazine := 1
	var reserve := 6
	var reload_commits := 0
	var reload_locked := false

	func get_ammo_snapshot() -> Dictionary:
		return {"rounds_in_magazine": magazine, "reserve_ammo": reserve}

	func request_reload() -> bool:
		reload_commits += 1
		magazine = reserve
		reserve = 0
		ammo_changed.emit(magazine, reserve)
		return true

	func set_reload_locked(active: bool) -> void:
		reload_locked = active


var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_expect(AutoReloadPolicy.should_start(0, 12, false), "shared policy starts at zero rounds with reserve ammo")
	_expect(not AutoReloadPolicy.should_start(0, 0, false), "shared policy does not reload without reserve ammo")
	_expect(not AutoReloadPolicy.should_start(0, 12, true), "shared policy does not restart an active reload")
	var player := FakePlayer.new()
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
	_expect(weapon.reload_locked, "active reload exclusively owns the trigger boundary")
	_expect(driver.play_count == 1, "auto reload starts exactly one animation")
	weapon.ammo_changed.emit(0, 6)
	await process_frame
	_expect(driver.play_count == 1, "repeated empty-ammo updates do not restart reload")
	driver.action_completed.emit(&"reload")
	_expect(weapon.reload_commits == 1 and weapon.magazine == 6, "ammo transfers only when the reload animation completes")
	_expect(not weapon.reload_locked, "completed reload returns trigger ownership once")
	weapon.magazine = 0
	weapon.reserve = 0
	weapon.ammo_changed.emit(0, 0)
	await process_frame
	_expect(driver.play_count == 1, "zero reserve does not start an empty reload")

	weapon.magazine = 0
	weapon.reserve = 6
	player.movement_state = &"AIRBORNE"
	weapon.ammo_changed.emit(0, 6)
	await process_frame
	await process_frame
	_expect(not bool(coordinator.pending), "zero-ammo auto reload waits while airborne")
	_expect(not weapon.reload_locked, "queued airborne reload does not lock fire before animation starts")
	_expect(
		bool(coordinator.auto_reload_waiting_for_safe_state),
		"airborne zero-ammo state keeps one grounded retry queued"
	)
	_expect(driver.play_count == 1, "airborne auto reload does not flicker the animation")
	player.movement_state = &"STANDING"
	await physics_frame
	await process_frame
	_expect(bool(coordinator.pending), "queued zero-ammo reload starts after landing")
	_expect(driver.play_count == 2, "landing starts the queued reload exactly once")
	player.movement_state = &"AIRBORNE"
	driver.action_cancelled.emit(&"reload")
	await process_frame
	await process_frame
	_expect(not bool(coordinator.pending), "jump interruption cancels the active reload commit")
	_expect(not weapon.reload_locked, "cancelled reload releases trigger ownership")
	_expect(
		bool(coordinator.auto_reload_waiting_for_safe_state),
		"cancelled zero-ammo reload remains queued for landing"
	)
	player.movement_state = &"STANDING"
	await physics_frame
	await process_frame
	_expect(bool(coordinator.pending), "cancelled zero-ammo reload restarts after landing")
	_expect(driver.play_count == 3, "grounded retry starts one replacement animation")
	driver.action_completed.emit(&"reload")
	_expect(
		weapon.reload_commits == 2 and weapon.magazine == 6,
		"grounded replacement reload commits the reserved ammunition"
	)

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
