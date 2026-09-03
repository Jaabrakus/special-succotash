extends SceneTree

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapRuntime := preload("res://scripts/maps/socom_map_runtime.gd")
const SwimmingVolume := preload("res://scripts/traversal/socom_swimming_volume.gd")
const PlayerController := preload("res://scripts/player/player_controller.gd")
const TraversalContract := preload("res://scripts/traversal/socom_traversal_contract.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(&"water_volume" in MapDocument.SUPPORTED_TYPES, "water is a supported map object")
	var water_object := MapDocument.make_object(
		&"water_volume",
		Vector3(3.0, -1.5, 4.0),
		Vector3(10.0, 3.0, 8.0)
	)
	water_object["properties"]["source_id"] = "regression_pool"
	var built := MapRuntime.build_object(water_object, true)
	_expect(built is SwimmingVolume, "map runtime builds the swimming contract")
	if built is SwimmingVolume:
		var volume := built as SwimmingVolume
		root.add_child(volume)
		_expect(is_equal_approx(volume.water_surface_y(), 0.0), "water surface follows map position and offset")
		_expect(volume.collision_layer == 0 and volume.collision_mask == 1, "water detects players without blocking shots")
		_expect(volume.get_node_or_null("WaterSurface") is MeshInstance3D, "water has an editable visible surface")
		var player := PlayerController.new()
		volume._on_body_entered(player)
		_expect(player.get_traversal_mode_name() == TraversalContract.SWIMMING, "volume enters swimming")
		volume._on_body_exited(player)
		_expect(player.get_traversal_mode_name() == TraversalContract.GROUNDED, "volume exits swimming")
		player.free()
	if is_instance_valid(built):
		built.free()
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("SWIMMING_MAP_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("SWIMMING_MAP_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("SWIMMING_MAP_VOLUME_REGRESSION PASS")
		quit(0)
	else:
		print("SWIMMING_MAP_VOLUME_REGRESSION FAIL ", failures)
		quit(1)
