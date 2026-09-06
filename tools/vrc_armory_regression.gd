extends SceneTree

const Scene := preload("res://main.tscn")
const Slice := preload("res://multiplayer_slice.tscn")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# Exercise the actual editor serializer without overwriting a user's profile.
	var lab = load("res://scripts/labs/gun_calibration_lab.gd").new()
	lab.reticle_vrc_enabled = true
	lab.reticle_vrc_delay = 0.31
	lab.reticle_vrc_return_speed = 123.0
	var repository = load("res://scripts/labs/gunsmith/gunsmith_weapon_profile_repository.gd")
	var prepared: Dictionary = repository.prepare_profile_for_save({"reticle": lab._current_reticle_profile()}, {})
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(prepared))
	var resolved: Dictionary = load("res://scripts/camera/reticle_climb_profile.gd").resolve(decoded.reticle)
	_expect(resolved.enabled and is_equal_approx(resolved.delay, 0.31) and resolved.return_speed == 123.0, "Gunsmith VRC values survive saved JSON and runtime resolution")
	lab.free()
	ProjectSettings.set_setting("socom/session/public_training", true)
	var game = Scene.instantiate()
	root.add_child(game)
	current_scene = game
	for frame in 30:
		await process_frame
	var weapon = game.weapon_controller
	var rig = game.camera_rig
	game.buy_menu_runtime._handle_purchase("m4a1")
	weapon.rounds_in_magazine = 11
	game.buy_menu_runtime._handle_purchase("mark_23")
	weapon.rounds_in_magazine = 5
	_expect(weapon.carried_loadout == {"primary": "m4a1", "secondary": "mark_23"}, "one primary plus pistol")
	_expect(game.grenade_runtime.equip_firearm_slot("primary"), "primary switch")
	_expect(weapon.rounds_in_magazine == 11, "primary ammo retained")
	_expect(game.grenade_runtime.equip_firearm_slot("secondary"), "pistol switch")
	_expect(weapon.rounds_in_magazine == 5, "pistol ammo retained")
	game.buy_menu_runtime._handle_purchase("ak-47")
	_expect(weapon.carried_loadout == {"primary": "ak-47", "secondary": "mark_23"}, "primary replacement preserves pistol")
	_expect(not weapon.equip_carried_slot("third"), "no third slot")
	game.buy_menu_runtime._handle_purchase("m4a1")
	game.buy_menu_runtime.open_menu()
	game.buy_menu_runtime.buy_menu._selected_weapon_id = "m4a1"
	game.buy_menu_runtime.buy_menu._refresh_detail()
	var detail: String = game.buy_menu_runtime.buy_menu._detail_body.get_parsed_text()
	_expect(not detail.to_lower().contains("socom") and detail.contains("RETICLE CLIMB"), "unbranded armory shows saved VRC")
	game.buy_menu_runtime.close_menu()
	rig.set_physics_process(false)
	rig._advance_functional_aim_climb(5.0)
	var basis: Basis = rig.camera.global_basis
	var yaw: float = rig.aim_yaw
	var pitch: float = rig.aim_pitch
	for shot in 10:
		rig.notify_functional_aim_climb()
	_expect(is_equal_approx(rig.vrc_height_px, 45.0), "M4 accumulated cap")
	rig.input_presenter._update_reticle_position(0.0)
	rig._update_weapon_aim_point()
	var pixel: Vector2 = rig.reticle_screen_normalized * root.get_visible_rect().size
	var projected: Vector2 = rig.camera.unproject_position(rig.weapon_aim_point)
	_expect(pixel.distance_to(projected) < 0.1, "bullet target projects to climbed reticle")
	var packet: Dictionary = rig.build_local_aim_intent()
	_expect(not packet.is_empty(), "climbed aim produces network intent")
	var packet_target: Vector3 = Vector3(packet.reported_muzzle_origin) + Vector3(packet.direction) * float(packet.convergence_distance)
	_expect(rig.camera.unproject_position(packet_target).distance_to(pixel) < 0.1, "replicated bullet aim converges at displayed reticle")
	game.dynamic_reticle.apply_profile(weapon.reticle_profile)
	game.dynamic_reticle.screen_center_override = pixel
	game.dynamic_reticle.notify_shot()
	_expect(game.dynamic_reticle.get_visual_center().distance_to(pixel) < 0.1, "no independent cosmetic aim mismatch")
	_expect(rig.camera.global_basis.is_equal_approx(basis) and rig.aim_yaw == yaw and rig.aim_pitch == pitch, "climb does not rotate camera")
	rig._advance_functional_aim_climb(0.1)
	_expect(rig.vrc_height_px == 45.0, "hold before return")
	rig._advance_functional_aim_climb(1.0)
	_expect(rig.vrc_height_px == 0.0, "return to base")
	rig.notify_functional_aim_climb()
	game.grenade_runtime.equip_firearm_slot("secondary")
	_expect(rig.vrc_height_px == 0.0 and rig.vrc_profile.cap == 40.0, "equip resets to pistol cap")
	if OS.get_cmdline_user_args().has("--render"):
		game.buy_menu_runtime.open_menu()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/vrc-armory.png")
	game.queue_free()
	await process_frame
	var session = Slice.instantiate()
	root.add_child(session)
	await process_frame
	# Shared UI adapter receives the same camera-owned aim point.
	session.queue_free()
	await process_frame
	print("VRC_ARMORY_REGRESSION ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("VRC_ARMORY FAIL " + label)
