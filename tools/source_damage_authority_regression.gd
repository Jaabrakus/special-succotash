extends SceneTree

const NetworkOperator := preload("res://scripts/network/socom_network_operator.gd")
const Policy := preload("res://scripts/weapons/source_firearm_policy.gd")
const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")

# Original 3c7600 -> 5a5830 -> 5a54d0/5a56d0, three M4A1 body hits,
# executed with source_damage_equation_audit.cjs and pinned decoded modules.
const M4_HEALTH_RATIOS := [0.6687629222869873, 0.283853143453598, 0.0]
const M4_BODY_POOLS := [31.10000228881836, 9.137504577636719, 0.0]
var checks := 0
var failures: Array[String] = []
var combat: Dictionary

class CheapTrainingTarget extends LabLeakTargetDummy:
	# Production damage, death and timer-respawn methods remain untouched.
	func _build_soldier() -> void:
		model_root = Node3D.new()
		add_child(model_root)
	func _build_hitboxes() -> void:
		pass


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var saved: Dictionary = WeaponContract.load_config("res://config/weapons/m4a1.json")
	var resolved: Dictionary = Policy.resolve(saved)
	_expect(resolved.get("damage_model") == Policy.DAMAGE_MODEL, "trusted M4 uses source damage")
	if not resolved.has("combat"):
		_finish()
		return
	combat = resolved.combat.duplicate(true)
	combat["distance_m"] = 0.0
	_expect(root.multiplayer.is_server(), "offline test root is authority")
	var server := _network(root)
	server.network_peer_id = 17
	var kills: Array = []
	server.eliminated.connect(func(victim: int, attacker: int) -> void: kills.append([victim, attacker]))
	for index in range(3):
		var hit: Dictionary = server.take_source_bullet_damage(combat, &"TORSO", 4)
		_expect(hit.accepted, "authoritative source body hit accepted")
		_float_equal(server.current_health, 100.0 * M4_HEALTH_RATIOS[index], "network original weighted body health")
		_float_equal(server.source_health.snapshot().health.body, M4_BODY_POOLS[index], "network original body pool")
		_expect(server.alive == (index < 2), "network original body death timing")
	_expect(kills == [[17, 4]], "one authoritative elimination with victim/attacker")
	_expect(not server.take_source_bullet_damage(combat, &"HEAD", 4).accepted, "dead source hit rejected")
	_expect(kills.size() == 1, "no duplicate elimination")
	server.respawn_at(Vector3(3.0, 0.0, 2.0))
	_expect(server.source_health == null and server.current_health == server.max_health and server.alive, "network respawn discards previous pools")
	server.take_source_bullet_damage(combat, &"TORSO", 4)
	_float_equal(server.current_health, 100.0 * M4_HEALTH_RATIOS[0], "network respawn restores fresh original armor/health")
	server.respawn_at(Vector3.ZERO)
	var head: Dictionary = server.take_source_bullet_damage(combat, &"HEAD", 4)
	_expect(head.accepted and head.eliminated and not server.alive, "source eight-HP head one-hit through network owner")
	server.respawn_at(Vector3.ZERO)
	server.take_explosion_damage(30.0, Vector3.ZERO, 4)
	_expect(server.source_health == null and server.current_health == 70.0, "legacy-first remains lazy source state")
	server.take_source_bullet_damage(combat, &"RIGHT_UPPER_ARM", 4)
	_expect(server.current_health <= 70.0, "initializing source state cannot heal earlier explosion")
	var before: float = server.current_health
	server.take_bullet_damage_region(4.0, &"TORSO", Vector3.ZERO, Vector3.UP, Vector3.ZERO, 4)
	_expect(server.current_health < before, "legacy after source damage reduces displayed health")
	before = server.current_health
	server.take_source_bullet_damage(combat, &"LEFT_CALF", 4)
	_expect(server.current_health <= before, "next source shot cannot restore pre-legacy health")
	server.take_explosion_damage(1000.0, Vector3.ZERO, 4)
	_expect(not server.alive and not server.source_health.alive, "legacy death closes existing source pools")
	server.respawn_at(Vector3.ZERO)
	_invalid_source_fresh(server, "network fresh")
	for region: StringName in [&"UNKNOWN", &"HAND", &"head"]:
		var rejected: Dictionary = server.take_source_bullet_damage(combat, region, 4)
		_expect(not rejected.accepted and server.current_health == 100.0, "unknown source region fails closed")
	var bad: Dictionary = combat.duplicate(true)
	bad["distance_m"] = INF
	_expect(not server.take_source_bullet_damage(bad, &"TORSO", 4).accepted, "nonfinite source distance rejected by real receiver")
	_expect(server.current_health == 100.0, "rejected input leaves authoritative health unchanged")
	_invalid_source_preserves_pools(server, "network")

	# A dedicated local client branch tests production multiplayer.is_server guard.
	var client_space := Node3D.new()
	client_space.name = "NonAuthorityBranch"
	root.add_child(client_space)
	var client_api := SceneMultiplayer.new()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client("127.0.0.1", 57423)
	_expect(error == OK, "local non-authority peer initialized")
	if error == OK:
		client_api.multiplayer_peer = peer
		set_multiplayer(client_api, client_space.get_path())
		var client := _network(client_space)
		client.is_proxy_replica = true
		_expect(not client.multiplayer.is_server(), "client branch is not server")
		_expect(not client.take_source_bullet_damage(combat, &"HEAD", 4).accepted, "client cannot apply source shot damage")
		_expect(not client.take_bullet_damage_region(200.0, &"HEAD", Vector3.ZERO, Vector3.UP).accepted, "client cannot apply legacy shot damage")
		_expect(not client.take_explosion_damage(200.0, Vector3.ZERO).accepted, "client cannot apply explosion damage")
		_expect(client.current_health == 100.0 and client.source_health == null, "client damage calls have zero pool mutation")
		client.push_network_snapshot(Vector3(2.0, 0.0, 0.0), 0.0, Vector3.ZERO, 0, 37.0, true, 1.0)
		client.update_proxy_interpolation(1.5)
		_expect(client.current_health == 37.0 and client.source_health == null, "replica health snapshot never creates authoritative source pools")
		client.set_authoritative_snapshot(Vector3.ZERO, 0.0, Vector3.ZERO, 0, 100.0, true, true, -1, 1)
		_expect(client.current_health == 100.0 and client.source_health == null, "replicated fresh-life snapshot remains presentation-only pools")
		peer.close()

	var training := CheapTrainingTarget.new()
	root.add_child(training)
	training.set_process(false)
	_invalid_source_fresh(training, "training fresh")
	training.take_explosion_damage(20.0, Vector3.ZERO)
	_expect(training.current_health == 80.0 and training.source_health == null, "training legacy-first damage preserved")
	training.take_source_bullet_damage(combat, &"RIGHT_THIGH")
	_expect(training.current_health <= 80.0, "training initial source hit cannot heal legacy damage")
	before = training.current_health
	training.take_bullet_damage_region(4.0, &"TORSO", Vector3.ZERO, Vector3.UP, Vector3.ZERO, 3.5, false)
	_expect(training.current_health < before, "training legacy damage after source decreases health")
	before = training.current_health
	training.take_source_bullet_damage(combat, &"LEFT_UPPER_ARM")
	_expect(training.current_health <= before, "training next source cannot heal")
	head = training.take_source_bullet_damage(combat, &"HEAD")
	_expect(head.eliminated and not training.is_alive and not training.source_health.alive, "training original head one-hit")
	await create_timer(2.7).timeout
	_expect(training.is_alive and training.current_health == training.max_health and training.source_health == null, "production training respawn timer clears source pools")
	training.take_source_bullet_damage(combat, &"TORSO")
	_float_equal(training.current_health, 100.0 * M4_HEALTH_RATIOS[0], "training respawn restores original fresh health and armor")
	_invalid_source_preserves_pools(training, "training")
	training.free()
	client_space.free()
	server.free()
	_finish()


func _network(parent: Node) -> SocomNetworkOperator:
	var result := NetworkOperator.new()
	result.visual_runtime_enabled = false
	parent.add_child(result)
	result.set_physics_process(false)
	result.set_process(false)
	return result


func _invalid_source_preserves_pools(receiver: Node, label: String) -> void:
	# Ensure this is the existing-pool branch, not only rejection before allocation.
	if receiver.source_health == null:
		receiver.take_source_bullet_damage(combat, &"RIGHT_UPPER_ARM", 4)
	var before_hp: float = receiver.current_health
	var before_pools: Dictionary = receiver.source_health.snapshot()
	for field in ["impact_damage", "damage_modifier", "piercing", "effective_range_m", "maximum_range_m", "distance_m", "pellet_count"]:
		for bad_value in [NAN, INF, -INF]:
			var bad: Dictionary = combat.duplicate(true)
			bad[field] = bad_value
			var result: Dictionary = receiver.take_source_bullet_damage(bad, &"TORSO", 4)
			_expect(not result.accepted, label + " rejects " + field + " nonfinite")
			_expect(receiver.current_health == before_hp and receiver.source_health.snapshot() == before_pools,
				label + " invalid input cannot mutate health OR armor")
	var unknown: Dictionary = receiver.take_source_bullet_damage(combat, &"NOT_A_REGION", 4)
	_expect(not unknown.accepted, label + " unknown region rejects")
	_expect(receiver.current_health == before_hp and receiver.source_health.snapshot() == before_pools,
		label + " unknown region cannot mutate health OR armor")
	for bad_value in ["", "0", "nan", {}, [], -1.0]:
		var bad: Dictionary = combat.duplicate(true)
		bad["distance_m"] = bad_value
		_expect(not receiver.take_source_bullet_damage(bad, &"TORSO", 4).accepted, label + " malformed distance rejects")
		_expect(receiver.current_health == before_hp and receiver.source_health.snapshot() == before_pools,
			label + " malformed distance cannot mutate existing pools")


func _invalid_source_fresh(receiver: Node, label: String) -> void:
	var before_hp: float = receiver.current_health
	_expect(receiver.source_health == null, label + " no initial pools")
	for bad_value in ["", "0", "nan", {}, [], -1.0, NAN, INF, -INF]:
		var bad: Dictionary = combat.duplicate(true)
		bad["distance_m"] = bad_value
		_expect(not receiver.take_source_bullet_damage(bad, &"TORSO", 4).accepted, label + " malformed distance rejects")
		_expect(receiver.current_health == before_hp and receiver.source_health == null,
			label + " rejected shot does not allocate pools")
	_expect(not receiver.take_source_bullet_damage(combat, &"NOT_A_REGION", 4).accepted, label + " invalid region rejects")
	_expect(receiver.current_health == before_hp and receiver.source_health == null,
		label + " invalid region does not allocate pools")


func _float_equal(actual: float, expected: float, label: String) -> void:
	_expect(absf(actual - expected) <= 0.00001, "%s actual=%s expected=%s" % [label, actual, expected])


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("SOURCE_AUTHORITY_FAIL " + label)


func _finish() -> void:
	print("SOURCE_DAMAGE_AUTHORITY_REGRESSION %s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
