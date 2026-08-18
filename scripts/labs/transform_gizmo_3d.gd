class_name SocomTransformGizmo3D
extends Node3D

## Reusable compact XYZ translation + rotation control used by Studio tools.
## It owns presentation and screen-space hit testing only. The host decides
## what a handle means, which lets Pose Mode preserve anatomical bone lengths.

const PICK_RADIUS_PX := 15.0
const ARROW_LENGTH := 0.18
const RING_RADIUS := 0.145

var _handles: Dictionary = {}
var _hovered: StringName = &""


func _ready() -> void:
	_build()


func set_hovered(handle_id: StringName) -> void:
	if _hovered == handle_id:
		return
	_hovered = handle_id
	for raw_id in _handles.keys():
		var handle_id_key := StringName(raw_id)
		var entry: Dictionary = _handles[handle_id_key]
		var visual: Node3D = entry["visual"]
		var material: StandardMaterial3D = entry["material"]
		var selected := handle_id_key == _hovered
		visual.scale = Vector3.ONE * (1.28 if selected else 1.0)
		material.albedo_color = Color.WHITE if selected else entry["color"]


func pick(camera: Camera3D, screen_position: Vector2) -> StringName:
	if not visible or camera == null:
		return &""
	var closest := PICK_RADIUS_PX
	var result: StringName = &""
	for raw_id in _handles.keys():
		var handle_id := StringName(raw_id)
		var distance := _handle_screen_distance(camera, screen_position, handle_id)
		if distance < closest:
			closest = distance
			result = handle_id
	return result


func is_translation(handle_id: StringName) -> bool:
	return String(handle_id).begins_with("move_")


func is_rotation(handle_id: StringName) -> bool:
	return String(handle_id).begins_with("rot_")


func axis_name(handle_id: StringName) -> StringName:
	return StringName(String(handle_id).get_slice("_", 1))


func _build() -> void:
	if not _handles.is_empty():
		return
	_add_arrow(&"move_x", Color(1.0, 0.22, 0.22), Vector3.RIGHT)
	_add_arrow(&"move_y", Color(0.25, 1.0, 0.32), Vector3.UP)
	_add_arrow(&"move_z", Color(0.28, 0.62, 1.0), Vector3.BACK)
	_add_ring(&"rot_x", Color(1.0, 0.88, 0.18), Vector3.RIGHT)
	_add_ring(&"rot_y", Color(0.15, 0.85, 1.0), Vector3.UP)
	_add_ring(&"rot_z", Color(1.0, 0.28, 0.88), Vector3.BACK)


func _add_arrow(handle_id: StringName, color: Color, direction: Vector3) -> void:
	var root := Node3D.new()
	root.name = String(handle_id)
	var material := _gizmo_material(color)

	var shaft := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.006
	cylinder.bottom_radius = 0.006
	cylinder.height = ARROW_LENGTH
	shaft.mesh = cylinder
	shaft.position = Vector3(0.0, ARROW_LENGTH * 0.5, 0.0)
	shaft.material_override = material
	root.add_child(shaft)

	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.018
	cone.height = 0.045
	head.mesh = cone
	head.position = Vector3(0.0, ARROW_LENGTH + 0.0225, 0.0)
	head.material_override = material
	root.add_child(head)

	if direction.is_equal_approx(Vector3.RIGHT):
		root.rotation_degrees.z = -90.0
	elif direction.is_equal_approx(Vector3.BACK):
		root.rotation_degrees.x = 90.0
	add_child(root)
	_handles[handle_id] = {
		"visual": root,
		"material": material,
		"color": color,
		"kind": &"arrow",
		"direction": direction,
	}


func _add_ring(handle_id: StringName, color: Color, normal: Vector3) -> void:
	var ring := MeshInstance3D.new()
	ring.name = String(handle_id)
	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS - 0.008
	torus.outer_radius = RING_RADIUS + 0.008
	torus.rings = 40
	torus.ring_segments = 12
	ring.mesh = torus
	var material := _gizmo_material(color)
	ring.material_override = material
	if normal.is_equal_approx(Vector3.RIGHT):
		ring.rotation_degrees.z = 90.0
	elif normal.is_equal_approx(Vector3.BACK):
		ring.rotation_degrees.x = 90.0
	add_child(ring)
	_handles[handle_id] = {
		"visual": ring,
		"material": material,
		"color": color,
		"kind": &"ring",
		"normal": normal,
	}


func _gizmo_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.render_priority = 110
	return material


func _handle_screen_distance(
	camera: Camera3D,
	screen_position: Vector2,
	handle_id: StringName
) -> float:
	var entry: Dictionary = _handles[handle_id]
	if entry["kind"] == &"ring":
		return _ring_distance(camera, screen_position, entry["normal"])
	var direction: Vector3 = entry["direction"]
	var world_direction := global_basis * direction
	var start := global_position
	var finish := start + world_direction.normalized() * (ARROW_LENGTH + 0.03)
	if camera.is_position_behind(start) or camera.is_position_behind(finish):
		return INF
	return _point_segment_distance(
		screen_position,
		camera.unproject_position(start),
		camera.unproject_position(finish)
	)


func _ring_distance(
	camera: Camera3D,
	screen_position: Vector2,
	normal: Vector3
) -> float:
	var axis_a := global_basis.y
	var axis_b := global_basis.z
	if normal.is_equal_approx(Vector3.UP):
		axis_a = global_basis.x
		axis_b = global_basis.z
	elif normal.is_equal_approx(Vector3.BACK):
		axis_a = global_basis.x
		axis_b = global_basis.y
	var best := INF
	for point_index in range(40):
		var angle := TAU * float(point_index) / 40.0
		var world_point := global_position + (
			axis_a * cos(angle) + axis_b * sin(angle)
		) * RING_RADIUS
		if not camera.is_position_behind(world_point):
			best = minf(
				best,
				screen_position.distance_to(camera.unproject_position(world_point))
			)
	return best


func _point_segment_distance(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(start)
	var amount := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * amount)
