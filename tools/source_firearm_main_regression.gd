extends SceneTree

## New main scene only; never reloads or drives the user's running game.
const Contract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const Ballistics := preload("res://scripts/weapons/weapon_ballistics.gd")
const Policy := preload("res://scripts/weapons/source_firearm_policy.gd")
const Target := preload("res://scripts/combat/lab_leak_target_dummy.gd")
var failures: Array[String] = []
var census: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var game: Node3D
var player: CharacterBody3D
var camera_rig: Node3D
var weapon: Node
var accepted_signals := 0
var capture := false
var output := "/private/tmp/source-firearm-main"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--capture": capture = true
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	if "--automated-test" in OS.get_cmdline_user_args():
		_expect(false, "Omit --automated-test: it disables gameplay actions")
		_finish()
		return
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	ProjectSettings.set_setting("socom/session/public_training", true)
	root.size = Vector2i(1280, 800)
	game = load("res://main.tscn").instantiate() as Node3D
	game.get_node("IndependentCameraRig").set("capture_mouse_on_ready", false)
	root.add_child(game)
	current_scene = game
	player = game.get_node("Player") as CharacterBody3D
	camera_rig = game.get_node("IndependentCameraRig") as Node3D
	player.call("set_local_input_enabled", false)
	camera_rig.set("orbit_input_enabled", false)
	await _frames(60)
	weapon = game.get("weapon_controller") as Node
	if weapon == null:
		_expect(false, "main did not create its weapon controller")
		_finish()
		return
	weapon.call("set_input_enabled", false)
	weapon.connect("authoritative_shot", func(_shot: Dictionary): accepted_signals += 1)
	_census_profiles()
	_install_platform()
	camera_rig.call("set_aim_angles", 0.0, 0.0, true)
	camera_rig.call("reset_camera_to_target")
	await _frames(90)
	for id in ["m4a1", "mark_23", "870", "assaultrifle_1"]:
		await _live_shot(id)
	_finish()


func _census_profiles() -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Policy.PATH))
	var profiles: Dictionary = saved.get("profiles", {})
	_expect(profiles.size() == 32, "saved source policy must name exactly 32 verified profiles")
	var session: Node = load("res://multiplayer_slice.tscn").instantiate()
	var server_ballistics := Ballistics.new()
	var ids := profiles.keys()
	ids.sort()
	ids.append("assaultrifle_1")
	for id: String in ids:
		var path := "res://config/weapons/%s.json" % id
		var config: Dictionary = Contract.load_config(path)
		_expect(not config.is_empty(), id + " config exists")
		_expect(bool(weapon.call("_apply_weapon_config", config)), id + " main config accepted")
		session.call("_apply_ballistics_profile", server_ballistics, config)
		var local: Node = weapon.get("ballistics") as Node
		var actual: Dictionary = local.get("trajectory_policy")
		var expected := Policy.POLICY_ID if profiles.has(id) else "project_hitscan"
		_expect(actual == server_ballistics.trajectory_policy, id + " main/server policy parity")
		_expect(String(actual.get("policy_id", "")) == expected, id + " expected policy")
		var fields := ["max_range", "pellet_count", "pellet_damage", "damage_per_shot",
			"muzzle_velocity_mps", "fire_interval", "damage_falloff_start_m",
			"damage_falloff_end_m", "minimum_damage_multiplier", "headshot_multiplier"]
		var values: Dictionary = {}
		var saved_fields := {"max_range": "max_range_m", "pellet_count": "pellet_count",
			"pellet_damage": "pellet_damage", "damage_per_shot": "damage",
			"muzzle_velocity_mps": "muzzle_velocity_mps", "damage_falloff_start_m": "damage_falloff_start_m",
			"damage_falloff_end_m": "damage_falloff_end_m", "minimum_damage_multiplier": "minimum_damage_multiplier",
			"headshot_multiplier": "headshot_multiplier"}
		var authored: Dictionary = config.get("ballistics", {})
		if actual.has("combat"):
			# Source mode's shared saved contract overrides earlier custom tuning.
			authored = authored.duplicate(true)
			var source: Dictionary = actual.combat
			authored.max_range_m = source.maximum_range_m
			authored.pellet_count = source.pellet_count
			authored.damage = local.get("source_damage_math").calculate_projectile_damage(
				source.impact_damage, source.damage_modifier, 0.0, source.effective_range_m, source.maximum_range_m)
			authored.pellet_damage = authored.damage
			authored.damage_falloff_start_m = source.effective_range_m
			authored.damage_falloff_end_m = source.maximum_range_m
			authored.minimum_damage_multiplier = 0.0
		for field: String in fields:
			_expect(is_equal_approx(float(local.get(field)), float(server_ballistics.get(field))),
				id + " numeric main/server parity: " + field)
			values[field] = local.get(field)
			var saved_key := String(saved_fields.get(field, ""))
			if authored.has(saved_key):
				_expect(is_equal_approx(float(local.get(field)), float(authored[saved_key])),
					id + " retains saved numeric setting: " + field)
		_expect(is_equal_approx(float(local.get("fire_interval")), 60.0 / float(authored.get("fire_rate_rpm", 600.0))),
			id + " retains saved fire cadence")
		census.append({"weapon_id": id, "config_sha256": FileAccess.get_sha256(path),
			"main_policy": actual.duplicate(true), "server_policy": server_ballistics.trajectory_policy.duplicate(true),
			"numeric_settings": values})
	server_ballistics.free()
	session.free()


func _install_platform() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "SourceFirearmProofFloor"
	floor_body.position = Vector3(500.0, -0.5, 500.0)
	var shape := BoxShape3D.new()
	shape.size = Vector3(40.0, 1.0, 40.0)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	floor_body.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.22, 0.24, 0.26)
	mesh.material_override = material
	floor_body.add_child(mesh)
	game.add_child(floor_body)
	player.global_position = Vector3(500.0, 0.02, 500.0)
	player.velocity = Vector3.ZERO


func _live_shot(id: String) -> void:
	var path := "res://config/weapons/%s.json" % id
	var ok: bool = weapon.call("apply_authorized_weapon_pickup", path)
	_expect(ok, id + " authorized full equip succeeds")
	if not ok: return
	await _frames(90)
	var target := Target.new()
	target.name = "SourceFirearmProofTarget_" + id
	game.add_child(target)
	var hurtboxes: Node3D = target.call("get_hurtbox_rig")
	var torso := hurtboxes.call("get_region_area", &"TORSO") as Area3D
	if torso == null:
		_expect(false, "target has a real torso hurtbox")
		target.queue_free()
		return
	var camera := camera_rig.get("camera") as Camera3D
	var center := root.get_visible_rect().size * 0.5
	var lens_origin := camera.project_ray_origin(center)
	var direction := camera.project_ray_normal(center).normalized()
	var depth := maxf((player.global_position + Vector3.UP * 1.3 - lens_origin).dot(direction), 0.0)
	var desired := lens_origin + direction * (depth + 3.0)
	target.global_position = desired - (torso.global_position - target.global_position)
	hurtboxes.call("force_pose_update")
	await _frames(3)
	hurtboxes.call("force_pose_update")
	camera_rig.set("reticle_screen_normalized", Vector2(0.5, 0.5))
	camera_rig.call("_update_weapon_aim_point")
	camera_rig.call("_update_shot_validation")
	var ammo_before := int(weapon.get("rounds_in_magazine"))
	var health_before: float = target.current_health
	var signals_before := accepted_signals
	var tick_before := Engine.get_physics_frames()
	var result: Dictionary = weapon.call("request_fire")
	var tick_after := Engine.get_physics_frames()
	var projectiles: Array = result.get("projectiles", [])
	var profile: Dictionary = Contract.load_config(path)
	var expected_pellets := int(profile.get("ballistics", {}).get("pellet_count", 1))
	var source_policy := Policy.resolve(profile)
	if source_policy.has("combat"): expected_pellets = int(source_policy.combat.pellet_count)
	var expected_policy := "project_hitscan" if id == "assaultrifle_1" else Policy.POLICY_ID
	_expect(bool(result.get("fired", false)), id + " actual main request_fire accepted: " + str(result.get("reason", "")))
	_expect(tick_before == tick_after, id + " shot resolves in requesting tick")
	_expect(int(weapon.get("rounds_in_magazine")) == ammo_before - 1, id + " consumes one round")
	_expect(accepted_signals == signals_before + 1, id + " one authoritative shot signal")
	_expect(projectiles.size() == expected_pellets, id + " saved projectile count")
	if expected_policy == Policy.POLICY_ID:
		_expect(String(result.get("dispersion_distribution", "")) == "source_signed_square_axes_v1",
			id + " accepted main shot uses source dispersion distribution")
		_expect(target.source_health != null, id + " real target uses original six pools")
		_expect(String(result.get("damage_result", {}).get("damage_model", "")) == Policy.DAMAGE_MODEL,
			id + " accepted main hit bypasses legacy multipliers")
	_expect(target.current_health < health_before, id + " actual target damaged before request returns")
	var projectile_rows: Array[Dictionary] = []
	for projectile: Dictionary in projectiles:
		_expect(String(projectile.get("trajectory_policy", "")) == expected_policy,
			id + " accepted projectile records policy")
		var origin := Vector3(result.get("origin", Vector3.ZERO))
		var hit := Vector3(projectile.get("hit_pos", Vector3.ZERO))
		_expect(origin.is_finite() and hit.is_finite(), id + " finite shot endpoints")
		projectile_rows.append({"trajectory_policy": projectile.get("trajectory_policy", ""),
			"hit_distance_m": origin.distance_to(hit), "hit_region": String(projectile.get("hit_region", "")),
			"direction": _xyz(Vector3(projectile.get("direction", Vector3.ZERO))),
			"damage": projectile.get("damage", 0), "damage_result": projectile.get("damage_result", {})})
	var row := {"weapon_id": id, "config_sha256": FileAccess.get_sha256(path),
		"policy": weapon.get("ballistics").get("trajectory_policy").duplicate(true),
		"fired": result.get("fired", false), "reason": result.get("reason", ""),
		"dispersion_distribution": result.get("dispersion_distribution", ""),
		"rng_algorithm": result.get("rng_algorithm", ""),
		"target_source_pools": target.source_health.snapshot() if target.source_health != null else {},
		"tick_before": tick_before, "tick_after": tick_after,
		"ammo_before": ammo_before, "ammo_after": weapon.get("rounds_in_magazine"),
		"accepted_signal_count": accepted_signals - signals_before,
		"target_health_before": health_before, "target_health_after": target.current_health,
		"origin": _xyz(Vector3(result.get("origin", Vector3.ZERO))),
		"aim_center_direction": _xyz(Vector3(result.get("aim_center_direction", Vector3.ZERO))),
		"camera_aim_collider": camera_rig.get("aim_collider_name"),
		"projectiles": projectile_rows}
	shots.append(row)
	print("SOURCE_FIREARM_MAIN_SHOT ", id, " fired=", row.fired,
		" pellets=", projectiles.size(), " target_health=", row.target_health_after)
	if capture and DisplayServer.get_name() != "headless":
		await _frames(2)
		await RenderingServer.frame_post_draw
		var filename := output + "-" + id + ".png"
		_expect(root.get_texture().get_image().save_png(filename) == OK, "write " + filename)
		row["capture"] = filename
	target.queue_free()
	await _frames(3)


func _xyz(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _frames(count: int) -> void:
	for _frame in count:
		await physics_frame
		await process_frame


func _expect(condition: bool, label: String) -> void:
	if not condition: failures.append(label)


func _finish() -> void:
	var report := {"scene": "res://main.tscn", "project": ProjectSettings.globalize_path("res://"),
		"policy_sha256": FileAccess.get_sha256(Policy.PATH),
		"policy_script_sha256": FileAccess.get_sha256("res://scripts/weapons/source_firearm_policy.gd"),
		"ballistics_script_sha256": FileAccess.get_sha256("res://scripts/weapons/weapon_ballistics.gd"),
		"engine": Engine.get_version_info(), "display": DisplayServer.get_name(),
		"server_scope": "actual session configuration method; no network connection or remote packet test",
		"routing": census, "main_shots": shots, "failures": failures, "passed": failures.is_empty()}
	var file := FileAccess.open(output + ".json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	else: _expect(false, "cannot write report " + output + ".json")
	for failure in failures: push_error("SOURCE_FIREARM_MAIN_REGRESSION: " + failure)
	print("SOURCE_FIREARM_MAIN_REGRESSION ", "PASS" if failures.is_empty() else "FAIL",
		" routing=", census.size(), " main_shots=", shots.size(), " report=", output + ".json")
	if is_instance_valid(game): game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
