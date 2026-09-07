extends SceneTree

class PresentationSpy extends Node:
	var reports := 0
	var impacts := 0
	func present_muzzle(_mannequin: Node, _config: Dictionary) -> void:
		pass
	func present_report(_origin: Vector3, _config: Dictionary, _exclude: Array) -> void:
		reports += 1
	func present_shot(_origin: Vector3, _impact: Vector3, _hit: bool, _message: String,
			_config: Dictionary, _exclude: Array, report: bool = true) -> void:
		if report: reports += 1
		impacts += 1

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = load("res://multiplayer_slice.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game._spawn_operator_local(1, 0, Vector3(0, 20, 0))
	game.local_operator.set_physics_process(false)
	await process_frame
	await process_frame
	var spy := PresentationSpy.new()
	game.add_child(spy)
	game.shot_presentation = spy
	var latch = game.local_operator.mannequin.production_animation.fire_upper_body_latch
	var before: int = latch.accepted_shot_count
	game.local_magazine_ammo = 20
	assert(not game.local_weapon_presentation.input_enabled and not game.local_weapon_presentation.is_processing(), "Visual controller cannot process firing input")
	var health: float = game.local_operator.current_health
	game._predict_local_shot(44)
	assert(latch.accepted_shot_count == before + 1, "Local recoil starts before the network reply")
	assert(spy.reports == 1 and spy.impacts == 0, "Local sound only, no predicted hit")
	assert(game.local_magazine_ammo == 20 and game.local_operator.current_health == health, "Prediction cannot change ammo/health")
	game._predict_local_shot(44)
	assert(spy.reports == 1, "Duplicate submission cannot play another report")
	game.receive_shot_effect(1, Vector3.ZERO, Vector3.FORWARD, false, "MISS", 44)
	assert(latch.accepted_shot_count == before + 1 and spy.reports == 1, "Server acknowledgement cannot double recoil/sound")
	assert(spy.impacts == 1 and game.local_predicted_shots.is_empty(), "Server effects remain authoritative")
	game.receive_shot_effect(1, Vector3.ZERO, Vector3.FORWARD, false, "MISS", 44)
	assert(spy.impacts == 1, "Duplicate authoritative effect is idempotent")
	game.receive_shot_effect(1, Vector3.ZERO, Vector3.FORWARD, false, "MISS", 45)
	assert(latch.accepted_shot_count == before + 2 and spy.reports == 2, "Unpredicted accepted shot still presents")
	game.free()
	print("NETWORK_SHOT_FEEDBACK PASS immediate recoil/sound, exactly-once acknowledgement, server-only impacts/ammo/health")
	quit()
