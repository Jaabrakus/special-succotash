extends SceneTree

const Flashbang := preload("res://scripts/tactical/flashbang_grenade.gd")
const ScreenEffects := preload("res://scripts/tactical/tactical_screen_effects.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var camera := Camera3D.new()
	camera.current = true
	arena.add_child(camera)
	var effects := ScreenEffects.new()
	arena.add_child(effects)
	effects.bind_camera(camera)
	await physics_frame

	var visible_flash := Flashbang.new()
	visible_flash.arm_on_ready = false
	visible_flash.position = Vector3(0.0, 0.0, -2.0)
	arena.add_child(visible_flash)
	await physics_frame
	visible_flash.detonate()
	var blast_visual := get_first_node_in_group("flashbang_blast_visuals")
	_expect(
		blast_visual != null
		and is_equal_approx(
			float(blast_visual.get("blast_radius")),
			visible_flash.effective_radius
		),
		"flashbang spawns a detached world visual at its configured blast radius"
	)
	_expect(
		blast_visual != null
		and blast_visual.get("bright_particles") is GPUParticles3D
		and bool((blast_visual.get("bright_particles") as GPUParticles3D).emitting),
		"flashbang shoots a one-shot bright particle burst"
	)
	_expect(
		blast_visual != null
		and blast_visual.get("smoke_particles") is GPUParticles3D
		and blast_visual.get("smoke_radius_shell") is MeshInstance3D,
		"flashbang smoke burst and shell expose the effective radius"
	)
	if blast_visual != null:
		blast_visual.set_process(false)
		blast_visual.call("_process", float(blast_visual.get("lifetime_seconds")) * 0.72)
		var radius_shell := blast_visual.get("smoke_radius_shell") as MeshInstance3D
		_expect(
			radius_shell != null
			and absf(radius_shell.scale.x - float(blast_visual.get("blast_radius"))) <= 0.01,
			"smoke shell expands to the exact configured flash radius"
		)
	_expect(
		float(effects.flash_strength) >= 0.99,
		"near visible flashbang produces a complete whiteout"
	)
	_expect(
		float(effects.flash_hold_remaining) >= 0.60,
		"complete whiteout holds before recovery begins"
	)
	var flash_material := effects.get("_flash_rect").material as ShaderMaterial
	_expect(
		flash_material != null
		and is_equal_approx(
			float(flash_material.get_shader_parameter("recovery")),
			0.0
		),
		"flash recovery shader begins fully white before opening from the center"
	)
	effects.set_process(false)
	effects.call("_process", 0.45)
	_expect(
		float(effects.flash_strength) >= 0.99,
		"whiteout remains opaque during the hold phase"
	)
	effects.call("_process", 0.40)
	effects.call("_process", 1.20)
	_expect(
		float(effects.flash_strength) > 0.45
		and float(effects.flash_recovery_progress) > 0.20
		and float(effects.flash_recovery_progress) < 0.55,
		"flash fades gradually instead of disappearing on the next moment"
	)
	await process_frame

	effects.flash_strength = 0.0
	effects.flash_peak_strength = 0.0
	effects.flash_hold_remaining = 0.0
	effects.flash_recovery_elapsed = 0.0
	effects.flash_recovery_progress = 1.0
	effects.flash_duration_weight = 0.0
	var medium_flash := Flashbang.new()
	medium_flash.arm_on_ready = false
	medium_flash.position = Vector3(0.0, 0.0, -10.0)
	arena.add_child(medium_flash)
	await physics_frame
	medium_flash.detonate()
	_expect(
		float(effects.flash_strength) >= 0.99,
		"every valid visible flash hit starts as a solid full-screen whiteout"
	)

	effects.flash_strength = 0.0
	effects.flash_peak_strength = 0.0
	effects.flash_hold_remaining = 0.0
	effects.flash_recovery_elapsed = 0.0
	effects.flash_recovery_progress = 1.0
	effects.flash_duration_weight = 0.0
	var wall := StaticBody3D.new()
	wall.position = Vector3(0.0, 0.0, -1.0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 2.0, 0.15)
	collision.shape = shape
	wall.add_child(collision)
	arena.add_child(wall)
	var blocked_flash := Flashbang.new()
	blocked_flash.arm_on_ready = false
	blocked_flash.position = Vector3(0.0, 0.0, -2.0)
	arena.add_child(blocked_flash)
	await physics_frame
	blocked_flash.detonate()
	_expect(
		float(effects.flash_strength) <= 0.001,
		"solid wall still blocks visual flash exposure"
	)

	if failures.is_empty():
		print("FLASHBANG_RUNTIME_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("FLASHBANG_RUNTIME_REGRESSION: %s" % failure)
	quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("FLASHBANG_CHECK PASS ", label)
	else:
		failures.append(label)
