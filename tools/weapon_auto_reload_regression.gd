extends SceneTree

const ReloadCoordinator := preload("res://scripts/runtime/weapon_reload_coordinator.gd")
const AutoReloadPolicy := preload("res://scripts/weapons/weapon_auto_reload_policy.gd")

class FakeDriver:
	extends Node
	signal action_completed(clip_name: StringName)
	signal action_cancelled(clip_name: StringName)
	signal reload_commit_cue(clip_name: StringName)
	var play_count := 0

	func weapon_reload_duration_seconds() -> float:
		return 0.25

	func present_event(event_name: StringName, _context: Dictionary) -> Dictionary:
		if event_name != &"RELOAD_STARTED":
			return {"applied": false}
		play_count += 1
		return {"applied": true}

	func cancel_reload_action() -> bool:
		action_cancelled.emit(&"reload")
		return true


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
	_expect(weapon.reload_commits == 0, "ammo remains unchanged before the magazine-in cue")
	_expect(
		not bool(coordinator.cancel_for_fire())
		and bool(coordinator.pending)
		and weapon.reload_locked,
		"fire cannot cancel an empty-magazine reload"
	)
	driver.reload_commit_cue.emit(&"reload")
	_expect(weapon.reload_commits == 1 and weapon.magazine == 6, "magazine-in cue commits ammunition once")
	_expect(weapon.reload_locked, "magazine-in commit keeps fire locked through reload recovery")
	driver.action_completed.emit(&"reload")
	_expect(weapon.reload_commits == 1 and weapon.magazine == 6, "reload completion does not duplicate the ammo commit")
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
	_expect(not bool(coordinator.pending), "new zero-ammo auto reload waits while already airborne")
	_expect(not weapon.reload_locked, "queued airborne reload does not lock fire before animation starts")
	_expect(bool(coordinator.auto_reload_waiting_for_safe_state), "airborne start keeps one grounded retry queued")
	_expect(driver.play_count == 1, "airborne start does not flicker the animation")
	player.movement_state = &"STANDING"
	await physics_frame
	await process_frame
	_expect(bool(coordinator.pending), "queued reload starts after landing")
	_expect(driver.play_count == 2, "landing starts the queued animation exactly once")
	player.movement_state = &"AIRBORNE"
	await physics_frame
	await process_frame
	_expect(bool(coordinator.pending), "jump does not cancel an active reload")
	_expect(driver.play_count == 2, "jump does not restart the active reload animation")
	driver.reload_commit_cue.emit(&"reload")
	_expect(weapon.reload_commits == 2 and weapon.magazine == 6, "jumping reload commits at magazine-in")
	driver.action_completed.emit(&"reload")
	_expect(weapon.reload_commits == 2 and weapon.magazine == 6, "jumping reload recovery does not duplicate commit")
	weapon.magazine = 0
	weapon.reserve = 6
	player.movement_state = &"STANDING"
	weapon.ammo_changed.emit(0, 6)
	await process_frame
	await process_frame
	_expect(bool(coordinator.pending), "grounded replacement reload starts")
	_expect(driver.play_count == 3, "replacement reload starts exactly once")
	player.movement_state = &"ROLLING"
	await physics_frame
	await process_frame
	_expect(bool(coordinator.pending), "roll preserves the active reload commit")
	_expect(weapon.reload_locked, "rolling reload keeps its transaction lock")
	_expect(
		driver.play_count == 3,
		"roll does not cancel or restart the active reload animation"
	)
	player.movement_state = &"STANDING"
	await physics_frame
	await process_frame
	_expect(bool(coordinator.pending), "reload remains continuous after roll ends")
	_expect(driver.play_count == 3, "post-roll state uses the original reload playhead")
	driver.reload_commit_cue.emit(&"reload")
	driver.action_completed.emit(&"reload")
	_expect(
		weapon.reload_commits == 3 and weapon.magazine == 6,
		"movement-surviving reload commits the reserved ammunition"
	)

	weapon.magazine = 0
	weapon.reserve = 6
	player.movement_state = &"STANDING"
	weapon.ammo_changed.emit(0, 6)
	await process_frame
	await process_frame
	_expect(bool(coordinator.pending), "post-commit interruption case starts a reload")
	driver.reload_commit_cue.emit(&"reload")
	_expect(weapon.reload_commits == 4 and weapon.magazine == 6, "post-commit case loads ammunition at magazine-in")
	player.movement_state = &"ROLLING"
	await physics_frame
	await process_frame
	_expect(bool(coordinator.pending), "roll after magazine-in preserves reload recovery")
	_expect(weapon.reload_locked, "post-commit movement keeps reload ownership")
	_expect(weapon.magazine == 6, "movement does not remove committed ammunition")
	driver.action_completed.emit(&"reload")
	_expect(not bool(coordinator.pending), "authored completion ends movement-surviving reload")
	_expect(not weapon.reload_locked, "authored completion releases trigger ownership")
	_expect(
		not bool(coordinator.auto_reload_waiting_for_safe_state),
		"loaded weapon does not queue another automatic reload"
	)

	weapon.magazine = 3
	weapon.reserve = 6
	player.movement_state = &"STANDING"
	_expect(bool(coordinator.request_reload()), "partial-magazine reload starts")
	coordinator.call("_on_mobility_action_requested", &"DIVING")
	coordinator.call("_on_mobility_action_started", &"ROLLING")
	coordinator.call("_on_mobility_action_started", &"VAULTING")
	_expect(
		bool(coordinator.pending) and weapon.reload_locked,
		"dive roll and vault cannot cancel the reload timeline"
	)
	_expect(
		bool(coordinator.cancel_for_fire())
		and not bool(coordinator.pending)
		and not weapon.reload_locked,
		"fire with remaining rounds is the explicit reload interrupt"
	)
	_expect(
		weapon.magazine == 3 and weapon.reload_commits == 4,
		"pre-commit fire interruption preserves the remaining magazine"
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
