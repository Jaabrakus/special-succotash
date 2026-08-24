extends SceneTree

const Profile := preload("res://scripts/tactical/tactical_grenade_profile.gd")
const SmokeCloud := preload("res://scripts/tactical/smoke_cloud.gd")
const Flashbang := preload("res://scripts/tactical/flashbang_grenade.gd")
const Frag := preload("res://scripts/tactical/frag_grenade.gd")
const Thrower := preload("res://scripts/tactical/tactical_grenade_thrower.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile := Profile.load_profile()
	var smoke_values: Dictionary = profile.get("smoke", {})
	var throw_values: Dictionary = profile.get("throw", {})
	_expect(
		float(smoke_values.get("maximum_radius", 0.0)) >= 6.5
		and int(smoke_values.get("particle_amount", 0)) >= 320
		and float(smoke_values.get("visual_opacity", 0.0)) >= 0.30,
		"saved smoke defaults are larger and denser"
	)
	_expect(
		float(throw_values.get("full_throw_charge_seconds", 9.0)) <= 0.80
		and float(throw_values.get("full_throw_playback_speed", 0.0)) >= 1.15
		and float(throw_values.get("quick_throw_playback_speed", 0.0))
			>= 2.05
		and float(throw_values.get("overhand_speed", 0.0)) >= 16.0
		and float(throw_values.get("underhand_speed", 0.0)) >= 6.4
		and float(throw_values.get("recovery_blend_seconds", 9.0)) <= 0.15,
		"saved throw profile slightly accelerates the animation and arc with bounded locomotion recovery"
	)
	var clamped := Profile.normalize({
		"smoke": {"maximum_radius": 99.0, "particle_amount": 2},
		"frag": {"maximum_damage": 9999.0},
	})
	_expect(
		is_equal_approx(float((clamped.smoke as Dictionary).maximum_radius), 12.0)
		and int((clamped.smoke as Dictionary).particle_amount) == 48
		and is_equal_approx(float((clamped.frag as Dictionary).maximum_damage), 300.0),
		"profile clamps unsafe lab values"
	)

	var arena := Node3D.new()
	root.add_child(arena)
	var cloud := SmokeCloud.new()
	cloud.configure_profile(profile)
	arena.add_child(cloud)
	var flash := Flashbang.new()
	flash.arm_on_ready = false
	flash.configure_profile(profile)
	arena.add_child(flash)
	var frag := Frag.new()
	frag.arm_on_ready = false
	frag.configure_profile(profile)
	arena.add_child(frag)
	var thrower := Thrower.new()
	thrower.configure_profile(profile)
	arena.add_child(thrower)
	await process_frame
	_expect(
		is_equal_approx(cloud.maximum_radius, float(smoke_values.maximum_radius))
		and cloud.particle_amount == int(smoke_values.particle_amount)
		and cloud.get("_particles") is GPUParticles3D
		and int((cloud.get("_particles") as GPUParticles3D).amount) == cloud.particle_amount,
		"smoke runtime consumes the shared profile"
	)
	_expect(
		is_equal_approx(flash.effective_radius, float((profile.flash as Dictionary).effective_radius))
		and is_equal_approx(frag.blast_radius, float((profile.frag as Dictionary).blast_radius))
		and is_equal_approx(frag.blast_effect_seconds, float((profile.frag as Dictionary).blast_effect_seconds))
		and frag.blast_smoke_particles == int((profile.frag as Dictionary).blast_smoke_particles)
		and is_equal_approx(frag.blast_smoke_opacity, float((profile.frag as Dictionary).blast_smoke_opacity))
		and is_equal_approx(frag.fuse_seconds, float((profile.common as Dictionary).fuse_seconds)),
		"flash, Frag damage/visuals, and common fuse consume the shared profile"
	)
	_expect(
		is_equal_approx(thrower.overhand_speed, float((profile.throw as Dictionary).overhand_speed))
		and is_equal_approx(thrower.underhand_speed, float((profile.throw as Dictionary).underhand_speed))
		and is_equal_approx(thrower.overhand_pitch_influence, float((profile.throw as Dictionary).overhand_pitch_influence))
		and is_equal_approx(thrower.underhand_pitch_influence, float((profile.throw as Dictionary).underhand_pitch_influence)),
		"throw strength consumes the shared profile"
	)
	var level_aim := Vector3.FORWARD
	var high_aim := Vector3(0.0, sin(deg_to_rad(35.0)), -cos(deg_to_rad(35.0)))
	var low_aim := Vector3(0.0, sin(deg_to_rad(-20.0)), -cos(deg_to_rad(-20.0)))
	for mode in [Thrower.ThrowMode.OVERHAND, Thrower.ThrowMode.UNDERHAND]:
		var level_velocity := thrower.calculate_launch_velocity(level_aim, Vector3.UP, mode, 1.0)
		var high_velocity := thrower.calculate_launch_velocity(high_aim, Vector3.UP, mode, 1.0)
		var low_velocity := thrower.calculate_launch_velocity(low_aim, Vector3.UP, mode, 1.0)
		_expect(
			high_velocity.y > level_velocity.y + 1.0
			and level_velocity.y > low_velocity.y + 0.5
			and is_equal_approx(high_velocity.length(), level_velocity.length()),
			"%s throw arc rises and falls with aim pitch without changing throw power"
			% ("overhand" if mode == Thrower.ThrowMode.OVERHAND else "underhand")
		)

	var lab_scene := load("res://tactical_grenade_lab.tscn") as PackedScene
	var lab := lab_scene.instantiate() if lab_scene != null else null
	_expect(lab != null, "Grenade Lab scene loads")
	if lab != null:
		root.add_child(lab)
		await process_frame
		_expect(
			lab.find_child("ThrowableTabs", true, false) != null
			and lab.find_child("SaveThrowableProfile", true, false) != null,
			"Grenade Lab exposes throwable tabs and one shared Save control"
		)
		_expect(
			lab.find_child("frag_blast_effect_seconds", true, false) is HSlider
			and lab.find_child("frag_blast_smoke_particles", true, false) is HSlider
			and lab.find_child("frag_blast_smoke_opacity", true, false) is HSlider,
			"Grenade Lab exposes the Frag radius smoke controls"
		)
		_expect(
			lab.find_child("throw_full_throw_playback_speed", true, false) is HSlider
			and lab.find_child("throw_quick_throw_playback_speed", true, false) is HSlider
			and lab.find_child("throw_recovery_blend_seconds", true, false) is HSlider,
			"Grenade Lab exposes throw animation and movement recovery timing"
		)
		var throwable_tabs := lab.find_child("ThrowableTabs", true, false) as TabContainer
		throwable_tabs.current_tab = 2
		await process_frame
		_expect(int(lab.get("selected_type")) == 2, "selecting the Frag tab also selects Frag preview throws")
		throwable_tabs.current_tab = 0
		await process_frame
		_expect(
			lab.get("operator_model") is Node3D
			and lab.get("operator_animation_player") is AnimationPlayer
			and lab.get_node_or_null("GrenadePreviewCamera") is Camera3D,
			"Grenade Lab stages the real operator animation and follow camera"
		)
		lab.call("_throw_grenade")
		await create_timer(0.50).timeout
		var preview_grenade := lab.get("active_preview_grenade") as TacticalGrenadeBase
		_expect(
			preview_grenade != null
			and String((lab.get("operator_animation_player") as AnimationPlayer).current_animation).contains("grenade"),
			"Space preview plays the throw and releases a visible grenade"
		)
		if preview_grenade != null:
			preview_grenade.detonate()
			await process_frame
			var smoke_cloud_found := false
			for child in lab.get_children():
				if child is TacticalSmokeCloud:
					smoke_cloud_found = true
					break
			_expect(smoke_cloud_found, "Smoke throw leaves a visible cloud at detonation")
		lab.queue_free()

	arena.queue_free()
	await process_frame
	if failures.is_empty():
		print("TACTICAL_GRENADE_PROFILE_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("TACTICAL_GRENADE_PROFILE_REGRESSION: %s" % failure)
	quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("GRENADE_PROFILE_CHECK PASS ", label)
	else:
		failures.append(label)
