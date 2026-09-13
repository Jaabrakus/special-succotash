extends "res://tools/map_jump_ledge_regression.gd"

var fixture: StaticBody3D
var fixture_shape: BoxShape3D
var origin := Vector3(600,0,600)

func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle",false)
	ProjectSettings.set_setting("socom/session/selected_map_document",load("res://scripts/maps/socom_map_document.gd").load_path("res://config/maps/current_map.json"))
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	for frame in 60:
		await physics_frame
		await process_frame
	player = world.get_node("Player")
	player.set_local_input_enabled(false)
	world.get_node("WeaponController").set_input_enabled(false)
	_box("HangProofFloor",Vector3(30,.2,30),origin+Vector3(0,-.1,0))
	fixture = _box("FiniteGripBeam",Vector3(4,.18,.22),origin+Vector3(0,2.51,0))
	fixture_shape = (fixture.get_child(0) as CollisionShape3D).shape
	direction = Vector3.FORWARD
	await _real_jump()
	_expect(player.traversal.is_hanging(),"real jump catches finite grip without standing footprint")
	for frame in 50: await _step()
	_expect(player.traversal.is_hanging() and not bool(player.traversal.state_machine.context.get("can_pull_up",true)),"stable hang explicitly has no pull-up")
	_expect(player.get_traversal_presentation().get("slot") == "hang_free","no wall below grip selects free hang")
	await create_timer(0.0).timeout
	var driver := player.get_node("Mannequin/ProductionAnimation")
	print("FREE_HANG_CONTACT errors_m=",driver.traversal_hand_contact.errors_m," evaluated_weights=",driver.traversal_hand_contact.evaluated_hand_weights," clip=",driver.current_clip)
	var anchor_before: Vector3 = player.traversal.state_machine.context.get("anchor",Vector3.ZERO)
	for frame in 20: await _step(false,false,false,0,false,1)
	_expect(Vector3(player.traversal.state_machine.context.get("anchor",Vector3.ZERO)).x > anchor_before.x+.1,"grip-only edge allows safe shimmy")
	await _step()
	await _step(false,false,false,-1)
	_expect(player.traversal.is_hanging() and not player.traversal.is_mantling(),"fresh W cannot pull up without feet support")
	await _step(false,false,false,1)
	_expect(not player.traversal.is_active(),"S drops grip-only edge")
	for frame in 60: await _step()
	_expect(player.is_on_floor(),"drop returns to safe floor")
	# The same narrow top with a measured wall below it is braced, not free.
	fixture_shape.size = Vector3(4,2.6,.22)
	fixture.position = origin+Vector3(0,1.3,0)
	await _real_jump()
	for frame in 50: await _step()
	_expect(player.traversal.is_hanging() and player.get_traversal_presentation().get("hang_style") == "braced","real wall under finite grip selects braced hang")
	# A formerly valid landing must not survive removal while hanging.
	fixture_shape.size = Vector3(4,2.6,2)
	fixture.position = origin+Vector3(0,1.3,-.89)
	await _real_jump()
	for frame in 50: await _step()
	_expect(player.traversal.is_hanging(),"wide top is caught before support changes")
	fixture_shape.size = Vector3(4,2.6,.22)
	fixture.position = origin+Vector3(0,1.3,0)
	await _step()
	await _step(false,false,false,-1)
	_expect(player.traversal.is_hanging() and not bool(player.traversal.state_machine.context.get("can_pull_up",true)),"fresh pull-up revalidates removed foot support")
	fixture.add_to_group("no_climb")
	await _real_jump()
	_expect(not player.traversal.is_active(),"no_climb never becomes grip-only exception")
	fixture.remove_from_group("no_climb")
	fixture_shape.size = Vector3(4,.18,.025)
	fixture.position = origin+Vector3(0,2.51,0)
	await _real_jump()
	_expect(not player.traversal.is_active(),"razor-depth top cannot provide finite hand grip")
	fixture_shape.size = Vector3(4,.18,.22)
	var ceiling := _box("HangCapsuleBlocker",Vector3(4,.2,1),origin+Vector3(0,1.7,.6))
	ceiling.add_to_group("no_climb")
	await _real_jump()
	_expect(not player.traversal.is_active(),"obstructed hang capsule cannot grab")
	ceiling.queue_free()
	world.queue_free()
	await process_frame
	print("MAIN_HANG_ONLY ","PASS" if failures.is_empty() else "FAIL"," ",failures)
	quit(0 if failures.is_empty() else 1)

func _real_jump() -> void:
	await _reset(origin+Vector3(0,.03,1.8))
	for frame in 20: await _step()
	_expect(player.is_on_floor(),"physical case starts on real floor")
	for frame in 8: await _step(false,false,false,-1)
	await _step(true,false,false,-1)
	_expect(player.velocity.y>0 and not player.traversal.is_active(),"actual jump precedes catch")
	for frame in 65:
		await _step(false,true,false,-1)
		if player.traversal.is_active(): break
