class_name SocomMainTrainingWorld
extends Node

const PlayerScene := preload("res://scenes/player/native_ik_socom_player.tscn")
const CameraRig := preload("res://scripts/camera/socom_camera.gd")
const TargetDummy := preload("res://scripts/combat/lab_leak_target_dummy.gd")
const MovingTargetDummy := preload("res://scripts/combat/socom_moving_training_dummy.gd")
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapGameplay := preload("res://scripts/maps/socom_map_gameplay_contract.gd")
const MapRuntime := preload("res://scripts/maps/socom_map_runtime.gd")
const MapAmbience := preload("res://scripts/maps/socom_map_ambience_engine.gd")
const MapAudioAmbience := preload("res://scripts/maps/socom_map_audio_ambience.gd")
const BombScene := preload("res://scenes/objectives/demolition_bomb.tscn")
const PlayerProfile := preload("res://scripts/player/player_gameplay_profile.gd")
const ENVIRONMENT_SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
uniform vec4 albedo_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
void fragment() {
	ALBEDO = albedo_color.rgb;
	ROUGHNESS = 0.88;
}
"""

var host

var player:
	get: return host.get("player")
	set(value): host.set("player", value)
var camera_rig:
	get: return host.get("camera_rig")
	set(value): host.set("camera_rig", value)
var map_document: Dictionary:
	get: return host.get("active_map_document") as Dictionary
	set(value): host.set("active_map_document", value)
var target_dummies: Array:
	get: return host.get("target_dummies") as Array
var target_range_active: bool:
	get: return bool(host.get("target_range_active"))
	set(value): host.set("target_range_active", value)
var bomb_visuals: Array:
	get: return host.get("training_bomb_visuals") as Array
var bomb_sites: Array:
	get: return host.get("training_bomb_site_positions") as Array
var bomb_carried: bool:
	get: return bool(host.get("training_bomb_carried"))
	set(value): host.set("training_bomb_carried", value)
var bomb_planted: bool:
	get: return bool(host.get("training_bomb_planted"))
	set(value): host.set("training_bomb_planted", value)
var plant_progress: float:
	get: return float(host.get("training_bomb_plant_progress"))
	set(value): host.set("training_bomb_plant_progress", value)
var plant_seconds: float:
	get: return float(host.get("training_bomb_plant_seconds"))
	set(value): host.set("training_bomb_plant_seconds", value)
var toast_seconds: float:
	get: return float(host.get("training_bomb_toast_seconds"))
	set(value): host.set("training_bomb_toast_seconds", value)
var bomb_status: Label:
	get: return host.get("training_bomb_status_label") as Label


func configure(main_host: Node) -> void:
	host = main_host


func build_environment() -> void:
	var profile_started := Time.get_ticks_usec()
	map_document = MapDocument.load_active()
	_configure_acoustic_world(map_document)
	_profile_startup_step("map_document", profile_started)
	var phase_started := Time.get_ticks_usec()
	if not map_document.is_empty() and bool(map_document.get("enabled", true)):
		if host.has_node("World"):
			var world_node: Node = host.get_node("World")
			if world_node is CanvasItem or world_node is Node3D:
				world_node.visible = false
				world_node.process_mode = Node.PROCESS_MODE_DISABLED
		MapAmbience.build_into(host, map_document)
		_profile_startup_step("map_ambience", phase_started)
		phase_started = Time.get_ticks_usec()
		MapRuntime.build_into(host, map_document)
		_profile_startup_step("map_geometry", phase_started)
		phase_started = Time.get_ticks_usec()
		_build_objective_visuals()
		_profile_startup_step("map_objectives", phase_started)
		return
	if not host.has_node("World"):
		var world_env := WorldEnvironment.new()
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0.11, 0.13, 0.16)
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(0.72, 0.76, 0.82)
		environment.ambient_light_energy = 0.75
		world_env.environment = environment
		host.add_child(world_env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-48, -35, 0)
		sun.light_energy = 1.4
		sun.shadow_enabled = true
		host.add_child(sun)
		_add_box("Floor", Vector3(24, 0.25, 28), Vector3(0, -0.125, -5), Color(0.30, 0.32, 0.35))
	_add_box("RearWall", Vector3(8, 3.0, 0.35), Vector3(0, 1.5, 8.0), Color(0.45, 0.43, 0.39))
	_add_box("LeftWall", Vector3(0.35, 3.0, 9), Vector3(-4.2, 1.5, -1.0), Color(0.38, 0.41, 0.44))
	_add_box("LowCover", Vector3(5.0, 1.1, 0.6), Vector3(0, 0.55, -4.0), Color(0.37, 0.34, 0.31))
	_add_box("TallCover", Vector3(1.3, 2.2, 1.3), Vector3(3.0, 1.1, -7.0), Color(0.33, 0.36, 0.40))
	_add_box("FarMarker", Vector3(2.0, 3.0, 0.5), Vector3(0, 1.5, -13.0), Color(0.30, 0.39, 0.34))
	_add_box("RoofTestBuilding", Vector3(6.0, 4.0, 6.0), Vector3(7.0, 2.0, -3.0), Color(0.27, 0.29, 0.32))
	_add_box("RoofParapet", Vector3(6.0, 0.9, 0.25), Vector3(7.0, 4.45, -6.0), Color(0.39, 0.38, 0.36))
	_add_box("InteriorCeiling", Vector3(4.0, 0.30, 6.0), Vector3(-8.0, 2.55, -3.0), Color(0.25, 0.27, 0.30))
	_add_box("InteriorLeftWall", Vector3(0.30, 2.7, 6.0), Vector3(-10.0, 1.35, -3.0), Color(0.34, 0.36, 0.39))
	_add_box("InteriorRightWall", Vector3(0.30, 2.7, 6.0), Vector3(-6.0, 1.35, -3.0), Color(0.34, 0.36, 0.39))
	_add_box("InteriorBackWall", Vector3(4.0, 2.7, 0.30), Vector3(-8.0, 1.35, 0.0), Color(0.38, 0.37, 0.35))
	for index in range(-4, 5):
		var marker := MeshInstance3D.new()
		marker.mesh = BoxMesh.new()
		marker.mesh.size = Vector3(0.08, 0.08, 0.08)
		marker.position = Vector3(index * 1.5, 0.08, -10.0)
		host.add_child(marker)


func _profile_startup_step(label: String, started_usec: int) -> void:
	if OS.get_cmdline_user_args().has("--startup-profile"):
		print("STARTUP_DETAIL %s step_ms=%.2f" % [
			label,
			float(Time.get_ticks_usec() - started_usec) / 1000.0,
		])


func _build_objective_visuals() -> void:
	var layout := MapGameplay.demolition_layout(map_document)
	var pickups: Array = layout.get("bomb_pickups", [])
	if pickups.is_empty():
		return
	var objective_root := Node3D.new()
	objective_root.name = "PlaytestDemolitionObjectives"
	host.add_child(objective_root)
	for index in pickups.size():
		var bomb := BombScene.instantiate() as Node3D
		bomb.name = "CenterBomb%02d" % index
		bomb.position = Vector3(pickups[index])
		objective_root.add_child(bomb)
		bomb_visuals.append(bomb)
	bomb_sites.assign(layout.get("alpha_targets", []))
	bomb_sites.append_array(layout.get("bravo_targets", []))
	plant_seconds = maxf(float((layout.get("rules", {}) as Dictionary).get("plant_time_seconds", 5.0)), 0.1)


func update_bomb(delta: float) -> void:
	if not bool(host.get("public_training_mode")) or player == null or bomb_status == null:
		return
	toast_seconds = maxf(toast_seconds - delta, 0.0)
	if bomb_planted:
		bomb_status.text = "BOMB PLANTED" if toast_seconds > 0.0 else ""
		bomb_status.visible = toast_seconds > 0.0
		return
	if bomb_carried:
		_update_carried_bomb(delta)
		return
	var closest_bomb: Node3D
	var closest_distance := INF
	for bomb: Node3D in bomb_visuals:
		if not is_instance_valid(bomb) or not bomb.visible:
			continue
		var distance: float = player.global_position.distance_to(bomb.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_bomb = bomb
	var can_acquire := closest_bomb != null and closest_distance <= 1.6
	bomb_status.visible = can_acquire
	bomb_status.text = "F  ACQUIRE BOMB" if can_acquire else ""
	if not can_acquire or not Input.is_action_just_pressed("interact"):
		return
	bomb_carried = true
	for bomb: Node3D in bomb_visuals:
		if is_instance_valid(bomb):
			bomb.visible = false
	_set_bomb_backpack(true)
	toast_seconds = 2.4
	bomb_status.visible = true
	bomb_status.text = "BOMB ACQUIRED"


func _update_carried_bomb(delta: float) -> void:
	var closest_site := Vector3.INF
	var closest_distance := INF
	for site_position: Vector3 in bomb_sites:
		var distance: float = player.global_position.distance_to(site_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_site = site_position
	var can_plant := closest_site.is_finite() and closest_distance <= 1.8
	if can_plant and Input.is_action_pressed("interact"):
		plant_progress = minf(plant_progress + delta, plant_seconds)
		bomb_status.visible = true
		bomb_status.text = "PLANTING  %d%%" % int(round(plant_progress / plant_seconds * 100.0))
		if plant_progress >= plant_seconds:
			complete_bomb_plant(closest_site)
		return
	plant_progress = 0.0
	if can_plant:
		bomb_status.visible = true
		bomb_status.text = "HOLD F  PLANT BOMB"
	else:
		bomb_status.text = "BOMB ACQUIRED" if toast_seconds > 0.0 else ""
		bomb_status.visible = toast_seconds > 0.0


func complete_bomb_plant(site_position: Vector3) -> void:
	bomb_carried = false
	bomb_planted = true
	plant_progress = plant_seconds
	_set_bomb_backpack(false)
	if not bomb_visuals.is_empty():
		var planted: Node3D = bomb_visuals[0] as Node3D
		if is_instance_valid(planted):
			planted.global_position = site_position + Vector3(0.0, 0.02, 0.0)
			planted.global_rotation = Vector3.ZERO
			planted.visible = true
			planted.call("set_bomb_state", &"PLANTED", 0.0)
	toast_seconds = 2.4
	bomb_status.visible = true
	bomb_status.text = "BOMB PLANTED"


func spawn_target_range() -> void:
	if not target_dummies.is_empty():
		return
	spawn_target_dummy(Vector3(0.0, 0.0, -8.0), 180.0)
	spawn_target_dummy(Vector3(4.0, 0.0, -11.0), -90.0)
	spawn_target_dummy(Vector3(-4.0, 0.0, -13.0), 0.0)


func spawn_target_dummy(position: Vector3, yaw_degrees: float) -> void:
	var dummy = TargetDummy.new()
	dummy.position = position
	dummy.rotation_degrees.y = yaw_degrees
	host.add_child(dummy)
	target_dummies.append(dummy)


func set_target_range_active(enabled: bool) -> void:
	target_range_active = enabled
	if not map_document.is_empty():
		for dummy in target_dummies:
			if not is_instance_valid(dummy):
				continue
			dummy.visible = enabled
			dummy.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
			var hurtbox = dummy.call("get_hurtbox_rig") if dummy.has_method("get_hurtbox_rig") else null
			if hurtbox != null and hurtbox.has_method("set_enabled"):
				hurtbox.call("set_enabled", enabled)
		return
	if enabled:
		spawn_target_range()
		return
	for dummy in target_dummies:
		if is_instance_valid(dummy):
			dummy.queue_free()
	target_dummies.clear()


func build_player() -> void:
	var spawned_player: CharacterBody3D = null
	if host.has_node("Player") and host.get_node("Player") is CharacterBody3D:
		spawned_player = host.get_node("Player") as CharacterBody3D
	else:
		spawned_player = PlayerScene.instantiate() as CharacterBody3D
		spawned_player.name = "Player"
		host.add_child(spawned_player)
	spawned_player.position = MapDocument.player_spawn(map_document, Vector3(0, 0.05, 0.5))
	host.set("player", spawned_player)
	player = spawned_player
	var profile := PlayerProfile.load_profile()
	player.call("configure_max_health", float(profile.get("max_health", 100.0)))
	host.set("grenade_limits", (profile.get("grenade_limits", {}) as Dictionary).duplicate(true))
	host.set("grenade_inventory", (host.get("grenade_limits") as Dictionary).duplicate(true))
	if not map_document.is_empty():
		_spawn_authored_dummies()
		if target_dummies.is_empty():
			spawn_target_range()
	elif target_range_active:
		spawn_target_range()
	if not map_document.is_empty():
		var map_audio = MapAudioAmbience.new()
		map_audio.name = "MapAudioAmbience"
		host.add_child(map_audio)
		map_audio.call("configure", map_document, player)
		host.set("map_audio_ambience", map_audio)


func _spawn_authored_dummies() -> void:
	for object: Dictionary in map_document.get("objects", []):
		var type_name := StringName(object.get("type", ""))
		if type_name not in [&"training_dummy", &"moving_training_dummy"]:
			continue
		var dummy = MovingTargetDummy.new() if type_name == &"moving_training_dummy" else TargetDummy.new()
		dummy.name = String(object.get("name", "Training Dummy")).validate_node_name()
		dummy.position = MapDocument.data_to_vector(object.get("position", {}))
		dummy.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
		dummy.set_meta("map_object_id", String(object.get("id", "")))
		var properties: Dictionary = object.get("properties", {})
		dummy.max_health = clampf(float(properties.get("health", 100.0)), 1.0, 10000.0)
		dummy.current_health = dummy.max_health
		host.add_child(dummy)
		if type_name == &"moving_training_dummy":
			dummy.call("configure_patrol", properties)
		target_dummies.append(dummy)


func set_roof_test(enabled: bool) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(7.0, 4.05, -3.0) if enabled else Vector3(0.0, 0.05, 0.5)


func set_indoor_test(enabled: bool) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(-8.0, 0.05, -3.0) if enabled else Vector3(0.0, 0.05, 0.5)


func set_wall_test(enabled: bool) -> void:
	player.velocity = Vector3.ZERO
	if enabled:
		player.global_position = (
			Vector3(-2.55, 0.05, -1.0)
			if OS.get_cmdline_user_args().has("--wall-entry-test")
			or OS.get_cmdline_user_args().has("--wall-follow-test")
			or OS.get_cmdline_user_args().has("--camera-stress-test")
			else Vector3(-3.72, 0.05, -1.0)
		)
		if camera_rig:
			camera_rig.yaw = deg_to_rad(20.0)
			camera_rig.pitch = deg_to_rad(-6.0)
			camera_rig.reset_camera_to_target()
	else:
		player.global_position = Vector3(0.0, 0.05, 0.5)
		reset_test_camera()


func reset_test_camera() -> void:
	if camera_rig:
		camera_rig.yaw = player.global_rotation.y
		camera_rig.pitch = deg_to_rad(-2.0)
		camera_rig.reset_camera_to_target()


func build_camera() -> void:
	var rig: Node3D = null
	if host.has_node("CameraRig"):
		rig = host.get_node("CameraRig") as Node3D
	elif host.has_node("IndependentCameraRig"):
		rig = host.get_node("IndependentCameraRig") as Node3D
	else:
		rig = CameraRig.new()
		rig.name = "IndependentCameraRig"
		host.add_child(rig)
	rig.set("target", player)
	var mannequin: Node = player.get_node_or_null("Mannequin") if player != null else null
	if mannequin != null:
		rig.set("head_marker", mannequin.get("head_marker"))
		rig.set("torso_marker", mannequin.get("torso_marker"))
		rig.set("pelvis_marker", mannequin.get("pelvis_marker"))
		rig.set("feet_marker", mannequin.get("feet_marker"))
	elif player != null:
		rig.set("head_marker", player.get("head_marker"))
		rig.set("torso_marker", player.get("torso_marker"))
		rig.set("pelvis_marker", player.get("pelvis_marker"))
		rig.set("feet_marker", player.get("feet_marker"))
	host.set("camera_rig", rig)
	camera_rig = rig
	if bool(host.get("wall_test_active")):
		rig.set("yaw", deg_to_rad(-90.0) if OS.get_cmdline_user_args().has("--wall-follow-test") else deg_to_rad(20.0))
		rig.set("pitch", deg_to_rad(-6.0))
	elif OS.get_cmdline_user_args().has("--side-orbit-test"):
		rig.set("yaw", deg_to_rad(90.0))
		rig.set("pitch", deg_to_rad(20.0) if OS.get_cmdline_user_args().has("--upward-aim-test") else deg_to_rad(-2.0))
	elif OS.get_cmdline_user_args().has("--up-orbit-test"):
		rig.set("yaw", deg_to_rad(-20.0))
		rig.set("pitch", deg_to_rad(9.0))
	else:
		rig.set("yaw", player.global_rotation.y)
	var acoustic: Node = host.get_node_or_null("/root/AcousticPropagation")
	if acoustic != null and acoustic.has_method("set_listener"):
		acoustic.call("set_listener", rig)


func _configure_acoustic_world(document: Dictionary) -> void:
	var acoustic: Node = host.get_node_or_null("/root/AcousticPropagation")
	if acoustic != null and acoustic.has_method("configure_map"):
		acoustic.call("configure_map", document)


func _set_bomb_backpack(visible: bool) -> void:
	var mannequin: Node = player.get_node_or_null("Mannequin") if player != null else null
	if mannequin != null and mannequin.has_method("set_bomb_backpack_visible"):
		mannequin.call("set_bomb_backpack_visible", visible)
	elif player != null and player.has_method("set_bomb_backpack_visible"):
		player.call("set_bomb_backpack_visible", visible)


func _add_box(box_name: String, size: Vector3, position: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = position
	host.add_child(body)
	var shape_node := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape_node.shape = box_shape
	body.add_child(shape_node)
	var mesh_node := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var shader := Shader.new()
	shader.code = ENVIRONMENT_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("albedo_color", color)
	mesh_node.material_override = material
	mesh_node.mesh = box_mesh
	body.add_child(mesh_node)
