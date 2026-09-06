extends "res://tools/pistol_compressed_idle_regression.gd"

## Canonical accepted-shot proof, complementing the effect pool's isolated unit
## test. Never invokes the effect synchronizer manually: GPU-backed proof must
## observe its real frame_pre_draw callback after the live animation update.
## Headless checks the real handoff and immutable ballistic/tracer snapshot, then
## exits 2 (NEEDS_DISPLAY) rather than claiming an unobserved draw passed.

const LiveEffects := preload("res://scripts/weapons/lab_leak_tracer_system.gd")
const LIVE_EFFECT_CAPTURE_PREFIX := "/private/tmp/socom-pistol-canonical-muzzle"

var effect_frames: Array[Dictionary] = []
var captured_effect_images: Array[Image] = []
var live_muzzle: Marker3D
var live_smoke: CPUParticles3D
var live_controller: Node
var accepted_shot: Dictionary = {}
var accepted_snapshot: Dictionary = {}
var tracer_vertices_at_accept := PackedVector3Array()
var tracer_index_at_accept: int = -1


func _run() -> void:
	Engine.max_fps = 60
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	active_scene = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(active_scene)
	current_scene = active_scene
	await _frames(60)
	var player := active_scene.get_node("Player") as CharacterBody3D
	live_controller = active_scene.get_node("WeaponController")
	var mannequin := player.get_node("Mannequin")
	var driver := mannequin.get("production_animation") as Node
	_expect(bool(live_controller.call("apply_authorized_weapon_pickup", MARK_23_PATH)), "canonical Mark 23 equips for muzzle proof")
	await _frames(30)
	player.set_physics_process(false)
	mannequin.set_process(false)
	driver.call("clear_fire_ready_aim")
	_expect(bool(player.call("_try_set_posture", 0)), "canonical standing stance")
	var target := player.global_position + Vector3.UP * 1.48 + _world_aim_direction(player, 0.0, 0.0) * 25.0
	driver.call("set_visual_inputs", Vector2.ZERO, &"STANDING", 0.0, 0.0, 0.0, false, 0.0,
		0.0, &"LOCOMOTION", 0.0, &"WALK", 0.0, target, Vector2.ZERO, 0.0, &"IDLE", 0.0)
	await _frames(40)
	if DisplayServer.get_name() != "headless":
		_hide_canvas_layers(active_scene)
		var debug_visualizer := active_scene.find_child("CameraBoomVisualizer", true, false) as Node3D
		if debug_visualizer != null:
			debug_visualizer.visible = false
		review_camera = Camera3D.new()
		review_camera.fov = 38.0
		review_camera.set_cull_mask_value(20, false)
		active_scene.add_child(review_camera)
		_aim_review_camera(review_camera, driver, player)
		review_camera.make_current()
		await _frames(4)
	live_muzzle = mannequin.call("get_active_muzzle_marker") as Marker3D
	var muzzle_before := live_muzzle.global_position
	var smoke_index := LiveEffects._muzzle_smoke_index
	tracer_index_at_accept = LiveEffects._tracer_index
	await _await_ballistics_ready(live_controller)
	accepted_shot = live_controller.call("request_fire")
	accepted_snapshot = accepted_shot.duplicate(true)
	_expect(bool(accepted_shot.get("fired", false)), "real canonical shot accepted")
	if not bool(accepted_shot.get("fired", false)):
		_finish_effect_proof(false)
		return
	_expect(Vector3(accepted_shot.get("origin", Vector3.INF)).distance_to(muzzle_before) <= 0.0001,
		"authoritative origin is the actual trigger-time muzzle snapshot")
	_expect(LiveEffects._presented_muzzle_effects.size() == 1, "canonical shot queues exactly one presented muzzle effect")
	if LiveEffects._presented_muzzle_effects.size() != 1:
		_finish_effect_proof(false)
		return
	var entry: Dictionary = LiveEffects._presented_muzzle_effects[0]
	live_smoke = LiveEffects._muzzle_smoke_pool[smoke_index]
	_expect((entry["source"] as WeakRef).get_ref() == live_muzzle and entry.get("smoke") == live_smoke,
		"queued source is the real equipped muzzle and pooled emitter")
	_expect(int(entry.get("started_usec", 0)) == -1, "effect is queued until the presented draw")
	_expect(RenderingServer.frame_pre_draw.is_connected(LiveEffects._sync_presented_muzzle_effects),
		"canonical runtime connected real pre-draw synchronization")
	tracer_vertices_at_accept = _tracer_vertices()
	_expect(tracer_vertices_at_accept.size() == 2
		and tracer_vertices_at_accept[0].distance_to(Vector3(accepted_snapshot["origin"])) <= 0.0001
		and tracer_vertices_at_accept[1].distance_to(Vector3(accepted_snapshot["hit_pos"])) <= 0.0001,
		"real tracer starts and ends at accepted world-shot coordinates")
	# The runtime signal was connected during request_fire. Connecting this
	# observer afterward samples the completed sync, not a hand-invoked mock.
	RenderingServer.frame_pre_draw.connect(_observe_effect_pre_draw)
	for _frame in range(3):
		await _frames(1)
		if capture_enabled and DisplayServer.get_name() != "headless":
			captured_effect_images.append(root.get_texture().get_image())
	RenderingServer.frame_pre_draw.disconnect(_observe_effect_pre_draw)
	_expect(accepted_shot == accepted_snapshot and (live_controller.get("last_result") as Dictionary) == accepted_snapshot,
		"presentation frames never mutate the authoritative shot result")
	_expect(_tracer_vertices() == tracer_vertices_at_accept, "presented muzzle motion never moves the authoritative tracer")
	if DisplayServer.get_name() == "headless":
		_expect(effect_frames.is_empty(), "headless did not fabricate render synchronization")
		print("PISTOL_CANONICAL_MUZZLE_EFFECT HEADLESS_CONTRACT_CHECKED; NEEDS_DISPLAY for actual pre-draw effect proof")
		_finish_effect_proof(true)
		return
	_expect(effect_frames.size() == 3, "observed all first three real presented shot frames")
	var maximum_muzzle_displacement := 0.0
	for index in effect_frames.size():
		var sample: Dictionary = effect_frames[index]
		print("PISTOL_CANONICAL_MUZZLE_EFFECT_FRAME ", JSON.stringify(sample))
		_expect(float(sample["emitter_error_m"]) <= 0.001 and float(sample["smoke_direction_error"]) <= 0.001,
			"shot frame %d smoke emission starts on the presented muzzle" % (index + 1))
		if bool(sample["light_active"]):
			_expect(float(sample["light_error_m"]) <= 0.001, "shot frame %d active flash light stays on muzzle" % (index + 1))
		maximum_muzzle_displacement = maxf(maximum_muzzle_displacement, float(sample["from_accepted_origin_m"]))
	_expect(not effect_frames.is_empty() and bool(effect_frames[0]["light_active"]), "first displayed frame contains the actual flash light")
	_expect(maximum_muzzle_displacement > 0.005, "proof covers real pose-driven muzzle motion, not a stationary fake marker")
	for index in captured_effect_images.size():
		var image: Image = captured_effect_images[index]
		_expect(image != null and not image.is_empty() and image.save_png("%s-shot-%02d.png" % [LIVE_EFFECT_CAPTURE_PREFIX, index + 1]) == OK,
			"first shot frame %d captured after draw" % (index + 1))
	_finish_effect_proof(false)


func _observe_effect_pre_draw() -> void:
	if review_camera != null:
		review_camera.make_current()
	if effect_frames.size() >= 3 or not is_instance_valid(live_smoke):
		return
	var expected_direction := -live_muzzle.global_basis.z.normalized() + Vector3(0.0, 0.12, 0.0)
	effect_frames.append({
		"frame": effect_frames.size() + 1,
		"process_frame": Engine.get_process_frames(),
		"muzzle": str(live_muzzle.global_position),
		"emitter": str(live_smoke.global_position),
		"emitter_error_m": live_smoke.global_position.distance_to(live_muzzle.global_position),
		"smoke_direction_error": live_smoke.direction.distance_to(expected_direction),
		"light_active": LiveEffects._muzzle_flash_light.light_energy > 0.01,
		"light_error_m": LiveEffects._muzzle_flash_light.global_position.distance_to(live_muzzle.global_position),
		"from_accepted_origin_m": live_muzzle.global_position.distance_to(Vector3(accepted_snapshot["origin"])),
	})


func _tracer_vertices() -> PackedVector3Array:
	var mesh := LiveEffects._tracer_pool[tracer_index_at_accept].mesh
	if mesh.get_surface_count() != 1:
		return PackedVector3Array()
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _finish_effect_proof(needs_display: bool) -> void:
	if RenderingServer.frame_pre_draw.is_connected(_observe_effect_pre_draw):
		RenderingServer.frame_pre_draw.disconnect(_observe_effect_pre_draw)
	# The test ends before the smoke lifetime. Release its pending weak-ref
	# bookkeeping without pretending the headless process rendered a frame.
	LiveEffects._presented_muzzle_effects.clear()
	LiveEffects._disconnect_presented_muzzle_sync()
	active_scene.queue_free()
	if failures.is_empty():
		if needs_display:
			print("PISTOL_CANONICAL_MUZZLE_EFFECT_VISUAL_CHECK NEEDS_DISPLAY")
			quit(2)
		else:
			print("PISTOL_CANONICAL_MUZZLE_EFFECT_VISUAL_CHECK PASS")
			quit(0)
	else:
		print("PISTOL_CANONICAL_MUZZLE_EFFECT_VISUAL_CHECK FAIL ", failures)
		quit(1)
