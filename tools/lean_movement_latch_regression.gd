extends "res://tools/rifle_reference_visual_probe.gd"

const Command := preload("res://scripts/network/socom_movement_command.gd")
const Protocol := preload("res://scripts/network/socom_network_protocol.gd")
const Delivery := preload("res://scripts/network/socom_movement_delivery.gd")
const Latch := preload("res://scripts/player/player_lean_latch.gd")
const State := preload("res://scripts/network/socom_movement_state.gd")
const NetworkActor := preload("res://scripts/network/socom_network_operator.gd")
var tick_id: int = 0

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func command(peek: int = 0, move: int = 0):
	var c = Command.new()
	tick_id += 1
	c.simulation_tick = tick_id
	c.peek_held_mask = peek
	c.peek_axis = float(bool(peek & 2)) - float(bool(peek & 1))
	c.direction_held_mask = move
	c.move_axis = Vector2(float(bool(move & 4))-float(bool(move & 2)),float(bool(move & 8))-float(bool(move & 1))).normalized()
	return c

func tick(peek: int = 0, move: int = 0) -> void:
	# move_and_slide uses the engine's current frame delta internally.
	# Manual prediction ticks must run inside a real physics frame in both
	# headless and rendered tests, not with a render-dependent process delta.
	await physics_frame
	player.queue_movement_command(Protocol.packet_to_movement(Protocol.movement_to_packet(command(peek, move))))
	player._physics_process(1.0/60.0)
	await process_frame

func _run() -> void:
	output_prefix = "/private/tmp/lean-movement-latch"
	var latch = Latch.new()
	check(latch.update(command(1),true)==-1, "left enters")
	check(latch.update(command(),true)==-1, "release holds")
	check(latch.update(command(1),true)==0, "same side toggles off")
	latch.update(command(),true)
	latch.update(command(1),true)
	check(latch.update(command(3),true)==1, "opposite switches while first key held")
	check(latch.update(command(),true)==1, "switch stays latched")
	for frame in 6: check(latch.update(command(0,1),true)==1, "short tap retains lean")
	check(latch.update(command(),true)==1 and latch.movement_hold_elapsed==0.0, "release resets timer and keeps lean")
	for frame in 13: check(latch.update(command(0,1 if frame<6 else 5),true)==1, "changing direction does not prematurely exit")
	check(latch.update(command(0,4),true)==0, "continuous hold exits even across direction changes")
	for rate in [30,60,120]:
		latch.reset()
		latch.update(command(1),true,1.0/rate)
		var elapsed := 0.0
		while latch.is_active():
			latch.update(command(0,1),true,1.0/rate)
			elapsed += 1.0/rate
			if elapsed>1.0: break
		check(elapsed >= latch.hold_seconds()-0.00001 and elapsed < latch.hold_seconds()+1.0/rate+0.00001, "hold uses simulation seconds at %d Hz" % rate)
	latch.reset()
	latch.update(command(1),true)
	var noise = command()
	noise.move_axis = Vector2(0.01,0)
	for frame in 30: latch.update(noise,true)
	check(latch.side==-1 and latch.movement_hold_elapsed==0.0, "stick noise cannot release lean")
	latch.reset()
	latch.update(command(1),true)
	check(latch.update(command(1),false)==0, "incompatible action clears")
	check(latch.update(command(1),true)==0, "held lean does not relatch after action")
	latch.reset()
	check(latch.update(command(3),true)==0, "simultaneous lean cancels")
	var sender = Delivery.new()
	var receiver = Delivery.new()
	latch.reset()
	sender.outgoing(Protocol.movement_to_packet(command(1)),0)
	var delivered: Array[Dictionary] = receiver.incoming(sender.outgoing(Protocol.movement_to_packet(command()),0))
	for packet in delivered: latch.update(Protocol.packet_to_movement(packet),true)
	check(latch.side==-1, "lost press recovered from network history")
	var bad: Dictionary = Protocol.movement_to_packet(command())
	bad.peek_held = 9
	check(not Protocol.movement_packet_is_sane(bad), "network rejects invalid mask")
	var actor = NetworkActor.new()
	actor.visual_runtime_enabled = false
	root.add_child(actor)
	actor.set_physics_process(false)
	actor.lean_latch.update(command(2,1),true)
	for frame in 5: actor.lean_latch.update(command(0,1),true)
	var timer: float = actor.lean_latch.movement_hold_elapsed
	var saved: Array = State.unpack(State.pack(State.capture(actor)))
	actor.lean_latch.reset()
	State.apply(actor,saved)
	check(actor.lean_latch.side==1 and actor.lean_latch.previous_direction_mask==1, "prediction restores state and input edges")
	check(is_equal_approx(actor.lean_latch.movement_hold_elapsed,timer), "prediction restores partial movement hold")
	for frame in 7: actor.lean_latch.update(command(0,1),true)
	check(actor.lean_latch.is_active(), "replayed partial hold remains below threshold")
	actor.lean_latch.update(command(0,1),true)
	check(not actor.lean_latch.is_active(), "replayed hold exits on same tick")
	actor.respawn_at(Vector3.ZERO)
	check(not actor.lean_latch.is_active(), "respawn releases latch")
	actor.queue_free()
	scene = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(60)
	player = scene.get_node("Player")
	driver = player.get_node("Mannequin/ProductionAnimation")
	controller = scene.get_node("WeaponController")
	controller.set_input_enabled(false)
	player.set_local_input_enabled(false)
	player.automatic_vault_enabled = false
	_install_fixture()
	await _frames(30)
	player.set_physics_process(false)
	for stance in [player.MotionState.STANDING,player.MotionState.CROUCHED,player.MotionState.PRONE]:
		player.lean_latch.reset()
		player._try_set_posture(stance)
		player.velocity = Vector3(3,0,-4)
		await tick(1)
		var planted: Vector3 = player.global_position
		for frame in 16: await tick()
		check(Vector2(player.global_position.x-planted.x,player.global_position.z-planted.z).length()<0.001, "canonical planted stance %d" % stance)
		check(player.peek_amount < -0.95, "canonical held pose stance %d" % stance)
		await capture_state("left_%d" % stance)
		for frame in 16: await tick(2)
		check(player.peek_amount > 0.95, "canonical opposite pose stance %d" % stance)
		await capture_state("right_%d" % stance)
		var before: Vector3 = player.global_position
		for frame in 6: await tick(0,1)
		var distance: float = Vector2(player.global_position.x-before.x,player.global_position.z-before.z).length()
		check(distance>0.02 and distance<0.075 and player.lean_latch.is_active(), "canonical micro tap stance %d distance=%f" % [stance,distance])
		await capture_state("step_%d" % stance)
		await tick()
		before = player.global_position
		for frame in 6: await tick()
		var stopped_drift := Vector2(player.global_position.x-before.x,player.global_position.z-before.z).length()
		print("LEAN_STOP stance=",stance," horizontal=",stopped_drift," vertical=",player.global_position.y-before.y)
		check(stopped_drift<0.001 and player.lean_latch.is_active(), "release plants immediately and retains lean stance %d" % stance)
		for frame in 13: await tick(0,1)
		check(player.lean_latch.is_active(), "hold not released early stance %d" % stance)
		await tick(0,1)
		check(not player.lean_latch.is_active() and player.velocity.length()>0.65, "hold resumes normal speed on threshold tick stance %d" % stance)
	# Diagonal taps cannot exceed the same total speed cap; taps can repeat.
	player._try_set_posture(player.MotionState.STANDING)
	player.lean_latch.reset()
	await tick(1)
	for direction in [1,2,4,8,3,5,10,12]:
		for frame in 6:
			await tick(0,direction)
			check(Vector2(player.velocity.x,player.velocity.z).length() <= 0.65001, "eight-way tap speed cap")
		await tick()
		check(player.lean_latch.is_active(), "repeated taps keep lean")
	# Edge adjustment still collides with cover; it is never a position offset.
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3,3,0.2)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	scene.add_child(wall)
	wall.global_position = player.global_position + Vector3(0,1,-0.5)
	await physics_frame
	await physics_frame
	var edge_start: Vector3 = player.global_position
	var hit_wall := false
	for tap in 5:
		for frame in 6:
			await tick(0,1)
			hit_wall = hit_wall or player.is_on_wall()
		await tick()
	check(hit_wall and edge_start.z-player.global_position.z<0.08, "micro taps respect cover collision")
	check(player.lean_latch.is_active(), "blocked taps retain lean without auto-vault")
	wall.queue_free()
	player.lean_latch.update(command(1),true)
	player.set_local_input_enabled(false)
	check(not player.lean_latch.is_active(), "input disable releases latch")
	print("LEAN_MOVEMENT_LATCH ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	_finish()

func capture_state(label: String) -> void:
	if not capture: return
	camera.global_position = player.global_position + Vector3(2.5,1.6,3.4)
	camera.look_at(player.global_position + Vector3(0,0.9,0))
	camera.current = true
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(output_prefix + "-" + label + ".png")
