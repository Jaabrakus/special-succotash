class_name GunsmithBallisticsView
extends RefCounted

const BULLET_VELOCITY_PREVIEW_SECONDS := 0.004


static func calculate_barrel_axis_local(muzzle_local: Vector3, barrel_base_local: Vector3) -> Vector3:
	var axis := muzzle_local - barrel_base_local
	if axis.length_squared() <= 0.000001:
		return Vector3.FORWARD
	return axis.normalized()


static func calculate_barrel_direction_world(socket_root: Node3D, muzzle_local: Vector3, barrel_base_local: Vector3) -> Vector3:
	if socket_root == null:
		return Vector3.FORWARD
	var clean_basis: Basis = socket_root.global_basis.orthonormalized()
	return (clean_basis * calculate_barrel_axis_local(muzzle_local, barrel_base_local)).normalized()


static func calculate_reticle_screen_position(
	cam: Camera3D,
	socket_root: Node3D,
	muzzle_local: Vector3,
	barrel_base_local: Vector3,
	fallback_center: Vector2,
	lead_pixels: float = 64.0
) -> Vector2:
	if cam == null or socket_root == null:
		return fallback_center
	var barrel_base_world: Vector3 = socket_root.to_global(barrel_base_local)
	var muzzle_world: Vector3 = socket_root.to_global(muzzle_local)
	var dir := calculate_barrel_direction_world(socket_root, muzzle_local, barrel_base_local)
	var trajectory_world := muzzle_world + dir * 100.0
	if cam.is_position_behind(trajectory_world):
		return fallback_center
	var barrel_base_screen := cam.unproject_position(barrel_base_world)
	var muzzle_screen := cam.unproject_position(muzzle_world)
	var projected_axis := muzzle_screen - barrel_base_screen
	if projected_axis.length_squared() <= 0.000001:
		var far_screen := cam.unproject_position(trajectory_world)
		projected_axis = far_screen - muzzle_screen
	if projected_axis.length_squared() <= 0.000001:
		return fallback_center
	return muzzle_screen + projected_axis.normalized() * maxf(lead_pixels, 0.0)


static func build_debug_mesh(
	mesh: ImmediateMesh,
	material: Material,
	show_velocity: bool,
	show_barrel_axis: bool,
	show_camera_aim: bool,
	show_last_shot: bool,
	socket_root: Node3D,
	muzzle_marker: Node3D,
	barrel_base_marker: Node3D,
	muzzle_local: Vector3,
	barrel_base_local: Vector3,
	muzzle_velocity: float,
	cam: Camera3D,
	camera_aim_target: Vector3,
	last_shot_origin: Vector3,
	last_shot_end: Vector3
) -> void:
	mesh.clear_surfaces()
	if not show_velocity and not show_barrel_axis and not show_camera_aim and not show_last_shot:
		return
	if socket_root == null:
		return

	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)

	var dir := calculate_barrel_direction_world(socket_root, muzzle_local, barrel_base_local)

	if show_velocity and muzzle_marker:
		var start := muzzle_marker.global_position
		var finish := start + dir * (muzzle_velocity * BULLET_VELOCITY_PREVIEW_SECONDS)
		_add_segment(mesh, start, finish, Color(0.15, 1.0, 0.18))

	if show_barrel_axis and muzzle_marker and barrel_base_marker:
		var start := barrel_base_marker.global_position
		var finish := muzzle_marker.global_position + dir * 5.0
		_add_segment(mesh, start, finish, Color(1.0, 0.12, 0.08))

	if show_camera_aim and cam:
		_add_segment(mesh, cam.global_position, camera_aim_target, Color(0.1, 0.9, 1.0))

	if show_last_shot and last_shot_origin != last_shot_end:
		_add_segment(mesh, last_shot_origin, last_shot_end, Color(1.0, 0.88, 0.15))

	mesh.surface_end()


static func _add_segment(mesh: ImmediateMesh, start: Vector3, finish: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(start)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(finish)
