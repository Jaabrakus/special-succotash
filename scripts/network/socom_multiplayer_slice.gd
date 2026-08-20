class_name SocomMultiplayerSlice
extends Node3D

## Small authoritative multiplayer vertical slice.
##
## Server owns movement simulation, ballistics, damage, score and respawn.
## The owning client predicts its CharacterBody and reconciles to snapshots;
## remote clients render interpolated authoritative states. Camera transforms,
## animation frames and client damage values never cross the network boundary.

const NetworkOperatorScript := preload("res://scripts/network/socom_network_operator.gd")
const NetworkProtocol := preload("res://scripts/network/socom_network_protocol.gd")
const CameraRigScript := preload("res://scripts/camera/socom_camera.gd")
const ShotAuthority := preload("res://scripts/network/socom_shot_authority.gd")
const BallisticsScript := preload("res://scripts/weapons/weapon_ballistics.gd")
const ComposureScript := preload("res://scripts/weapons/operator_composure.gd")
const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const TracerSystemScript := preload("res://scripts/weapons/lab_leak_tracer_system.gd")

const PlayerScript := preload("res://scripts/player/player_controller.gd")

const DEFAULT_PORT := 14141
const MAX_PLAYERS := 16
const SNAPSHOT_INTERVAL := 1.0 / 20.0
const RESPAWN_SECONDS := 3.0
const SCORE_LIMIT := 5

@export var simulated_network_latency_ms: float = 0.0
@export var remote_interpolation_delay_seconds: float = 0.130

var operators: Dictionary = {}
var server_ballistics: Dictionary = {}
var server_composure: Dictionary = {}
var latest_commands: Dictionary = {}
var last_command_tick: Dictionary = {}
var last_accepted_shot_sequence: Dictionary = {}
var scores: Dictionary = {}
var assigned_spawns: Dictionary = {}
var pending_snapshots: Dictionary = {}
var logged_command_peers: Dictionary = {}
var logged_first_snapshot: bool = false
var spawn_points: Array[Vector3] = [
	Vector3(-8.0, 0.05, 9.0), Vector3(-5.5, 0.05, 9.0),
	Vector3(-3.0, 0.05, 9.0), Vector3(-0.5, 0.05, 9.0),
	Vector3(2.0, 0.05, 9.0), Vector3(4.5, 0.05, 9.0),
	Vector3(7.0, 0.05, 9.0), Vector3(9.0, 0.05, 7.0),
	Vector3(-8.0, 0.05, -13.0), Vector3(-5.5, 0.05, -13.0),
	Vector3(-3.0, 0.05, -13.0), Vector3(-0.5, 0.05, -13.0),
	Vector3(2.0, 0.05, -13.0), Vector3(4.5, 0.05, -13.0),
	Vector3(7.0, 0.05, -13.0), Vector3(9.0, 0.05, -11.0),
]

var network_peer: ENetMultiplayerPeer
var local_camera: SocomCameraRig
var local_operator: SocomNetworkOperator
var snapshot_accumulator: float = 0.0
var local_fire_cooldown: float = 0.0
var equipped_config: Dictionary = {}
var session_active: bool = false
var round_active: bool = true

var menu_panel: PanelContainer
var address_edit: LineEdit
var status_label: Label
var score_label: Label
var reticle: Label


func _ready() -> void:
	process_physics_priority = 100
	_ensure_input_map()
	_build_environment()
	_build_ui()
	TracerSystemScript.initialize(self)
	equipped_config = WeaponContract.load_equipped_config()
	_connect_multiplayer_signals()
	_apply_command_line_mode()


func _physics_process(delta: float) -> void:
	if not session_active:
		return
	local_fire_cooldown = maxf(0.0, local_fire_cooldown - delta)
	var local_id := multiplayer.get_unique_id()
	if local_operator != null and local_operator.alive:
		var command = local_operator.get_last_movement_command()
		if command != null:
			var packet := NetworkProtocol.movement_to_packet(command)
			if multiplayer.is_server():
				latest_commands[local_id] = packet
			else:
				submit_movement.rpc_id(1, packet)
		_try_submit_local_shot()

	if not multiplayer.is_server():
		return
	_advance_server_composure(delta)
	snapshot_accumulator += delta
	if snapshot_accumulator >= SNAPSHOT_INTERVAL:
		snapshot_accumulator = fmod(snapshot_accumulator, SNAPSHOT_INTERVAL)
		_broadcast_authoritative_state()


func _process(_delta: float) -> void:
	if (
		session_active
		and local_operator != null
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and Input.is_action_just_pressed("reload_weapon")
		and local_operator.mannequin != null
	):
		local_operator.mannequin.play_operator_semantic_action(&"reload", 0.12)
	var current_time_sec := Time.get_ticks_msec() / 1000.0
	for raw_id in operators:
		var operator := operators[raw_id] as SocomNetworkOperator
		if operator != null and operator.is_proxy_replica:
			operator.update_proxy_interpolation(current_time_sec)
	
	if pending_snapshots.is_empty():
		return
	var local_id := multiplayer.get_unique_id()
	var raw_key = local_id if pending_snapshots.has(local_id) else str(local_id)
	if pending_snapshots.has(raw_key):
		var operator := operators.get(local_id) as SocomNetworkOperator
		if operator != null:
			var state: Dictionary = pending_snapshots[raw_key]
			operator.set_authoritative_snapshot(
				Vector3(state.get("position", operator.global_position)),
				float(state.get("yaw", operator.rotation.y)),
				Vector3(state.get("velocity", Vector3.ZERO)),
				int(state.get("posture", 0)),
				float(state.get("health", operator.current_health)),
				bool(state.get("alive", true)),
				false
			)
	pending_snapshots.clear()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and session_active:
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)
		get_viewport().set_input_as_handled()


func host_match(port: int = DEFAULT_PORT) -> Error:
	_disconnect_existing_peer()
	network_peer = ENetMultiplayerPeer.new()
	var error := network_peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		_set_status("HOST FAILED: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = network_peer
	session_active = true
	menu_panel.visible = false
	_set_status("HOSTING :%d  •  waiting for players" % port)
	_server_spawn_operator(1, 0, spawn_points[0])
	print("MP_SLICE HOST_READY port=%d peer=1" % port)
	return OK


func join_match(address: String, port: int = DEFAULT_PORT) -> Error:
	_disconnect_existing_peer()
	network_peer = ENetMultiplayerPeer.new()
	var clean_address := address.strip_edges()
	if clean_address.is_empty():
		clean_address = "127.0.0.1"
	var error := network_peer.create_client(clean_address, port)
	if error != OK:
		_set_status("JOIN FAILED: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = network_peer
	_set_status("CONNECTING TO %s:%d" % [clean_address, port])
	return OK


func _connect_multiplayer_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	for existing_id in operators:
		var existing := operators[existing_id] as SocomNetworkOperator
		spawn_operator.rpc_id(
			peer_id,
			int(existing_id),
			existing.team_id,
			existing.global_position
		)
	var assigned_team := operators.size() % 2
	var assigned_spawn := _spawn_for_team(assigned_team, _team_member_count(assigned_team))
	_server_spawn_operator(peer_id, assigned_team, assigned_spawn)
	spawn_operator.rpc(peer_id, assigned_team, assigned_spawn)
	_set_status("PLAYER %d JOINED  •  %d connected" % [peer_id, operators.size()])
	print("MP_SLICE PEER_JOINED peer=%d players=%d" % [peer_id, operators.size()])


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		_remove_operator(peer_id)
		despawn_operator.rpc(peer_id)
		_set_status("PLAYER %d LEFT  •  %d connected" % [peer_id, operators.size()])


func _on_connected_to_server() -> void:
	session_active = true
	menu_panel.visible = false
	_set_status("CONNECTED  •  server-authoritative match")
	print("MP_SLICE CLIENT_CONNECTED peer=%d" % multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	_set_status("CONNECTION FAILED")
	menu_panel.visible = true


func _on_server_disconnected() -> void:
	session_active = false
	_set_status("SERVER DISCONNECTED")
	menu_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_clear_operators()


@rpc("authority", "call_remote", "reliable")
func spawn_operator(peer_id: int, team: int, spawn_position: Vector3) -> void:
	_spawn_operator_local(peer_id, team, spawn_position)


@rpc("authority", "call_remote", "reliable")
func despawn_operator(peer_id: int) -> void:
	_remove_operator(peer_id)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_movement(packet: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not operators.has(sender):
		return
	if not NetworkProtocol.movement_packet_is_sane(packet):
		return
	var command_tick := int(packet.get("tick", -1))
	if command_tick <= int(last_command_tick.get(sender, -1)):
		return
	last_command_tick[sender] = command_tick
	latest_commands[sender] = packet
	var operator := operators[sender] as SocomNetworkOperator
	operator.queue_movement_command(NetworkProtocol.packet_to_movement(packet))
	if not logged_command_peers.has(sender):
		logged_command_peers[sender] = true
		print("MP_SLICE COMMAND_ACCEPTED peer=%d" % sender)


@rpc("any_peer", "call_remote", "reliable")
func submit_shot(packet: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_server_process_shot(
		multiplayer.get_remote_sender_id(),
		packet
	)


@rpc("authority", "call_remote", "unreliable_ordered")
func receive_world_state(snapshot_packet: Dictionary, score_snapshot: Dictionary) -> void:
	scores = score_snapshot
	var entities: Dictionary = snapshot_packet.get("entities", snapshot_packet)
	var timestamp_seconds := float(snapshot_packet.get("timestamp_ms", Time.get_ticks_msec())) / 1000.0
	var local_id := multiplayer.get_unique_id()
	
	for raw_id in entities:
		var peer_id := int(raw_id)
		var operator := operators.get(peer_id) as SocomNetworkOperator
		if operator == null:
			continue
		var state: Dictionary = entities[raw_id]
		if peer_id == local_id:
			pending_snapshots[raw_id] = state
		else:
			operator.push_network_snapshot(
				Vector3(state.get("position", operator.global_position)),
				float(state.get("yaw", operator.rotation.y)),
				Vector3(state.get("velocity", Vector3.ZERO)),
				int(state.get("posture", 0)),
				float(state.get("health", operator.current_health)),
				bool(state.get("alive", true)),
				timestamp_seconds
			)
	
	if not logged_first_snapshot:
		logged_first_snapshot = true
		print("MP_SLICE SNAPSHOT_RECEIVED operators=%d" % entities.size())
	_refresh_scoreboard()


@rpc("authority", "call_remote", "reliable")
func receive_shot_effect(
	shooter_peer_id: int,
	origin: Vector3,
	impact: Vector3,
	hit: bool,
	message: String
) -> void:
	_present_shot(shooter_peer_id, origin, impact, hit, message)


@rpc("authority", "call_remote", "reliable")
func receive_match_event(message: String) -> void:
	_set_status(message)


func _server_spawn_operator(
	peer_id: int,
	assigned_team: int,
	assigned_spawn: Vector3
) -> void:
	assigned_spawns[peer_id] = assigned_spawn
	_spawn_operator_local(peer_id, assigned_team, assigned_spawn)
	var ballistics = BallisticsScript.new()
	ballistics.name = "ServerBallistics_%d" % peer_id
	add_child(ballistics)
	_apply_ballistics_profile(ballistics)
	server_ballistics[peer_id] = ballistics
	var composure = ComposureScript.new()
	composure.configure_weapon(equipped_config.get("composure", {}))
	server_composure[peer_id] = composure
	last_accepted_shot_sequence[peer_id] = -1
	scores[peer_id] = 0


func _spawn_operator_local(peer_id: int, team: int, spawn_position: Vector3) -> void:
	if operators.has(peer_id):
		return
	var operator := NetworkOperatorScript.new() as SocomNetworkOperator
	operator.name = "NetworkOperator_%d" % peer_id
	operator.position = spawn_position
	operator.rotation.y = PI if team == 0 else 0.0
	operator.interpolation_delay_seconds = remote_interpolation_delay_seconds
	add_child(operator)
	operator.configure_identity(peer_id, team)
	operators[peer_id] = operator
	var local_id := multiplayer.get_unique_id()
	var is_local_owner := peer_id == local_id
	operator.set_replica_mode(not is_local_owner and not multiplayer.is_server())
	operator.set_local_input_enabled(is_local_owner)
	if multiplayer.is_server():
		operator.eliminated.connect(_on_operator_eliminated)
	if is_local_owner:
		local_operator = operator
		_attach_local_camera(operator)
	print("MP_SLICE OPERATOR_SPAWN peer=%d team=%d local=%s" % [peer_id, team, is_local_owner])
	_refresh_scoreboard()


func _remove_operator(peer_id: int) -> void:
	var operator := operators.get(peer_id) as SocomNetworkOperator
	if operator != null:
		operator.queue_free()
	operators.erase(peer_id)
	latest_commands.erase(peer_id)
	last_accepted_shot_sequence.erase(peer_id)
	last_command_tick.erase(peer_id)
	scores.erase(peer_id)
	assigned_spawns.erase(peer_id)
	var ballistics := server_ballistics.get(peer_id) as Node
	if ballistics != null:
		ballistics.queue_free()
	server_ballistics.erase(peer_id)
	server_composure.erase(peer_id)
	_refresh_scoreboard()


func _clear_operators() -> void:
	for peer_id in operators.keys():
		_remove_operator(int(peer_id))
	operators.clear()
	local_operator = null
	if local_camera:
		local_camera.queue_free()
		local_camera = null


func _attach_local_camera(operator: SocomNetworkOperator) -> void:
	if local_camera != null:
		local_camera.queue_free()
	local_camera = CameraRigScript.new() as SocomCameraRig
	local_camera.name = "LocalSOCOMCamera"
	local_camera.target = operator
	local_camera.head_marker = operator.mannequin.head_marker
	local_camera.torso_marker = operator.mannequin.torso_marker
	local_camera.pelvis_marker = operator.mannequin.pelvis_marker
	local_camera.feet_marker = operator.mannequin.feet_marker
	local_camera.yaw = operator.global_rotation.y
	add_child(local_camera)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _try_submit_local_shot() -> void:
	if (
		local_camera == null
		or local_operator == null
		or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		or not Input.is_action_pressed("fire")
		or local_fire_cooldown > 0.0
	):
		return
	local_fire_cooldown = _configured_fire_interval()
	var packet := local_camera.build_local_aim_intent()
	if packet.is_empty():
		return
	if multiplayer.is_server():
		_server_process_shot(multiplayer.get_unique_id(), packet)
	else:
		submit_shot.rpc_id(1, packet)


func _server_process_shot(peer_id: int, packet: Dictionary) -> void:
	var shooter := operators.get(peer_id) as SocomNetworkOperator
	var ballistics = server_ballistics.get(peer_id)
	if shooter == null or ballistics == null or not shooter.alive or not round_active:
		return
	var muzzle_marker := shooter.mannequin.get_active_muzzle_marker()
	if muzzle_marker == null:
		return
	var muzzle := muzzle_marker.global_position
	var validation := ShotAuthority.validate_intent(
		packet,
		muzzle,
		int(last_accepted_shot_sequence.get(peer_id, -1)),
		-1
	)
	if not bool(validation.get("accepted", false)):
		return
	last_accepted_shot_sequence[peer_id] = int(packet.get("sequence", 0))
	var exclude: Array[RID] = [shooter.get_rid()]
	if shooter.hurtbox_rig:
		exclude.append_array(shooter.hurtbox_rig.get_hurtbox_rids())
	var movement_ratio := clampf(
		Vector2(shooter.velocity.x, shooter.velocity.z).length()
		/ maxf(shooter.move_speed, 0.001),
		0.0,
		1.0
	)
	var composure = server_composure.get(peer_id)
	var dispersion_multiplier: float = float(composure.get_shot_dispersion_multiplier(
		int(ballistics.continuous_shot_count) + 1,
		movement_ratio,
		0.0
	))
	var core_scale: float = float(composure.get_precision_core_scale())
	var seed := int(packet.get("sequence", 0)) * 73856093 ^ peer_id * 19349663
	var result: Dictionary = ballistics.try_fire_direction(
		muzzle,
		Vector3(validation.direction),
		get_world_3d().direct_space_state,
		exclude,
		seed,
		shooter.get_posture_name(),
		movement_ratio,
		not shooter.is_on_floor(),
		dispersion_multiplier
	)
	if not bool(result.get("fired", false)):
		return
	composure.notify_shot()
	var damage_message := "MISS"
	var collider: Object = result.get("hit_collider")
	if collider != null and collider.has_method("get_damage_receiver"):
		var receiver := collider.call("get_damage_receiver") as SocomNetworkOperator
		if receiver != null and receiver.team_id != shooter.team_id:
			var classification: Dictionary = collider.call(
				"classify_shot_path",
				muzzle,
				Vector3(result.direction),
				core_scale
			)
			var damage_scale := (
				1.0
				if bool(classification.get("precision", true))
				else clampf(
					float(equipped_config.get("composure", {}).get("graze_damage_scale", 0.38)),
					0.0,
					1.0
				)
			)
			var damage_result := receiver.take_bullet_damage_region(
				float(ballistics.damage_per_shot) * damage_scale,
				StringName(collider.call("get_hit_region")),
				Vector3(result.hit_pos),
				Vector3(result.get("normal", Vector3.UP)),
				muzzle,
				peer_id
			)
			if bool(damage_result.get("accepted", false)):
				damage_message = "%s  %.0f DMG" % [
					String(damage_result.get("hit_region", &"HIT")),
					float(damage_result.get("damage", 0.0)),
				]
	var hit := collider != null
	_present_shot(peer_id, muzzle, Vector3(result.hit_pos), hit, damage_message)
	receive_shot_effect.rpc(peer_id, muzzle, Vector3(result.hit_pos), hit, damage_message)


func _advance_server_composure(delta: float) -> void:
	for raw_id in server_composure:
		var peer_id := int(raw_id)
		var operator := operators.get(peer_id) as SocomNetworkOperator
		if operator == null:
			continue
		var ratio := clampf(
			Vector2(operator.velocity.x, operator.velocity.z).length()
			/ maxf(operator.move_speed, 0.001),
			0.0,
			1.0
		)
		var stance := ComposureScript.Stance.STANDING
		if operator.posture == PlayerScript.MotionState.CROUCHED:
			stance = ComposureScript.Stance.CROUCHED
		elif operator.posture == PlayerScript.MotionState.PRONE:
			stance = ComposureScript.Stance.PRONE
		server_composure[raw_id].advance(delta, ratio, 0.0, stance)


func _broadcast_authoritative_state() -> void:
	var snapshot := {}
	for raw_id in operators:
		var operator := operators[raw_id] as SocomNetworkOperator
		snapshot[raw_id] = {
			"position": operator.global_position,
			"yaw": operator.rotation.y,
			"velocity": operator.velocity,
			"posture": operator.posture,
			"health": operator.current_health,
			"alive": operator.alive,
		}
	var packet := {
		"timestamp_ms": Time.get_ticks_msec(),
		"tick": Engine.get_physics_frames(),
		"entities": snapshot,
	}
	receive_world_state.rpc(packet, scores)


func _on_operator_eliminated(victim_peer_id: int, attacker_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if attacker_peer_id != victim_peer_id and scores.has(attacker_peer_id):
		scores[attacker_peer_id] = int(scores[attacker_peer_id]) + 1
	_refresh_scoreboard()
	if int(scores.get(attacker_peer_id, 0)) >= SCORE_LIMIT:
		_end_round(attacker_peer_id)
	else:
		_respawn_after_delay(victim_peer_id)


func _end_round(winner_peer_id: int) -> void:
	if not round_active:
		return
	round_active = false
	var message := "ROUND WON BY SEAL %d  •  resetting in 4 seconds" % winner_peer_id
	_set_status(message)
	receive_match_event.rpc(message)
	await get_tree().create_timer(4.0).timeout
	if not multiplayer.is_server():
		return
	for raw_id in scores:
		scores[raw_id] = 0
	for raw_id in operators:
		var peer_id := int(raw_id)
		var operator := operators[raw_id] as SocomNetworkOperator
		operator.respawn_at(Vector3(assigned_spawns.get(peer_id, _spawn_for_peer(peer_id))))
	round_active = true
	_set_status("NEW ROUND  •  first to %d" % SCORE_LIMIT)
	receive_match_event.rpc("NEW ROUND  •  first to %d" % SCORE_LIMIT)
	_refresh_scoreboard()


func _respawn_after_delay(peer_id: int) -> void:
	await get_tree().create_timer(RESPAWN_SECONDS).timeout
	if not multiplayer.is_server():
		return
	var operator := operators.get(peer_id) as SocomNetworkOperator
	if operator:
		operator.respawn_at(Vector3(assigned_spawns.get(peer_id, _spawn_for_peer(peer_id))))


func _present_shot(
	shooter_peer_id: int,
	origin: Vector3,
	impact: Vector3,
	hit: bool,
	message: String
) -> void:
	TracerSystemScript.spawn_tracer(
		get_tree(),
		origin,
		impact,
		Color(1.0, 0.86, 0.30),
		float(equipped_config.get("ballistics", {}).get("muzzle_velocity_mps", 715.0))
	)
	if hit:
		TracerSystemScript.spawn_impact_effect(get_tree(), impact, Vector3.UP)
	if shooter_peer_id == multiplayer.get_unique_id():
		_set_status("SHOT  •  %s" % message)


func _apply_ballistics_profile(ballistics) -> void:
	var values: Dictionary = equipped_config.get("ballistics", {})
	ballistics.fire_rate_rpm = float(values.get("fire_rate_rpm", 600.0))
	ballistics.damage_per_shot = float(values.get("damage", 34.0))
	ballistics.muzzle_velocity_mps = float(values.get("muzzle_velocity_mps", 715.0))
	ballistics.base_spread_deg = float(values.get("base_spread_deg", 0.28))
	ballistics.bloom_per_shot_deg = float(values.get("bloom_per_shot_deg", 0.32))
	ballistics.max_recoil_bloom_deg = float(values.get("max_recoil_bloom_deg", 2.4))
	ballistics.bloom_recovery_speed = float(values.get("bloom_recovery_speed", 10.0))
	ballistics.fire_interval = 60.0 / maxf(60.0, ballistics.fire_rate_rpm)


func _configured_fire_interval() -> float:
	var rpm := float(equipped_config.get("ballistics", {}).get("fire_rate_rpm", 600.0))
	return 60.0 / maxf(60.0, rpm)


func _spawn_for_peer(peer_id: int) -> Vector3:
	return spawn_points[(peer_id - 1) % spawn_points.size()]


func _spawn_for_team(team: int, member_index: int) -> Vector3:
	var team_offset := 0 if team == 0 else 8
	return spawn_points[team_offset + (member_index % 8)]


func _team_member_count(team: int) -> int:
	var count := 0
	for raw_id in operators:
		var operator := operators[raw_id] as SocomNetworkOperator
		if operator != null and operator.team_id == team:
			count += 1
	return count


func _disconnect_existing_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_clear_operators()
	session_active = false


func _build_environment() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.09, 0.11, 0.14)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.75, 0.78, 0.84)
	settings.ambient_light_energy = 0.82
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	_add_box("ArenaFloor", Vector3(22.0, 0.25, 26.0), Vector3(0.0, -0.125, -2.0), Color(0.31, 0.34, 0.38))
	_add_box("CenterCover", Vector3(7.0, 1.15, 0.7), Vector3(0.0, 0.575, -2.0), Color(0.44, 0.40, 0.35))
	_add_box("LeftCover", Vector3(0.7, 2.4, 5.0), Vector3(-5.2, 1.2, -2.0), Color(0.32, 0.36, 0.42))
	_add_box("RightCover", Vector3(0.7, 2.4, 5.0), Vector3(5.2, 1.2, -2.0), Color(0.32, 0.36, 0.42))


func _add_box(node_name: String, size: Vector3, position: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	status_label = Label.new()
	status_label.position = Vector2(20.0, 16.0)
	status_label.add_theme_font_size_override("font_size", 17)
	status_label.text = "SOCOM-141 MULTIPLAYER SLICE"
	layer.add_child(status_label)
	score_label = Label.new()
	score_label.position = Vector2(20.0, 42.0)
	score_label.add_theme_font_size_override("font_size", 16)
	layer.add_child(score_label)
	reticle = Label.new()
	reticle.text = "+"
	reticle.add_theme_font_size_override("font_size", 28)
	reticle.set_anchors_preset(Control.PRESET_CENTER)
	reticle.position = Vector2(-8.0, -18.0)
	reticle.modulate = Color(1.0, 0.92, 0.20)
	layer.add_child(reticle)
	menu_panel = PanelContainer.new()
	menu_panel.position = Vector2(20.0, 88.0)
	menu_panel.custom_minimum_size = Vector2(360.0, 0.0)
	layer.add_child(menu_panel)
	var column := VBoxContainer.new()
	menu_panel.add_child(column)
	var title := Label.new()
	title.text = "8v8 DIRECT-IP MATCH"
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)
	var explanation := Label.new()
	explanation.text = "Host one window. Join it from a second window.\nWASD move • Mouse aim • Left click fire • Esc releases mouse"
	column.add_child(explanation)
	address_edit = LineEdit.new()
	address_edit.placeholder_text = "Server address"
	address_edit.text = "127.0.0.1"
	column.add_child(address_edit)
	var row := HBoxContainer.new()
	column.add_child(row)
	var host_button := Button.new()
	host_button.text = "HOST MATCH"
	host_button.pressed.connect(func(): host_match(DEFAULT_PORT))
	row.add_child(host_button)
	var join_button := Button.new()
	join_button.text = "JOIN MATCH"
	join_button.pressed.connect(func(): join_match(address_edit.text, DEFAULT_PORT))
	row.add_child(join_button)
	var leave_button := Button.new()
	leave_button.text = "MAIN MENU"
	leave_button.pressed.connect(func():
		_disconnect_existing_peer()
		get_tree().change_scene_to_file("res://game_launcher.tscn")
	)
	column.add_child(leave_button)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_scoreboard()


func _set_status(message: String) -> void:
	if status_label:
		status_label.text = "SOCOM-141 MULTIPLAYER SLICE  •  %s" % message


func _refresh_scoreboard() -> void:
	if score_label == null:
		return
	var entries: Array[String] = []
	var ids := scores.keys()
	ids.sort()
	for raw_id in ids:
		entries.append("P%s:%s" % [raw_id, scores[raw_id]])
	score_label.text = "SCORE  " + "  •  ".join(entries)


func _ensure_input_map() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("crouch", KEY_C)
	_add_key_action("dive", KEY_Z)
	_add_key_action("peek_left", KEY_Q)
	_add_key_action("peek_right", KEY_E)
	_remove_key_binding("reset_camera", KEY_R)
	_add_key_action("reset_camera", KEY_HOME)
	_add_key_action("reload_weapon", KEY_R)
	_ensure_action("prone")
	_ensure_action("roll")
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire", 0.1)
	var has_fire := false
	for event in InputMap.action_get_events("fire"):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			has_fire = true
	if not has_fire:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", mouse)


func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)


func _remove_key_binding(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		return
	for existing_event in InputMap.action_get_events(action):
		if existing_event is InputEventKey and existing_event.physical_keycode == keycode:
			InputMap.action_erase_event(action, existing_event)


func _add_key_action(action: StringName, keycode: Key) -> void:
	_ensure_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return
	var key := InputEventKey.new()
	key.physical_keycode = keycode
	InputMap.action_add_event(action, key)


func _apply_command_line_mode() -> void:
	var args := OS.get_cmdline_user_args()
	var port := DEFAULT_PORT
	var join_address := ""
	for argument in args:
		if argument.begins_with("--mp-port="):
			port = int(argument.trim_prefix("--mp-port="))
		elif argument.begins_with("--mp-join="):
			join_address = argument.trim_prefix("--mp-join=")
	if args.has("--mp-host"):
		host_match(port)
	elif not join_address.is_empty():
		join_match(join_address, port)
	else:
		var launch_mode := String(ProjectSettings.get_setting("socom/session/launch_mode", ""))
		var launcher_address := String(ProjectSettings.get_setting("socom/session/join_address", ""))
		ProjectSettings.set_setting("socom/session/launch_mode", "")
		ProjectSettings.set_setting("socom/session/join_address", "")
		if launch_mode == "host":
			host_match(port)
		elif launch_mode == "join":
			join_match(launcher_address, port)
