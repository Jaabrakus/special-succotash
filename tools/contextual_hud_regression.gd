extends SceneTree

const Card := preload("res://scripts/ui/socom_loadout_card_hud.gd")
const Reticle := preload("res://scripts/ui/socom_dynamic_reticle.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var card := Card.new()
	root.add_child(card)
	card.set_process(false)
	card.update_weapon_state("Vanguard 5.56", "PRIMARY", 30, 95, "auto", [], 3, 30)
	card.update_grenade_state({"frag": 2, "flash": 1, "smoke": 1}, "frag", false)
	card.update_health(100, 100)
	for selected in ["FRAG", "FLASH", "SMOKE"]:
		card.update_grenade_state({"frag": 2, "flash": 1, "smoke": 0}, selected, true)
		card.attention.advance(6.0)
		for kind in ["frag", "flash", "smoke"]:
			assert(card.grenade_is_selected(kind) == (kind == selected.to_lower()))
			var tint := card.grenade_tint(kind)
			assert((tint.b - tint.r > 0.4) == (kind == selected.to_lower()), "Only selected grenade is blue")
		assert(card.grenade_tint(selected.to_lower()).a == 1.0, "Equipped selection stays bright, including zero stock")
	card.update_grenade_state({"frag": 2, "flash": 1, "smoke": 1}, "frag", false)
	card.attention.glance_elapsed = 0.0
	card.attention.advance(6.0)
	for i in 120:
		card.update_weapon_state("Vanguard 5.56", "PRIMARY", 30, 95, "auto", [], 3, 30)
		card.update_grenade_state({"frag": 2, "flash": 1, "smoke": 1}, "frag", false)
		card.update_health(100, 100)
	assert(is_equal_approx(card.attention.alpha("weapon"), 0.16), "Unchanged snapshots must not retrigger")
	assert(card.grenade_tint("frag").a > card.grenade_tint("flash").a)
	card.update_weapon_state("Vanguard 5.56", "PRIMARY", 29, 95, "auto", [], 3, 30)
	card.update_health(70, 100)
	assert(card.attention.alpha("weapon") == 1.0 and card.attention.alpha("health") == 1.0)
	assert(is_equal_approx(card.attention.alpha("throwable"), 0.16), "Independent channels")
	card.attention.advance(6.0)
	card.update_grenade_state({"frag": 1, "flash": 1, "smoke": 1}, "frag", false)
	assert(card.attention.alpha("throwable") == 1.0)
	assert(is_equal_approx(card.attention.alpha("weapon"), 0.16))
	card.attention.advance(8.0)
	for channel in ["weapon", "health", "throwable"]:
		assert(card.attention.alpha(channel) == 1.0, "Periodic full glance")
	card.attention.advance(5.0)
	assert(card.attention.alpha("health", true) == 1.0, "Critical health stays visible")
	assert(card.rounds_in_magazine == 29 and card.reserve_rounds == 95)
	var reticle := Reticle.new()
	root.add_child(reticle)
	reticle.apply_profile({"weapon_category": "Assault Rifles", "socom2_source_name": "M4A1"})
	reticle.screen_center_override = Vector2(400, 240)
	assert(reticle.get_authoritative_center().is_equal_approx(Vector2(400, 240)))
	var player := Node3D.new()
	root.add_child(player)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 2, 5)
	camera.look_at(Vector3(0, 1.4, 0))
	camera.make_current()
	card.bind_player(player)
	card._update_floating_position(1.0)
	assert(card._anchor_valid and card._floating_initialized)
	var first_position := card.position
	player.position.x = 0.5
	card._update_floating_position(1.0)
	assert(card.position.x > first_position.x, "Card follows local player, not viewport corner")
	assert(card.position.x < camera.unproject_position(player.position + Vector3.UP * 1.48).x)
	assert(card._actions_position.x > camera.unproject_position(player.position + Vector3.UP * 1.48).x, "Outgoing actions are right of player")
	card.update_weapon_state("Vanguard", "PRIMARY", 0, 0)
	card.attention.advance(6.0)
	assert(card.ammo_warning() == "NO AMMO")
	assert(card.attention.alpha("weapon", not card.ammo_warning().is_empty()) == 1.0)
	card.update_weapon_state("Vanguard", "PRIMARY", 0, 30)
	assert(card.ammo_warning() == "EMPTY — RELOAD")
	card.update_weapon_state("Vanguard", "PRIMARY", 10, 0)
	assert(card.ammo_warning().is_empty(), "Loaded rounds still usable without reserves")
	player.position = Vector3(1000, 0, 0)
	card._update_floating_position(1.0)
	assert(card.position.x + card.size.x * card.scale.x <= root.get_visible_rect().size.x)
	player.position = Vector3(0, 2, 10)
	card._update_floating_position(1.0)
	assert(not card._anchor_valid, "Behind-camera card is not drawn")
	player.position = Vector3.ZERO
	card.visible = false
	card._update_floating_position(1.0)
	assert(not card.visible, "Tracking must not override HUD hide")
	card.visible = true
	if "--render" in OS.get_cmdline_user_args():
		root.size = Vector2i(960, 540)
		card._update_floating_position(1.0)
		card.attention.reveal("weapon")
		card.attention.reveal("health")
		card.attention.reveal("throwable")
		card.queue_redraw()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/contextual-hud-active.png")
		card.attention.advance(5.0)
		card.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/contextual-hud-idle.png")
	print("CONTEXTUAL_HUD_PASS: snapshot dedupe, simultaneous events, fades, glance, critical visibility, aim center")
	card.free()
	reticle.free()
	player.free()
	camera.free()
	quit()
