extends SceneTree

const Pickup := preload("res://scripts/items/field_backpack_pickup.gd")
const Host := preload("res://tools/fixtures/field_backpack_host.gd")
const Actor := preload("res://tools/fixtures/field_backpack_actor.gd")
var failures := 0
var branches: Array[Node] = []
var peers: Array[ENetMultiplayerPeer] = []

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FIELD_BACKPACK FAIL " + message)
	else:
		print("FIELD_BACKPACK PASS " + message)

func _run() -> void:
	for path in ["res://main.tscn", "res://multiplayer_slice.tscn"]:
		var scene: Node = load(path).instantiate()
		var component := scene.get_node_or_null("FieldBackpackPickup")
		check(component != null and component.get_script() == Pickup, "canonical component " + path)
		check(component.network_mode == path.contains("multiplayer"), "correct authority mode " + path)
		scene.free()
	var solo := Host.new()
	solo.name = "Solo"
	root.add_child(solo)
	var actor: Node3D = load("res://scenes/player/operator_player.tscn").instantiate()
	actor.name = "Player"
	solo.add_child(actor)
	actor.set_physics_process(false)
	actor.set("local_input_enabled", false)
	var pack := Pickup.new()
	pack.name = "FieldBackpackPickup"
	solo.add_child(pack)
	actor.position = pack.spawn_position() + Vector3(0.6, 0, 0)
	await physics_frame
	check(not pack.try_pick_up(9, 0, 0), "unknown peer rejected offline")
	actor.position.x += 10
	check(not pack.try_pick_up(1, 0, 0), "out-of-range rejected")
	actor.position = pack.spawn_position() + Vector3(1, 0, 0)
	actor.set("current_health", 0)
	check(not pack.try_pick_up(1, 0, 0), "dead player rejected")
	actor.set("current_health", 100)
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.1, 2, 2)
	collision.shape = shape
	wall.add_child(collision)
	solo.add_child(wall)
	wall.position = pack.spawn_position() + Vector3(0.5, 0.7, 0)
	await physics_frame
	await physics_frame
	check(not pack.try_pick_up(1, 0, 0), "through-wall rejected")
	wall.queue_free()
	await physics_frame
	await physics_frame
	if "--visual" in OS.get_cmdline_user_args():
		await _render(solo, actor, pack, false)
	check(pack.try_pick_up(1, 0, 0), "nearby living player receives item")
	check(pack.holder_peer_id == 1 and not pack.ground.visible, "ground item consumed")
	check(is_instance_valid(pack.attachment) and not pack.attachment.override_pose and pack.attachment.bone_name == "mixamorig_Spine2", "canonical spine follows without writing pose")
	check(is_instance_valid(pack.worn) and pack.worn.visible, "canonical actor wears real AGLS mesh")
	check(not pack.try_pick_up(1, 0, 0), "duplicate request rejected")
	var bomb: Node3D = pack._find_named(actor, "WearableBackpack")
	check(bomb != null and not bomb.visible, "bomb presentation unchanged on field pickup")
	if bomb != null:
		bomb.visible = true
		pack._update_visual()
		check(not pack.worn.visible and bomb.visible, "bomb priority without mutating objective")
		bomb.visible = false
		pack._update_visual()
		check(pack.worn.visible, "field pack returns after objective leaves back slot")
	if "--visual" in OS.get_cmdline_user_args():
		await _render(solo, actor, pack, true)
	actor.set("current_health", 0)
	pack._validate_holder()
	check(pack.holder_peer_id == 0 and pack.ground.visible, "death returns item to spawn")
	solo.queue_free()
	await process_frame
	await _network_checks()
	for peer in peers:
		peer.close()
	for branch in branches:
		set_multiplayer(null, branch.get_path())
		branch.queue_free()
	await process_frame
	print("FIELD_BACKPACK_REGRESSION %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)

func _network_checks() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	var error := server_peer.create_server(0, 4)
	check(error == OK, "ENet server started")
	if error != OK:
		return
	var port := server_peer.host.get_local_port()
	var server := _branch("Server", server_peer)
	var client_peer := ENetMultiplayerPeer.new()
	check(client_peer.create_client("127.0.0.1", port) == OK, "ENet client started")
	var client := _branch("Client", client_peer)
	await _settle(0.15)
	var client_id := client_peer.get_unique_id()
	var server_pack = server.get_node("FieldBackpackPickup")
	var client_pack = client.get_node("FieldBackpackPickup")
	_add_actor(server, client_id)
	_add_actor(client, client_id)
	await _settle(0.7)
	check(client_pack._synced, "admitted client gets initial reliable state")
	client_pack.interact()
	await _settle(0.12)
	check(server_pack.holder_peer_id == client_id and client_pack.holder_peer_id == client_id, "client RPC server awards and replicates pickup")
	# Server body is authoritative; sender cannot provide another actor/position.
	check(not server_pack.try_pick_up(777, server_pack.revision, 0), "unadmitted sender rejected online")
	var late_peer := ENetMultiplayerPeer.new()
	check(late_peer.create_client("127.0.0.1", port) == OK, "late client connects")
	var late := _branch("Late", late_peer)
	await _settle(0.15)
	var late_id := late_peer.get_unique_id()
	_add_actor(server, late_id)
	_add_actor(client, late_id)
	_add_actor(late, client_id)
	_add_actor(late, late_id)
	var late_pack = late.get_node("FieldBackpackPickup")
	await _settle(0.7)
	check(late_pack._synced and late_pack.holder_peer_id == client_id and not late_pack.ground.visible and is_instance_valid(late_pack.worn), "late join receives worn state and hides ground mesh")
	server.operators[client_id].respawn_revision += 1
	await _settle(0.1)
	check(server_pack.holder_peer_id == 0 and client_pack.holder_peer_id == 0 and late_pack.ground.visible, "respawn epoch clears and replicates item")
	check(not server_pack.try_pick_up(client_id, server_pack.revision, 0), "old-life request rejected")
	client.operators[client_id].received_respawn_revision = 1
	check(client_pack._life(client.operators[client_id]) == 1 and client.operators[client_id].respawn_revision == 0, "client uses received server epoch rather than local counter")
	client_pack.interact()
	late_pack.interact()
	await _settle(0.15)
	check(server_pack.holder_peer_id in [client_id, late_id] and client_pack.holder_peer_id == server_pack.holder_peer_id and late_pack.holder_peer_id == server_pack.holder_peer_id, "simultaneous RPC requests have one replicated winner")
	server.round_index += 1
	await _settle(0.12)
	check(server_pack.holder_peer_id == 0 and late_pack.holder_peer_id == 0, "round change returns pack")
	late_pack.interact()
	await _settle(0.12)
	check(server_pack.holder_peer_id == late_id, "late peer can pick up available item")
	late_peer.close()
	await _settle(0.2)
	check(server_pack.holder_peer_id == 0 and client_pack.holder_peer_id == 0, "disconnect returns item and informs remaining client")
	server.session_active = false
	check(not server_pack.try_pick_up(client_id, server_pack.revision, 1), "inactive session rejects pickup")

func _branch(branch_name: String, peer: ENetMultiplayerPeer) -> Node3D:
	var branch := Host.new()
	branch.name = branch_name
	root.add_child(branch)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	set_multiplayer(api, branch.get_path())
	var pack := Pickup.new()
	pack.name = "FieldBackpackPickup"
	pack.network_mode = true
	branch.add_child(pack)
	branches.append(branch)
	peers.append(peer)
	return branch

func _add_actor(host: Node3D, id: int) -> void:
	var actor := Actor.new()
	actor.name = "Operator%d" % id
	host.add_child(actor)
	actor.position = host.get_node("FieldBackpackPickup").spawn_position() + Vector3(0.5, 0, 0)
	var skeleton := Skeleton3D.new()
	actor.add_child(skeleton)
	skeleton.add_bone("mixamorig_Spine2")
	host.operators[id] = actor

func _settle(seconds: float) -> void:
	await create_timer(seconds).timeout

func _render(host: Node3D, actor: Node3D, pack: Node3D, equipped: bool) -> void:
	var camera := Camera3D.new()
	host.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.8
	camera.position = actor.position + Vector3(2.4, 1.7, 3.4)
	camera.look_at(actor.position + Vector3(0, 1, 0))
	var light := DirectionalLight3D.new()
	host.add_child(light)
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 2.0
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.14, 0.17)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	host.add_child(environment)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var suffix := "worn" if equipped else "ground"
	root.get_texture().get_image().save_png("/private/tmp/field-backpack-%s.png" % suffix)
	if equipped:
		camera.position = actor.position + Vector3(-3.4, 1.5, 0.2)
		camera.look_at(actor.position + Vector3(0, 1, 0))
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/field-backpack-side.png")
	print("FIELD_BACKPACK_VISUAL ", suffix, " worn_transform=", pack.worn.global_transform if equipped else pack.ground.global_transform)
	camera.queue_free()
	light.queue_free()
	environment.queue_free()
