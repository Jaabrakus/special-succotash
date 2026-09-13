extends SceneTree

const Envelope := preload("res://scripts/weapons/reticle_bloom_envelope.gd")
const Ballistics := preload("res://scripts/weapons/weapon_ballistics.gd")
const Card := preload("res://scripts/ui/socom_loadout_card_hud.gd")

class StanceActor extends Node3D:
	var stance := &"STANDING"
	func get_posture_name() -> StringName:
		return stance

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var profile := {"base_gap_px": 10.0, "max_gap_px": 50.0, "weapon_category": "Assault Rifles"}
	assert(is_equal_approx(Envelope.gap_for(profile, 1, &"STANDING", 0), 42))
	assert(is_equal_approx(Envelope.gap_for(profile, 0, &"STANDING", 0), 10))
	assert(is_equal_approx(Envelope.gap_for(profile, 1, &"STANDING", 1), 50))
	assert(is_equal_approx(Envelope.gap_for(profile, 1, &"STANDING", 0, true), 50))
	assert(is_equal_approx(Envelope.gap_for(profile, 1, &"CROUCHED", 0), 40))
	assert(is_equal_approx(Envelope.gap_for(profile, 1, &"PRONE", 0), 32))
	var guns: Array[Node] = []
	for i in 2:
		var gun := Ballistics.new()
		gun.configure_bloom_envelope({"reticle": profile, "category": "Assault Rifles"})
		gun.current_movement_speed_norm = 0
		gun.visual_bloom_input = 1.0
		gun.bloom_gap_px = 50
		gun._process(1.0)
		assert(is_equal_approx(gun.bloom_gap_px, 42))
		guns.append(gun)
	assert(is_equal_approx(guns[0].get_bloom_tangent_limit(), guns[1].get_bloom_tangent_limit()))
	for gun in guns:
		gun.free()
	root.size = Vector2i(1280, 900)
	var player := StanceActor.new()
	root.add_child(player)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 2, 5)
	camera.look_at(Vector3(0, 1, 0))
	camera.make_current()
	var card := Card.new()
	root.add_child(card)
	card.set_process(false)
	card.bind_player(player)
	var previous_y := -INF
	for stance in [&"STANDING", &"CROUCHED", &"PRONE"]:
		player.stance = stance
		card._update_floating_position(1.0)
		assert(card.position.y > previous_y + 10, "HUD lowers with each stance, even without collider updates")
		assert(card.position.y + card.size.y * card.scale.y <= root.size.y)
		previous_y = card.position.y
	assert(int(card.attention.profile.health_font_size) > 12)
	assert(int(card.attention.profile.ammo_font_size) > 15)
	assert(float(card.attention.profile.health_radius) > 39)
	card.free()
	player.free()
	camera.free()
	if "--render" in OS.get_cmdline_user_args():
		ProjectSettings.set_setting("socom/session/public_training", true)
		ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
		change_scene_to_file("res://main.tscn")
		await scene_changed
		await create_timer(0.3).timeout
		var actor = current_scene.get_node("Player")
		var hud = current_scene.gameplay_hud.loadout_card_hud
		for stance in [0, 1, 2]:
			assert(actor._try_set_posture(stance))
			for frame in 45:
				await process_frame
			hud.attention.reveal("health")
			hud.attention.reveal("weapon")
			hud.attention.reveal("throwable")
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/private/tmp/stance-hud-%d.png" % stance)
	print("STANCE_HUD_BLOOM_PASS: stationary cap, moving/airborne and stance caps, matching ballistics, stance tracking and larger health/ammo")
	quit()
