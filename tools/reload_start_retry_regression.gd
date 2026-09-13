extends SceneTree

const Coordinator := preload("res://scripts/runtime/weapon_reload_coordinator.gd")
const Fixtures := preload("res://tools/weapon_auto_reload_regression.gd")

class Driver extends Fixtures.FakeDriver:
	var ready_for_reload := false
	func present_event(event_name: StringName, context: Dictionary) -> Dictionary:
		if not ready_for_reload:
			return {"applied": false}
		return super.present_event(event_name, context)

class Weapon extends Fixtures.FakeWeaponController:
	func can_reload() -> bool:
		return reserve > 0 and magazine < 6

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var player := Fixtures.FakePlayer.new()
	root.add_child(player)
	var mannequin := Fixtures.FakeMannequin.new()
	mannequin.name = "Mannequin"
	player.add_child(mannequin)
	var driver := Driver.new()
	mannequin.add_child(driver)
	mannequin.production_animation = driver
	var weapon := Weapon.new()
	root.add_child(weapon)
	var coordinator := Coordinator.new()
	root.add_child(coordinator)
	coordinator.configure(player, weapon)
	weapon.magazine = 0
	coordinator._request_auto_reload()
	_check(coordinator.auto_reload_waiting_for_safe_state, "rejected start stays queued")
	_check(not coordinator.pending and not weapon.reload_locked and weapon.reload_commits == 0, "rejected start neither locks nor commits ammo")
	driver.ready_for_reload = true
	for frame in 4:
		await physics_frame
		await process_frame
	_check(coordinator.pending and driver.play_count == 1, "ready animation starts once without another ammo event")
	weapon.ammo_changed.emit(0, 6)
	await process_frame
	_check(driver.play_count == 1, "duplicate empty update does not restart accepted reload")
	driver.reload_commit_cue.emit(&"reload")
	driver.action_completed.emit(&"reload")
	_check(weapon.reload_commits == 1 and not coordinator.pending, "cue and completion commit ammo exactly once")
	driver.ready_for_reload = false
	weapon.magazine = 0
	weapon.reserve = 6
	coordinator._request_auto_reload()
	weapon.reserve = 0
	for frame in 4:
		await physics_frame
		await process_frame
	_check(not coordinator.auto_reload_waiting_for_safe_state, "ineligible queued reload is discarded")
	coordinator.queue_free()
	weapon.queue_free()
	player.queue_free()
	print("RELOAD_START_RETRY_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
