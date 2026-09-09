extends SceneTree

const Ballistics := preload("res://scripts/weapons/weapon_ballistics.gd")
const Envelope := preload("res://scripts/weapons/reticle_bloom_envelope.gd")
const Controller := preload("res://scripts/weapons/socom_weapon_controller.gd")
const Server := preload("res://scripts/network/socom_multiplayer_rounds.gd")
const Reticle := preload("res://scripts/ui/socom_dynamic_reticle.gd")
const Contract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const Main := preload("res://main.tscn")
var failures: Array[String] = []
var world: Node3D
var directions_checked := 0
var profiles_checked := 0

func _initialize() -> void:
	_run.call_deferred()

func expect(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	await physics_frame
	var server := Server.new()
	for file in DirAccess.get_files_at("res://config/weapons"):
		if not file.ends_with(".json"):
			continue
		var config := Contract.load_config("res://config/weapons/" + file)
		if not Envelope.load_settings().custom.categories.has(config.get("category", "")):
			continue
		var id := String(config.get("weapon_id", file))
		var local := Ballistics.new()
		var remote := Ballistics.new()
		world.add_child(local)
		world.add_child(remote)
		local.set_process(false)
		remote.set_process(false)
		var controller := Controller.new()
		controller.ballistics = local
		controller._apply_weapon_config(config)
		server._apply_ballistics_profile(remote, config)
		profiles_checked += 1
		expect(local.bloom_profile == remote.bloom_profile, id + " local/server shared profile")
		var hud := Reticle.new()
		root.add_child(hud)
		hud.set_process(false)
		hud.apply_profile(controller.reticle_profile)
		hud.bind_bloom_envelope(controller)
		for stance in [&"STANDING", &"CROUCHED", &"PRONE"]:
			local._process(10.0)
			remote._process(10.0)
			for index in 18:
				var motion := float(index % 3) * 0.5
				var airborne: bool = index == 16
				var visual := clampf(float(index) / 8.0, 0.0, 1.0)
				local.visual_bloom_input = visual
				remote.visual_bloom_input = visual
				local.update_spread_state(stance, motion, airborne)
				remote.update_spread_state(stance, motion, airborne)
				var gap_before := local.bloom_gap_px
				var limit_before := local.get_bloom_tangent_limit()
				var dispersion := 0.0 if index == 0 else 1.0
				var seed := 21000 + index
				var a := local.try_fire_direction(Vector3.ZERO, Vector3.FORWARD,
					world.get_world_3d().direct_space_state, [], seed, stance, motion, airborne, dispersion)
				var b := remote.try_fire_direction(Vector3.ZERO, Vector3.FORWARD,
					world.get_world_3d().direct_space_state, [], seed, stance, motion, airborne, dispersion)
				expect(a.fired and b.fired, id + " cadence accepted")
				expect(is_equal_approx(a.bloom_gap_px, gap_before), "shot uses pre-existing gap, not instant target")
				expect(a.cone_tangent_radius <= limit_before + 0.000001, "combined cone capped before sampling")
				expect(is_equal_approx(a.cone_tangent_radius, b.cone_tangent_radius), "server and local identical cap")
				for n in a.projectiles.size():
					var direction: Vector3 = a.projectiles[n].direction
					var radial := Vector2(direction.x, direction.y).length() / -direction.z
					expect(radial <= limit_before + 0.000001, id + " every projectile inside bloom")
					expect(direction.is_equal_approx(b.projectiles[n].direction), "same seed same capped pattern")
					if index == 0 and local.pellet_count == 1:
						expect(direction.is_equal_approx(Vector3.FORWARD), "settled first bullet remains centered")
					directions_checked += 1
				if index == 0 and local.pellet_count > 1:
					expect(a.cone_tangent_radius > 0.0, "settled shotgun keeps pellet dispersion")
				hud._process(0.2)
				expect(is_equal_approx(hud.current_gap, local.bloom_gap_px), "HUD has no second smoothing clock")
				var geometry := hud.get_custom_reference_geometry()
				var width := float(geometry.width) + float(Envelope.load_settings().custom.outline_extra_px)
				expect(is_equal_approx(Envelope.inner_radius(geometry.strokes, width),
					Envelope.radius_px(local.bloom_profile, local.bloom_gap_px)), "cap uses actual marks including outline")
				var rejected := local.try_fire_direction(Vector3.ZERO, Vector3.FORWARD,
					world.get_world_3d().direct_space_state)
				expect(not rejected.fired and is_equal_approx(local.bloom_gap_px, gap_before), "rejected click cannot change gap")
				local.release_trigger()
				local._process(local.fire_interval + 0.0001)
				remote._process(remote.fire_interval + 0.0001)
		local.visual_bloom_input = 0.0
		local.update_spread_state(&"PRONE", 0.0, false)
		var open_gap := local.bloom_gap_px
		local._process(10.0)
		expect(local.bloom_gap_px < open_gap, "pause recovers bloom")
		var count := local.continuous_shot_count
		var age := local.seconds_since_last_shot
		local.preview_next_shot_cone(&"PRONE", 0.0, false, 1.0)
		expect(local.continuous_shot_count == count and local.seconds_since_last_shot == age, "preview is read only")
		hud.free()
		controller.free()
		local.free()
		remote.free()
	server.free()
	check_projection()
	world.free()
	await check_main()
	print("BLOOM_SHOT_ENVELOPE_REGRESSION ", "PASS" if failures.is_empty() else "FAIL",
		" profiles=", profiles_checked, " directions=", directions_checked, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func check_projection() -> void:
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0.0, 1.8, 2.2)
	var muzzle := Vector3(0.4, 1.35, 0.0)
	for fov in [42.0, 60.0, 68.0, 74.0]:
		camera.fov = fov
		for aspect in [Camera3D.KEEP_HEIGHT, Camera3D.KEEP_WIDTH]:
			camera.keep_aspect = aspect
			for target in [Vector3(0, 1.35, -3), Vector3(0, 1.35, -12), Vector3(15, 8, -40)]:
				var tangent := 0.055
				var bound := Envelope.projected_radius(camera, muzzle, target, tangent)
				var center := camera.unproject_position(target)
				var basis := Basis.looking_at(muzzle.direction_to(target))
				for index in 720:
					var angle := float(index) * TAU / 720.0
					var edge: Vector3 = target + (basis.x * cos(angle) + basis.y * sin(angle)) * muzzle.distance_to(target) * tangent
					var actual := center.distance_to(camera.unproject_position(edge))
					expect(actual <= bound + 0.002, "analytic projection bounds complete off-center disk")
					directions_checked += 1
	camera.free()

func check_main() -> void:
	ProjectSettings.set_setting("socom/session/public_training", true)
	var game := Main.instantiate()
	root.add_child(game)
	current_scene = game
	for index in 30:
		await physics_frame
		await process_frame
	for id in ["m4a1", "mark_23", "870"]:
		expect(game.weapon_controller.apply_authorized_weapon_pickup("res://config/weapons/" + id + ".json"), "main equip " + id)
		for index in 4:
			await physics_frame
			await process_frame
		var weapon = game.weapon_controller
		var model = weapon.ballistics
		model._process(10.0)
		var gap := float(model.bloom_gap_px)
		var shot: Dictionary = weapon.request_fire()
		expect(shot.get("fired", false), "canonical main fires " + id)
		expect(is_equal_approx(float(shot.get("bloom_gap_px", -1.0)), gap), "main firing consumes shared bloom " + id)
		expect(game.dynamic_reticle.bloom_weapon == weapon, "canonical HUD bound to actual weapon")
		var marks: Dictionary = game.dynamic_reticle.get_custom_reference_geometry()
		var width := float(marks.width) + float(Envelope.load_settings().custom.outline_extra_px)
		var drawn_radius := Envelope.inner_radius(marks.strokes, width)
		var muzzle: Vector3 = shot.get("origin", weapon.mannequin.get_active_muzzle_marker().global_position)
		var target: Vector3 = weapon.camera_rig.weapon_aim_point
		var projected := Envelope.projected_radius(weapon.camera_rig.camera, muzzle, target,
			float(shot.get("cone_tangent_radius", 0.0)))
		expect(projected <= drawn_radius + 0.01, "canonical aimed-depth pattern fits drawn bloom " + id)
		if OS.get_cmdline_user_args().has("--render"):
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png("/private/tmp/bloom-envelope-main-" + id + ".png") == OK, "main render " + id)
	game.queue_free()
	await process_frame
