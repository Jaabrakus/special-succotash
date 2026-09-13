extends Node3D

## Sole field-item state owner. Never writes actor movement, pose, or bomb state.
const PROFILE_PATH := "res://config/field_backpack.json"
const DEFAULT_MESH := preload("res://assets/props/agls_field_backpack/backpack.scn")
const KeyboardMapping := preload("res://scripts/input/socom_keyboard_mapping_profile.gd")
@export var network_mode := false
var profile: Dictionary = {}
var holder_peer_id := 0
var revision := 0
var ground: Node3D
var prompt: Label3D
var attachment: BoneAttachment3D
var worn: Node3D
var _wearer: Node3D
var _authority_wearer: Node3D
var _holder_life := 0
var _holder_round := 0
var _synced := false
var _sync_wait := 0.0
var _last_request: Dictionary = {}
var _mesh: PackedScene
var _transport: MultiplayerPeer


func _ready() -> void:
	profile = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not bool(profile.get("enabled", true)):
		set_process(false)
		return
	_mesh = DEFAULT_MESH if String(profile.mesh) == DEFAULT_MESH.resource_path else load(String(profile.mesh)) as PackedScene
	ground = _mesh.instantiate() as Node3D
	ground.name = "GroundFieldBackpack"
	add_child(ground)
	ground.position = spawn_position() + Vector3(0, 0.26, 0)
	prompt = Label3D.new()
	prompt.name = "FieldPackPrompt"
	prompt.text = "F  PICK UP FIELD PACK"
	prompt.font_size = 42
	prompt.pixel_size = 0.003
	prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt.position = spawn_position() + Vector3(0, 0.8, 0)
	prompt.visible = false
	add_child(prompt)
	if network_mode:
		multiplayer.peer_disconnected.connect(_peer_disconnected)


func spawn_position() -> Vector3:
	return _vector(profile.get("network_spawn" if network_mode else "local_spawn", [0, 0, 0]))


func _process(delta: float) -> void:
	if network_mode and (_transport != multiplayer.multiplayer_peer or not _connected()):
		_transport = multiplayer.multiplayer_peer
		_synced = false
		_sync_wait = 0.0
		holder_peer_id = 0
		revision = 0
		_authority_wearer = null
		_last_request.clear()
		_clear_worn()
		if not _connected():
			ground.visible = false
			prompt.visible = false
			return
	if _is_authority():
		_validate_holder()
	elif _connected() and not _synced:
		_sync_wait -= delta
		if _sync_wait <= 0.0:
			_sync_wait = 0.5
			request_state.rpc_id(1)
	_update_visual()
	var actor := _actor(multiplayer.get_unique_id() if network_mode else 1)
	var can_interact := _can_pick_up(actor) and _gameplay_allowed(multiplayer.get_unique_id() if network_mode else 1)
	prompt.visible = can_interact and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if prompt.visible:
		prompt.text = "%s  PICK UP FIELD PACK" % KeyboardMapping.binding_text(&"interact")
	if prompt.visible and Input.is_action_just_pressed("interact") and bool(actor.get("local_input_enabled")):
		interact()


func interact() -> void:
	if network_mode and not _connected():
		return
	var id := multiplayer.get_unique_id() if network_mode else 1
	var actor := _actor(id)
	if not _can_pick_up(actor) or not _gameplay_allowed(id):
		return
	var life := _life(actor)
	if _is_authority():
		try_pick_up(id, revision, life)
	elif _connected() and _synced:
		request_pickup.rpc_id(1, revision, life)


@rpc("any_peer", "call_remote", "reliable")
func request_pickup(expected_revision: int, life: int) -> void:
	if _is_authority():
		try_pick_up(multiplayer.get_remote_sender_id(), expected_revision, life)


@rpc("any_peer", "call_remote", "reliable")
func request_state() -> void:
	if not _is_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	# Admission must have created the canonical actor; don't answer strangers.
	if _actor(sender) == null:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_request.get(sender, -1000)) < 250:
		return
	_last_request[sender] = now
	receive_state.rpc_id(sender, holder_peer_id, revision)


@rpc("authority", "call_remote", "reliable")
func receive_state(holder: int, state_revision: int) -> void:
	if _is_authority() or state_revision < revision:
		return
	holder_peer_id = holder
	revision = state_revision
	_synced = true
	_update_visual()


func try_pick_up(peer_id: int, expected_revision: int, life: int) -> bool:
	if not _is_authority() or expected_revision != revision or not _gameplay_allowed(peer_id):
		return false
	var actor := _actor(peer_id)
	if not _can_pick_up(actor) or life != _life(actor):
		return false
	holder_peer_id = peer_id
	_authority_wearer = actor
	_holder_life = life
	_holder_round = _round()
	revision += 1
	_publish()
	return true


func _can_pick_up(actor: Node3D) -> bool:
	if holder_peer_id != 0 or not _alive(actor):
		return false
	var target := global_transform * (spawn_position() + Vector3(0, 0.3, 0))
	if actor.global_position.distance_to(global_transform * spawn_position()) > float(profile.get("pickup_range", 1.65)):
		return false
	var query := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3(0, 0.6, 0), target)
	if actor is CollisionObject3D:
		query.exclude = [(actor as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _gameplay_allowed(peer_id: int) -> bool:
	if not network_mode:
		return true
	var host := get_parent()
	return (bool(host.get("session_active")) or bool(host.call("is_lobby_warmup_active"))) and bool(host.call("is_peer_gameplay_action_allowed", peer_id))


func _validate_holder() -> void:
	if holder_peer_id == 0:
		return
	var actor := _actor(holder_peer_id)
	if not _alive(actor) or actor != _authority_wearer or _life(actor) != _holder_life or _round() != _holder_round or not _gameplay_allowed(holder_peer_id):
		holder_peer_id = 0
		_authority_wearer = null
		revision += 1
		_publish()


func _publish() -> void:
	_update_visual()
	if not network_mode or not _connected():
		return
	# Only admitted peers with actors receive this item state.
	for peer_id in multiplayer.get_peers():
		if _actor(peer_id) != null:
			receive_state.rpc_id(peer_id, holder_peer_id, revision)


func _peer_disconnected(peer_id: int) -> void:
	_last_request.erase(peer_id)
	if _is_authority() and holder_peer_id == peer_id:
		holder_peer_id = 0
		_authority_wearer = null
		revision += 1
		_publish()


func _actor(peer_id: int) -> Node3D:
	if peer_id <= 0:
		return null
	if not network_mode:
		return get_parent().get_node_or_null("Player") as Node3D if peer_id == 1 else null
	var actors: Dictionary = get_parent().get("operators")
	var actor: Variant = actors.get(peer_id)
	return actor as Node3D if is_instance_valid(actor) else null


func _alive(actor: Node3D) -> bool:
	return is_instance_valid(actor) and float(actor.get("current_health")) > 0.0 and (not "alive" in actor or bool(actor.get("alive")))


func _life(actor: Node3D) -> int:
	if not is_instance_valid(actor):
		return 0
	# Clients consume the server's received epoch; their local respawn counter
	# is not authoritative and may differ after a round or warmup respawn.
	var field := "received_respawn_revision" if network_mode and not _is_authority() else "respawn_revision"
	return int(actor.get(field)) if field in actor else 0


func _round() -> int:
	return int(get_parent().get("round_index")) if network_mode else 0


func _is_authority() -> bool:
	return not network_mode or (_connected() and multiplayer.is_server())


func _connected() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _update_visual() -> void:
	if ground == null:
		return
	ground.visible = holder_peer_id == 0 and (not network_mode or _is_authority() or _synced)
	var actor := _actor(holder_peer_id)
	if actor != _wearer or (is_instance_valid(actor) and not is_instance_valid(attachment)):
		_clear_worn()
		if is_instance_valid(actor):
			_attach_to(actor)
	if is_instance_valid(worn):
		# The bomb retains its own state/writer and gets visual priority.
		var bomb := _find_named(actor, "WearableBackpack") as Node3D
		worn.visible = _alive(actor) and (bomb == null or not bomb.visible)


func _attach_to(actor: Node3D) -> void:
	var skeleton := _find_skeleton(actor)
	if skeleton == null or skeleton.find_bone(String(profile.bone_name)) < 0:
		return
	attachment = BoneAttachment3D.new()
	attachment.name = "FieldBackpackAttachment"
	skeleton.add_child(attachment)
	attachment.bone_name = String(profile.bone_name)
	attachment.override_pose = false
	worn = _mesh.instantiate() as Node3D
	worn.name = "WornFieldBackpack"
	attachment.add_child(worn)
	var inverse_scale := 1.0 / skeleton.global_basis.get_scale().abs().x
	worn.position = _vector(profile.wear_position) * inverse_scale
	worn.rotation_degrees = _vector(profile.wear_rotation_degrees)
	worn.scale = Vector3.ONE * inverse_scale * float(profile.wear_scale)
	_wearer = actor


func _clear_worn() -> void:
	if is_instance_valid(attachment):
		attachment.get_parent().remove_child(attachment)
		attachment.queue_free()
	attachment = null
	worn = null
	_wearer = null


func _exit_tree() -> void:
	_clear_worn()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_named(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	for child in node.get_children():
		var found := _find_named(child, node_name)
		if found != null:
			return found
	return null


func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
