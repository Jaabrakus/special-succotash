class_name TacticalScreenEffects
extends CanvasLayer

const FoleyEngine := preload("res://scripts/audio/tactical_foley_engine.gd")
const FlashbangScript := preload("res://scripts/tactical/flashbang_grenade.gd")

var camera: Camera3D
var flash_strength := 0.0
var smoke_strength := 0.0
var shake_strength := 0.0
var _flash_rect: ColorRect
var _smoke_rect: ColorRect
var _foley: Node
var _master_bus_original_db := 0.0
var _base_h_offset := 0.0
var _base_v_offset := 0.0


func _ready() -> void:
	add_to_group("tactical_screen_effects")
	layer = 95
	_flash_rect = _make_overlay(Color.WHITE)
	_smoke_rect = _make_overlay(Color(0.40, 0.43, 0.40, 1.0))
	_foley = FoleyEngine.new()
	add_child(_foley)
	_master_bus_original_db = AudioServer.get_bus_volume_db(0)


func bind_camera(target: Camera3D) -> void:
	camera = target
	if camera != null:
		_base_h_offset = camera.h_offset
		_base_v_offset = camera.v_offset


func _exit_tree() -> void:
	AudioServer.set_bus_volume_db(0, _master_bus_original_db)
	if camera != null:
		camera.h_offset = _base_h_offset
		camera.v_offset = _base_v_offset


func _process(delta: float) -> void:
	flash_strength = move_toward(flash_strength, 0.0, delta * lerpf(0.18, 0.72, 1.0 - flash_strength))
	if camera != null:
		var manager := get_node_or_null("/root/TacticalOcclusionManager")
		var target_density := float(manager.call("get_density_at", camera.global_position)) if manager else 0.0
		smoke_strength = move_toward(smoke_strength, target_density, delta * 3.5)
	_flash_rect.color.a = flash_strength
	_smoke_rect.color.a = smoke_strength * 0.86
	AudioServer.set_bus_volume_db(0, _master_bus_original_db - flash_strength * 12.0)
	if camera != null:
		shake_strength = move_toward(shake_strength, 0.0, delta * 2.8)
		camera.h_offset = _base_h_offset + randf_range(-0.025, 0.025) * shake_strength
		camera.v_offset = _base_v_offset + randf_range(-0.018, 0.018) * shake_strength


func apply_flash_from_world(position: Vector3, radius: float) -> void:
	if camera == null:
		return
	var has_los := _has_line_of_sight(camera.global_position, position)
	var exposure: float = FlashbangScript.calculate_exposure(
		position, camera.global_position, -camera.global_basis.z, has_los, radius
	)
	flash_strength = maxf(flash_strength, exposure)
	if exposure > 0.08:
		_foley.call("play_cue", &"tinnitus", camera.global_position, linear_to_db(exposure), 1.0)


func apply_explosion_shake(position: Vector3, radius: float) -> void:
	if camera != null:
		shake_strength = maxf(shake_strength, clampf(1.0 - camera.global_position.distance_to(position) / radius, 0.0, 1.0))


func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	if camera == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [camera]
	return camera.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _make_overlay(base_color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(base_color, 0.0)
	add_child(rect)
	return rect
