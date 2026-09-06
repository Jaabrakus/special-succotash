class_name SocomMainWeaponRuntime
extends Node

const WeaponController := preload("res://scripts/weapons/socom_weapon_controller.gd")
const ReloadCoordinator := preload("res://scripts/runtime/weapon_reload_coordinator.gd")
const TracerSystem := preload("res://scripts/weapons/lab_leak_tracer_system.gd")
const AudioEngine := preload("res://scripts/audio/lab_leak_audio_engine.gd")

var host

var player:
	get: return host.get("player")
var camera_rig:
	get: return host.get("camera_rig")
var dynamic_reticle:
	get: return host.get("dynamic_reticle")
var weapon_controller:
	get: return host.get("weapon_controller")
	set(value): host.set("weapon_controller", value)
var reload_coordinator:
	get: return host.get("reload_coordinator")
	set(value): host.set("reload_coordinator", value)


func configure(main_host: Node) -> void:
	host = main_host


func build_weapon_controller() -> void:
	AudioEngine.initialize(self)
	weapon_controller = WeaponController.new()
	weapon_controller.name = "WeaponController"
	host.add_child(weapon_controller)
	var active_player: CharacterBody3D = host.get("player") as CharacterBody3D
	var active_camera = host.get("camera_rig")
	weapon_controller.configure(active_player, active_camera)
	weapon_controller.authoritative_shot.connect(on_authoritative_shot)
	weapon_controller.ammo_changed.connect(on_ammo_changed)
	weapon_controller.reload_fire_interrupt_requested.connect(
		on_reload_fire_interrupt_requested
	)


func build_reload_coordinator() -> void:
	reload_coordinator = ReloadCoordinator.new()
	reload_coordinator.name = "WeaponReloadCoordinator"
	host.add_child(reload_coordinator)
	reload_coordinator.configure(player, weapon_controller)
	reload_coordinator.pending_changed.connect(func(pending: bool):
		host.set("reload_commit_pending", pending)
		_update_status()
	)


func request_reload() -> bool:
	return reload_coordinator != null and reload_coordinator.request_reload()


func on_ammo_changed(_magazine: int, _reserve: int) -> void:
	_update_status()


func on_reload_fire_interrupt_requested() -> void:
	if reload_coordinator != null:
		reload_coordinator.cancel_for_fire()


func on_authoritative_shot(result: Dictionary) -> void:
	var origin := Vector3(result.get("origin", Vector3.ZERO))
	var hit_position := Vector3(result.get("hit_pos", origin))
	var hit_normal := Vector3(result.get("normal", Vector3.UP))
	var shot_direction := (
		(hit_position - origin).normalized()
		if hit_position.distance_squared_to(origin) > 0.01
		else Vector3.FORWARD
	)
	# Ballistic/tracer origins stay the accepted shot snapshot. Only an opted-in
	# local muzzle effect follows the weapon's presented pose before drawing.
	TracerSystem.spawn_muzzle_flash(
		host.get_tree(), origin, shot_direction, _presented_muzzle_effect_source()
	)
	for projectile: Dictionary in result.get("projectiles", [result]):
		TracerSystem.spawn_tracer(
			host.get_tree(), origin, Vector3(projectile.get("hit_pos", hit_position)),
			Color(1.0, 0.88, 0.35), float(result.get("muzzle_velocity_mps", 715.0))
		)
	var mannequin = player.get_node_or_null("Mannequin") if player != null else null
	if mannequin != null and mannequin.has_method("get_active_ejection_marker"):
		var ejection := mannequin.get_active_ejection_marker() as Marker3D
		if ejection != null:
			var eject_direction := (
				ejection.global_basis.y + ejection.global_basis.z * 0.45
			).normalized()
			TracerSystem.spawn_shell_casing(
				host.get_tree(), ejection.global_position, eject_direction
			)
	if dynamic_reticle:
		var composure_kick := float(result.get("reticle_bounce", 1.0))
		dynamic_reticle.notify_shot(
			int(result.get("continuous_count", 1)),
			composure_kick * (1.0 + float(result.get("spread_deg", 0.0)) * 0.12)
		)
	if TracerSystem.is_trajectory_debug_enabled():
		TracerSystem.spawn_trajectory_reference(
			host.get_tree(), camera_rig.global_position, camera_rig.weapon_aim_point,
			Color(0.15, 0.95, 1.0)
		)
		TracerSystem.spawn_trajectory_reference(
			host.get_tree(), origin, camera_rig.weapon_aim_point, Color.WHITE
		)
	# Let the acoustic engine resolve walls, portals, and reflections. Exclude
	# the local operator collision shapes so the shooter's own body cannot make
	# a clear muzzle-to-camera path sound blocked.
	var sound_config: Dictionary = weapon_controller.get("equipped_weapon_config")
	AudioEngine.play_gunshot(
		host.get_tree(), bool(sound_config.get("ballistics", {}).get("is_silenced", false)),
		origin, false, _local_acoustic_exclusions(), String(sound_config.get("weapon_id", ""))
	)
	for projectile: Dictionary in result.get("projectiles", [result]):
		var projectile_position := Vector3(projectile.get("hit_pos", hit_position))
		var projectile_normal := Vector3(projectile.get("normal", hit_normal))
		var damage_result: Variant = projectile.get("damage_result", {})
		if damage_result is Dictionary and bool((damage_result as Dictionary).get("accepted", false)):
			TracerSystem.spawn_body_hit_effect(
				host.get_tree(), projectile_position, projectile_normal,
				bool((damage_result as Dictionary).get("headshot", false))
			)
			AudioEngine.play_body_impact(
				host.get_tree(), projectile_position,
				bool((damage_result as Dictionary).get("headshot", false))
			)
			if dynamic_reticle:
				dynamic_reticle.notify_hit()
		else:
			TracerSystem.spawn_impact_effect(host.get_tree(), projectile_position, projectile_normal)


func _presented_muzzle_effect_source() -> Node3D:
	if weapon_controller == null or player == null:
		return null
	var config: Dictionary = weapon_controller.get("equipped_weapon_config")
	var handling: Dictionary = config.get("handling_profile", {})
	var presentation: Dictionary = handling.get("presentation", {})
	if not bool(presentation.get("muzzle_effect_follows_presented_muzzle", false)):
		return null
	var mannequin := player.get_node_or_null("Mannequin") as Node
	if mannequin == null or not mannequin.has_method("get_active_muzzle_marker"):
		return null
	return mannequin.call("get_active_muzzle_marker") as Node3D


func _local_acoustic_exclusions() -> Array:
	var exclusions: Array = []
	if player is CollisionObject3D:
		exclusions.append((player as CollisionObject3D).get_rid())
	if player != null:
		for child in player.find_children("*", "CollisionObject3D", true, false):
			if child is CollisionObject3D:
				exclusions.append((child as CollisionObject3D).get_rid())
	return exclusions


func _update_status() -> void:
	host.call("_update_player_status_ui")
