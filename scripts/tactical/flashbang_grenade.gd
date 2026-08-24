class_name TacticalFlashbangGrenade
extends TacticalGrenadeBase

const BlastVisual := preload("res://scripts/tactical/flashbang_blast_visual.gd")
const RuntimeAudio := preload("res://scripts/audio/lab_leak_audio_engine.gd")

@export var effective_radius := 18.0
@export var intensity_multiplier := 1.0


func _apply_type_profile(profile: Dictionary) -> void:
	var values: Dictionary = profile.get("flash", {})
	effective_radius = float(values.get("effective_radius", effective_radius))
	intensity_multiplier = float(values.get("intensity_multiplier", intensity_multiplier))


static func calculate_exposure(
	detonation_position: Vector3,
	viewer_position: Vector3,
	viewer_forward: Vector3,
	has_line_of_sight: bool,
	radius := 18.0
) -> float:
	if not has_line_of_sight:
		return 0.0
	var to_flash := detonation_position - viewer_position
	var distance_falloff := clampf(1.0 - to_flash.length() / radius, 0.0, 1.0)
	if distance_falloff <= 0.0:
		return 0.0
	var facing := clampf(viewer_forward.normalized().dot(to_flash.normalized()), -1.0, 1.0)
	var angle_weight := lerpf(0.14, 1.0, smoothstep(-0.25, 0.85, facing))
	return distance_falloff * distance_falloff * angle_weight


func _on_detonated() -> void:
	RuntimeAudio.play_grenade_detonation(get_tree(), global_position, &"flash")
	_spawn_blast_visual()
	for node in get_tree().get_nodes_in_group("tactical_screen_effects"):
		if node.has_method("apply_flash_from_world"):
			node.call(
				"apply_flash_from_world",
				global_position,
				effective_radius,
				get_rid(),
				intensity_multiplier
			)
	queue_free()


func _spawn_blast_visual() -> void:
	var visual := BlastVisual.new()
	visual.configure(effective_radius)
	var visual_parent := get_parent()
	if visual_parent == null:
		return
	visual_parent.add_child(visual)
	visual.global_position = global_position
