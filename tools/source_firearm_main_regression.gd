extends SceneTree

## New main scene only; never reloads or drives the user's running game.
const Contract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const Ballistics := preload("res://scripts/weapons/weapon_ballistics.gd")
const Policy := preload("res://scripts/weapons/source_firearm_policy.gd")
const Target := preload("res://scripts/combat/lab_leak_target_dummy.gd")
const SourceDamage := preload("res://scripts/combat/source_firearm_damage.gd")
const MapRuntime := preload("res://scripts/maps/socom_map_runtime.gd")
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const IMPORTED_PROP := "res://assets/environment/tactical_courtyard_kit/wood_supply_crate_1m.glb"
var failures: Array[String] = []
var census: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var material_shots: Array[Dictionary] = []
var metadata_cases: Array[Dictionary] = []
var checks := 0
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
	_metadata_contract()
	_install_platform()
	camera_rig.call("set_aim_angles", 0.0, 0.0, true)
	camera_rig.call("reset_camera_to_target")
	await _frames(90)
	for id in ["m4a1", "mark_23", "870", "assaultrifle_1"]:
		await _live_shot(id)
	for material_name in ["WOOD_THIN", "UNKNOWN"]:
		await _material_shot(material_name)
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
		_expect(local.get("source_materials") == server_ballistics.source_materials,
			id + " main/server material coefficient parity")
		_expect(local.get("source_materials") == (Policy.material_coefficients() if profiles.has(id) else {}),
			id + " source material selection and unsupported-profile clearing")
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
			"material_coefficients": local.get("source_materials").duplicate(true),
			"numeric_settings": values})
	server_ballistics.free()
	session.free()


func _metadata_contract() -> void:
	# Serialize the document, then use the same normalizer/builders as saved maps.
	# These temporary props are far from the firing lane and never saved to the map.
	for mode in ["primitive", "box", "detailed_mesh"]:
		for tag_case in ["explicit", "absent", "malformed"]:
			var properties: Dictionary = {}
			if tag_case == "explicit": properties.source_material = "WOOD_THIN"
			if tag_case == "malformed": properties.source_material = 0.25
			if mode != "primitive":
				properties.asset_path = IMPORTED_PROP
				properties.collision_mode = mode
			var object := {"id": "source_material_metadata_probe", "name": "Material metadata probe",
				"type": "wall" if mode == "primitive" else "imported_asset",
				"position": {"x": 530.0, "y": 1.0, "z": 530.0},
				"size": {"x": 1.0, "y": 1.0, "z": 1.0}, "properties": properties}
			var document := MapDocument.new_document("Temporary material contract proof")
			document.objects = [object]
			var round_trip: Dictionary = JSON.parse_string(JSON.stringify(document))
			var built := MapRuntime.build_into(game, round_trip, false)
			var label: String = mode + "/" + tag_case
			_expect(built != null, label + " saved document builds")
			if built == null: continue
			var collider_rows: Array[Dictionary] = []
			for collider: Node in built.find_children("*", "StaticBody3D", true, false):
				var has_collision := false
				for child: Node in collider.get_children():
					if child is CollisionShape3D and child.shape != null: has_collision = true
				if not has_collision: continue
				var expected: Variant = "WOOD_THIN" if tag_case == "explicit" else null
				var actual: Variant = collider.get_meta("source_material") if collider.has_meta("source_material") else null
				_expect(actual == expected, label + " source_material on " + String(collider.name))
				collider_rows.append({"node": String(built.get_path_to(collider)), "source_material": actual})
			_expect(not collider_rows.is_empty(), label + " tests actual physical collision owners")
			metadata_cases.append({"mode": mode, "tag_case": tag_case, "colliders": collider_rows})
			built.free()


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
	if expected_policy == Policy.POLICY_ID:
		row["receiver_replay"] = _verify_source_impacts(result, [target], id)
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


func _material_shot(material_name: String) -> void:
	var label := "M4 cover " + material_name
	_expect(bool(weapon.call("apply_authorized_weapon_pickup", "res://config/weapons/m4a1.json")),
		label + " authorized equip")
	camera_rig.call("set_aim_angles", 0.0, 0.0, true)
	await _frames(90)
	var camera := camera_rig.get("camera") as Camera3D
	var center := root.get_visible_rect().size * 0.5
	var lens := camera.project_ray_origin(center)
	var forward := camera.project_ray_normal(center).normalized()
	var player_depth := maxf((player.global_position + Vector3.UP * 1.3 - lens).dot(forward), 0.0)
	var cover_center := lens + forward * (player_depth + 2.0)
	var cover := MapRuntime.build_object({"id": "source_material_cover", "name": material_name,
		"type": "wall", "position": MapDocument.vector_to_data(cover_center),
		"size": {"x": 2.0, "y": 2.0, "z": 0.10},
		"properties": {"source_material": material_name}}, false)
	game.add_child(cover)
	_expect(cover.get_meta("source_material", "") == material_name, label + " real map collider tag")
	await _frames(3)
	camera_rig.set("reticle_screen_normalized", Vector2(0.5, 0.5))
	camera_rig.call("_update_weapon_aim_point")
	camera_rig.call("_update_shot_validation")
	var mannequin: Node = weapon.get("mannequin")
	var muzzle: Vector3 = mannequin.call("get_active_muzzle_position")
	var aim: Vector3 = camera_rig.call("get_shared_aim_target")
	var shot_direction := muzzle.direction_to(aim)
	var receivers: Array = []
	for index in 2:
		var target := Target.new()
		target.name = "MaterialProofTarget_%s_%d" % [material_name, index]
		game.add_child(target)
		var rig: Node3D = target.call("get_hurtbox_rig")
		var torso := rig.call("get_region_area", &"TORSO") as Area3D
		_expect(torso != null, label + " real target torso")
		if torso == null:
			target.queue_free()
			continue
		# Only fixture placement changes. The controller still derives and validates
		# its own aim and muzzle; no shot payload, spread or damage is overridden.
		target.global_position = muzzle + shot_direction * (4.0 + index * 1.5) \
			- (torso.global_position - target.global_position)
		rig.call("force_pose_update")
		receivers.append(target)
	await _frames(3)
	for target: Node3D in receivers: target.call("get_hurtbox_rig").call("force_pose_update")
	camera_rig.call("_update_weapon_aim_point")
	camera_rig.call("_update_shot_validation")
	var ammo_before := int(weapon.get("rounds_in_magazine"))
	var signals_before := accepted_signals
	var result: Dictionary = weapon.call("request_fire")
	_expect(bool(result.get("fired", false)), label + " actual request_fire: " + str(result.get("reason", "")))
	_expect(int(weapon.get("rounds_in_magazine")) == ammo_before - 1, label + " consumes one round")
	_expect(accepted_signals == signals_before + 1, label + " one accepted shot signal")
	var projectiles: Array = result.get("projectiles", [])
	_expect(projectiles.size() == 1, label + " one M4 projectile")
	var contact_rows: Array[Dictionary] = []
	if not projectiles.is_empty():
		var contacts: Array = projectiles[0].get("penetrations", [])
		_expect(not contacts.is_empty(), label + " physically hits cover")
		if not contacts.is_empty():
			_expect(contacts[0].collider == cover, label + " cover is first physical contact")
			_expect(contacts[0].source_material == material_name, label + " explicit coefficient selected")
		var previous_distance := 0.0
		for contact: Dictionary in contacts:
			var distance := Vector3(result.origin).distance_to(contact.entry_pos)
			_expect(distance > previous_distance, label + " contacts ordered from original muzzle")
			previous_distance = distance
			contact_rows.append({"source_material": contact.source_material,
				"receiver": String(contact.receiver.name) if is_instance_valid(contact.receiver) else "",
				"distance_m": distance, "range_limit": contact.range_limit, "range_after": contact.range_after,
				"coefficient": contact.coefficient, "continues": contact.continues})
		var impacts: Array = projectiles[0].get("damage_impacts", [])
		_expect(impacts.size() == (2 if material_name == "WOOD_THIN" else 0),
			label + " two collateral receivers only through explicitly thin cover")
		if material_name == "WOOD_THIN" and impacts.size() == 2 and receivers.size() == 2:
			for index in 2:
				_expect(impacts[index].hit_collider.call("get_damage_receiver") == receivers[index],
					label + " ordered receiver " + str(index))
	var replay := _verify_source_impacts(result, receivers, label)
	var hp: Array = []
	for target: Node3D in receivers:
		var health := float(target.get("current_health"))
		hp.append(health)
		_expect(health < float(target.get("max_health")) if material_name == "WOOD_THIN" else \
			health == float(target.get("max_health")), label + " actual receiver damage/block")
	var row := {"material": material_name, "fired": result.get("fired", false),
		"reason": result.get("reason", ""), "contacts": contact_rows, "receiver_health": hp,
		"receiver_replay": replay, "camera_aim_collider": camera_rig.get("aim_collider_name")}
	material_shots.append(row)
	print("SOURCE_FIREARM_MAIN_MATERIAL ", material_name, " health=", hp, " contacts=", contact_rows.size())
	if capture and DisplayServer.get_name() != "headless":
		await _frames(2)
		await RenderingServer.frame_post_draw
		var filename := output + "-material-" + material_name + ".png"
		_expect(root.get_texture().get_image().save_png(filename) == OK, "write " + filename)
		row["capture"] = filename
	for target: Node3D in receivers: target.queue_free()
	cover.queue_free()
	await _frames(3)


func _verify_source_impacts(result: Dictionary, receivers: Array, label: String) -> Array[Dictionary]:
	var replays: Dictionary = {}
	var rows: Array[Dictionary] = []
	var pellet_index := 0
	for projectile: Dictionary in result.get("projectiles", []):
		var seen: Dictionary = {}
		for impact: Dictionary in projectile.get("damage_impacts", []):
			var collider: Object = impact.get("hit_collider")
			_expect(is_instance_valid(collider) and collider.has_method("get_damage_receiver"),
				label + " anatomical impact has receiver")
			if not is_instance_valid(collider) or not collider.has_method("get_damage_receiver"): continue
			var receiver: Node3D = collider.call("get_damage_receiver")
			var id := receiver.get_instance_id()
			_expect(not seen.has(id), label + " receiver appears once in pellet " + str(pellet_index))
			seen[id] = true
			if receiver not in receivers: continue
			if not replays.has(id):
				var replay := SourceDamage.new()
				_expect(replay.initialize(Policy.multiplayer_defaults()), label + " original MP pool fixture")
				replays[id] = replay
			var source: Dictionary = impact.source_combat
			var distance := Vector3(result.origin).distance_to(impact.hit_pos)
			_expect(is_equal_approx(float(source.distance_m), distance), label + " global muzzle damage distance")
			var region: StringName = collider.call("get_hit_region")
			var expected: Dictionary = replays[id].apply_projectile(source.impact_damage, source.damage_modifier,
				source.piercing, distance, source.effective_range_m, source.maximum_range_m, Policy.source_region(region))
			var actual: Dictionary = impact.get("damage_result", {})
			_expect(bool(actual.get("accepted", false)) == bool(expected.get("accepted", false)),
				label + " receiver acceptance matches source pools")
			if bool(expected.get("accepted", false)):
				_expect(String(actual.get("damage_model", "")) == Policy.DAMAGE_MODEL, label + " source damage owner")
				for field in ["source_damage", "hp_damage", "armor_damage", "region_damage", "health_ratio"]:
					_expect(actual.get(field) == expected.get(field), label + " no legacy/cover multiplier: " + field)
			rows.append({"pellet": pellet_index, "receiver": String(receiver.name), "region": String(region),
				"distance_m": distance, "expected_source_result": expected, "actual_result": actual})
		pellet_index += 1
	for receiver: Node3D in receivers:
		var source_health: RefCounted = receiver.get("source_health")
		if replays.has(receiver.get_instance_id()):
			var expected: RefCounted = replays[receiver.get_instance_id()]
			_expect(source_health != null, label + " actual source health allocated")
			if source_health != null:
				_expect(source_health.call("snapshot") == expected.call("snapshot"), label + " exact final six health/armor pools")
			_expect(is_equal_approx(float(receiver.get("current_health")),
				float(receiver.get("max_health")) * float(expected.call("weighted_health_ratio"))), label + " visible health matches pools")
		else:
			_expect(source_health == null, label + " blocked/unhit receiver has no damage state mutation")
	return rows


func _xyz(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _frames(count: int) -> void:
	for _frame in count:
		await physics_frame
		await process_frame


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)


func _finish() -> void:
	_expect(census.size() == 33, "all profile comparisons completed")
	_expect(shots.size() == 4, "all four actual main firearm cases completed")
	_expect(material_shots.size() == 2, "both actual main cover cases completed")
	_expect(metadata_cases.size() == 9, "all saved-map metadata cases completed")
	var report := {"scene": "res://main.tscn", "project": ProjectSettings.globalize_path("res://"),
		"policy_sha256": FileAccess.get_sha256(Policy.PATH),
		"policy_script_sha256": FileAccess.get_sha256("res://scripts/weapons/source_firearm_policy.gd"),
		"ballistics_script_sha256": FileAccess.get_sha256("res://scripts/weapons/weapon_ballistics.gd"),
		"source_trace_sha256": FileAccess.get_sha256("res://scripts/combat/source_firearm_trace.gd"),
		"map_runtime_sha256": FileAccess.get_sha256("res://scripts/maps/socom_map_runtime.gd"),
		"map_geometry_sha256": FileAccess.get_sha256("res://scripts/maps/socom_map_geometry.gd"),
		"map_imported_builder_sha256": FileAccess.get_sha256("res://scripts/maps/socom_imported_map_asset_builder.gd"),
		"regression_sha256": FileAccess.get_sha256("res://tools/source_firearm_main_regression.gd"),
		"engine": Engine.get_version_info(), "display": DisplayServer.get_name(),
		"server_scope": "actual session configuration method; no network connection or remote packet test",
		"routing": census, "main_shots": shots, "material_shots": material_shots,
		"map_metadata_cases": metadata_cases, "checks": checks, "failures": failures, "passed": failures.is_empty()}
	var file := FileAccess.open(output + ".json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	else: _expect(false, "cannot write report " + output + ".json")
	for failure in failures: push_error("SOURCE_FIREARM_MAIN_REGRESSION: " + failure)
	print("SOURCE_FIREARM_MAIN_REGRESSION ", "PASS" if failures.is_empty() else "FAIL",
		" checks=", checks, " routing=", census.size(), " main_shots=", shots.size(),
		" material_shots=", material_shots.size(), " metadata_cases=", metadata_cases.size(), " report=", output + ".json")
	if is_instance_valid(game): game.queue_free()
	await create_timer(0.15).timeout # Let the audio thread release queued playback resources.
	quit(0 if failures.is_empty() else 1)
