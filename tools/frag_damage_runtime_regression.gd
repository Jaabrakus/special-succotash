extends SceneTree

const FragGrenade := preload("res://scripts/tactical/frag_grenade.gd")
const PlayerController := preload("res://scripts/player/player_controller.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var near_player := _build_player(arena, Vector3(0.0, 0.0, -1.0), "NearPlayer")
	var far_player := _build_player(arena, Vector3(-4.0, 0.0, -3.0), "FarPlayer")
	var protected_player := _build_player(
		arena,
		Vector3(3.0, 0.0, 0.0),
		"ProtectedPlayer"
	)
	var wall := StaticBody3D.new()
	wall.position = Vector3(1.5, 0.9, 0.0)
	var wall_collision := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(0.18, 2.4, 2.4)
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	arena.add_child(wall)

	var grenade := FragGrenade.new()
	grenade.arm_on_ready = false
	grenade.position = Vector3.ZERO
	arena.add_child(grenade)
	await physics_frame
	grenade.call("_apply_blast_gameplay")

	var near_damage := 100.0 - float(near_player.current_health)
	var far_damage := 100.0 - float(far_player.current_health)
	var protected_damage := 100.0 - float(protected_player.current_health)
	_expect(near_damage > far_damage and far_damage > 0.0, "near Frag damage exceeds far damage")
	_expect(protected_damage <= 0.001, "solid wall blocks Frag health damage")
	_expect(near_damage <= grenade.maximum_damage + 0.001, "Frag damage never exceeds its configured maximum")

	grenade.call("_spawn_blast_visual")
	var blast_visual := get_first_node_in_group("frag_blast_visuals")
	_expect(
		blast_visual != null
		and is_equal_approx(float(blast_visual.get("blast_radius")), grenade.blast_radius),
		"Frag detonation visual uses the exact authoritative damage radius"
	)
	_expect(
		blast_visual != null
		and blast_visual.get("spark_particles") is GPUParticles3D
		and blast_visual.get("smoke_particles") is GPUParticles3D
		and bool((blast_visual.get("smoke_particles") as GPUParticles3D).emitting),
		"Frag detonation emits visible sparks and fast smoke particles"
	)
	if blast_visual != null:
		var smoke_particles := blast_visual.get("smoke_particles") as GPUParticles3D
		var smoke_process := smoke_particles.process_material as ParticleProcessMaterial
		_expect(
			smoke_process.initial_velocity_max * smoke_particles.lifetime
			<= grenade.blast_radius - 0.05,
			"Frag smoke particles cannot overshoot the damage radius"
		)
		blast_visual.set_process(false)
		blast_visual.call("_process", float(blast_visual.get("lifetime_seconds")) * 0.46)
		var radius_shell := blast_visual.get("smoke_radius_shell") as MeshInstance3D
		_expect(
			radius_shell != null
			and absf(radius_shell.scale.x - grenade.blast_radius) <= 0.01,
			"Frag smoke shell rapidly expands to the complete blast radius"
		)
		blast_visual.call("_process", float(blast_visual.get("lifetime_seconds")) * 0.54)
		_expect(blast_visual.is_queued_for_deletion(), "Frag blast visual disappears quickly")

	if failures.is_empty():
		print(
			"FRAG_DAMAGE_RUNTIME_REGRESSION PASS near=%.2f far=%.2f protected=%.2f"
			% [near_damage, far_damage, protected_damage]
		)
		quit(0)
		return
	for failure in failures:
		push_error("FRAG_DAMAGE_RUNTIME_REGRESSION: %s" % failure)
	quit(1)


func _build_player(parent: Node3D, location: Vector3, label: String) -> CharacterBody3D:
	var player := PlayerController.new()
	player.name = label
	player.position = location
	player.replay_override_active = true
	var collision := CollisionShape3D.new()
	collision.position = Vector3.UP * 0.9
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.8
	collision.shape = shape
	player.add_child(collision)
	parent.add_child(player)
	return player


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("FRAG_DAMAGE_CHECK PASS ", label)
	else:
		failures.append(label)
