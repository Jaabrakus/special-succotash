class_name SocomMainGrenadeTrajectory
extends RefCounted

const TacticalGrenadeThrower := preload(
	"res://scripts/tactical/tactical_grenade_thrower.gd"
)
const GrenadeProfile := preload("res://scripts/tactical/tactical_grenade_profile.gd")
const GrenadeBase := preload("res://scripts/tactical/tactical_grenade_base.gd")

const PREDICTION_STEP_SECONDS := 1.0 / 30.0
const PREDICTION_MAX_SECONDS := 4.5
const PREDICTION_MAX_BOUNCES := 6
const RUNTIME_SURFACE_FRICTION := 0.62
const REST_SPEED_MPS := 0.65

var host
var grenade_collision_shape: SphereShape3D


func configure(main_host: Node) -> void:
	host = main_host
	grenade_collision_shape = SphereShape3D.new()
	grenade_collision_shape.radius = GrenadeBase.COLLISION_RADIUS_METERS


func create_preview() -> MeshInstance3D:
	var preview := MeshInstance3D.new()
	preview.name = "GrenadeArcPreview"
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preview.visible = false
	host.add_child(preview)
	return preview


func refresh(
	preview: MeshInstance3D,
	thrower: Node,
	hold_seconds: float,
	underhand: bool,
	type_name: String,
	selected_count: int,
	charge_bar: ProgressBar,
	charge_label: Label
) -> void:
	var player: CharacterBody3D = host.get("player") as CharacterBody3D
	if preview == null or thrower == null or player == null:
		return
	var launch_state := build_launch_state(thrower, hold_seconds, underhand)
	if launch_state.is_empty():
		return
	var charge := float(launch_state.get("charge", 0.0))
	var origin: Vector3 = launch_state.get("origin", Vector3.ZERO)
	var velocity: Vector3 = launch_state.get("velocity", Vector3.ZERO)
	var prediction := draw_launch_state(preview, launch_state, player)
	if charge_bar != null:
		charge_bar.value = charge * 100.0
	if charge_label != null:
		var cooked_fuse := float(thrower.call("remaining_fuse", 3.0, hold_seconds))
		var elevation_degrees := float(launch_state.get("elevation_degrees", 0.0))
		var landing: Vector3 = prediction.get("landing_position", origin)
		var landing_distance := Vector2(
			landing.x - origin.x,
			landing.z - origin.z
		).length()
		charge_label.text = "%s x%d  •  %s  •  POWER %d%%  •  ELEV %d°  •  LAND %.1fm  •  BOUNCES %d  •  FUSE %.1fs" % [
			type_name,
			selected_count,
			"UNDERHAND" if underhand else "OVERHAND",
			int(round(charge * 100.0)),
			int(round(elevation_degrees)),
			landing_distance,
			int(prediction.get("bounce_count", 0)),
			cooked_fuse,
		]


func draw_launch_state(
	preview: MeshInstance3D,
	launch_state: Dictionary,
	player: CharacterBody3D
) -> Dictionary:
	if preview == null or launch_state.is_empty():
		return {}
	var origin: Vector3 = launch_state.get("origin", Vector3.ZERO)
	var velocity: Vector3 = launch_state.get("velocity", Vector3.ZERO)
	var charge := float(launch_state.get("charge", 0.0))
	var prediction := _draw(preview, origin, velocity, charge, player)
	preview.set_meta("predicted_launch_origin", origin)
	preview.set_meta("predicted_launch_velocity", velocity)
	return prediction


func build_launch_state(thrower: Node, hold_seconds: float, underhand: bool) -> Dictionary:
	var camera_rig: Node3D = host.get("camera_rig") as Node3D
	var player: CharacterBody3D = host.get("player") as CharacterBody3D
	if thrower == null or camera_rig == null or player == null:
		return {}
	var camera: Camera3D = camera_rig.get("camera") as Camera3D
	if camera == null:
		return {}
	var charge := float(thrower.call("charge_for_hold", hold_seconds))
	var mode := (
		TacticalGrenadeThrower.ThrowMode.UNDERHAND
		if underhand
		else TacticalGrenadeThrower.ThrowMode.OVERHAND
	)
	var forward := -camera.global_basis.z
	var player_vel: Vector3 = player.velocity if player != null else Vector3.ZERO
	var launch_velocity: Vector3 = thrower.call(
		"calculate_launch_velocity",
		forward,
		Vector3.UP,
		mode,
		charge,
		player_vel
	)
	return {
		"origin": arc_origin(),
		"forward": forward,
		"velocity": launch_velocity,
		"elevation_degrees": rad_to_deg(asin(clampf(
			launch_velocity.normalized().dot(Vector3.UP),
			-1.0,
			1.0
		))),
		"charge": charge,
		"mode": mode,
	}


func arc_origin() -> Vector3:
	var player: CharacterBody3D = host.get("player") as CharacterBody3D
	if player == null:
		return Vector3.INF
	var shoulder := bone_world_position(&"mixamorig_RightArm")
	if shoulder.is_finite():
		return shoulder + player.global_basis.z.normalized() * 0.18 + Vector3.UP * 0.04
	return (
		player.global_position
		+ Vector3.UP * 1.48
		+ player.global_basis.x.normalized() * 0.24
		+ player.global_basis.z.normalized() * 0.16
	)


func release_origin() -> Vector3:
	var hand := bone_world_position(&"mixamorig_RightHand")
	return hand if hand.is_finite() else arc_origin()


func bone_world_position(bone_name: StringName) -> Vector3:
	var player: Node = host.get("player") as Node
	if player == null:
		return Vector3.INF
	var mannequin := player.get_node_or_null("Mannequin") as Node
	var driver: Node = mannequin.get("production_animation") as Node if mannequin != null else null
	var skeleton: Skeleton3D = driver.get("skeleton") as Skeleton3D if driver != null else null
	if skeleton == null:
		return Vector3.INF
	var bone_index := skeleton.find_bone(bone_name)
	if bone_index < 0:
		return Vector3.INF
	return (skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)).origin


func _draw(
	preview: MeshInstance3D,
	origin: Vector3,
	velocity: Vector3,
	charge: float,
	player: CharacterBody3D
) -> Dictionary:
	var prediction := predict_path(origin, velocity, player)
	var points: Array = prediction.get("points", [])
	var first_bounce_index := int(prediction.get("first_bounce_index", -1))
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = Color.WHITE
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	var flight_color := Color(0.25, 0.95, 0.72).lerp(Color(1.0, 0.78, 0.22), charge)
	var bounce_color := Color(1.0, 0.38, 0.16)
	for index in points.size():
		var point: Vector3 = points[index]
		mesh.surface_set_color(
			bounce_color
			if first_bounce_index >= 0 and index >= first_bounce_index
			else flight_color
		)
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	_draw_landing_marker(
		mesh,
		material,
		prediction.get("landing_position", origin),
		prediction.get("landing_normal", Vector3.UP)
	)
	preview.mesh = mesh
	preview.set_meta("predicted_landing_position", prediction.get("landing_position", origin))
	preview.set_meta("predicted_bounce_count", prediction.get("bounce_count", 0))
	preview.set_meta("predicted_path_point_count", points.size())
	return prediction


func predict_path(
	origin: Vector3,
	velocity: Vector3,
	player: CharacterBody3D
) -> Dictionary:
	var points: Array[Vector3] = [origin]
	var position := origin
	var current_velocity := velocity
	var gravity_strength := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var gravity := Vector3.DOWN * gravity_strength
	var profile := GrenadeProfile.load_profile()
	var common: Dictionary = profile.get("common", {})
	var restitution := clampf(float(common.get("bounce_restitution", 0.38)), 0.0, 0.95)
	var bounce_count := 0
	var first_bounce_index := -1
	var landing_position := origin
	var landing_normal := Vector3.UP
	var step_count := int(ceil(PREDICTION_MAX_SECONDS / PREDICTION_STEP_SECONDS))
	for _step in step_count:
		var next_position := (
			position
			+ current_velocity * PREDICTION_STEP_SECONDS
			+ gravity * 0.5 * PREDICTION_STEP_SECONDS * PREDICTION_STEP_SECONDS
		)
		var next_velocity := current_velocity + gravity * PREDICTION_STEP_SECONDS
		var hit := _cast_grenade_volume(position, next_position, player)
		if hit.is_empty():
			position = next_position
			current_velocity = next_velocity
			points.append(position)
			landing_position = position
			continue
		var impact_position := Vector3(hit.get("center_position", next_position))
		var impact_normal := Vector3(hit.get("normal", Vector3.UP)).normalized()
		points.append(impact_position)
		if first_bounce_index < 0:
			first_bounce_index = points.size() - 1
		bounce_count += 1
		landing_position = impact_position
		landing_normal = impact_normal
		var normal_speed := next_velocity.dot(impact_normal)
		var tangent_velocity := next_velocity - impact_normal * normal_speed
		var outward_speed := maxf(-normal_speed * restitution, 0.0)
		current_velocity = (
			tangent_velocity * (1.0 - RUNTIME_SURFACE_FRICTION)
			+ impact_normal * outward_speed
		)
		position = impact_position + impact_normal * 0.002
		points.append(position)
		if current_velocity.length() <= REST_SPEED_MPS or bounce_count >= PREDICTION_MAX_BOUNCES:
			break
	return {
		"points": points,
		"bounce_count": bounce_count,
		"first_bounce_index": first_bounce_index,
		"landing_position": landing_position,
		"landing_normal": landing_normal,
		"rest_speed_mps": current_velocity.length(),
	}


func _cast_grenade_volume(
	start: Vector3,
	destination: Vector3,
	player: CharacterBody3D
) -> Dictionary:
	if grenade_collision_shape == null:
		grenade_collision_shape = SphereShape3D.new()
		grenade_collision_shape.radius = GrenadeBase.COLLISION_RADIUS_METERS
	var exclude: Array[RID] = []
	if player != null:
		exclude.append(player.get_rid())
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = grenade_collision_shape
	query.transform = Transform3D(Basis.IDENTITY, start)
	query.motion = destination - start
	query.margin = 0.001
	query.collision_mask = GrenadeBase.COLLISION_MASK
	query.collide_with_areas = false
	query.exclude = exclude
	var space: PhysicsDirectSpaceState3D = host.get_world_3d().direct_space_state
	var cast: PackedFloat32Array = space.cast_motion(query)
	var safe_fraction := cast[0] if cast.size() >= 1 else 1.0
	if safe_fraction >= 0.9999:
		return {}
	var unsafe_fraction := cast[1] if cast.size() >= 2 else safe_fraction
	var center_position := start.lerp(destination, safe_fraction)
	var ray := PhysicsRayQueryParameters3D.create(
		start,
		destination,
		GrenadeBase.COLLISION_MASK,
		exclude
	)
	ray.collide_with_areas = false
	var ray_hit: Dictionary = space.intersect_ray(ray)
	var normal := Vector3.ZERO
	var surface_position := center_position
	if not ray_hit.is_empty():
		normal = Vector3(ray_hit.get("normal", Vector3.ZERO)).normalized()
		surface_position = Vector3(ray_hit.get("position", center_position))
	else:
		query.transform.origin = start.lerp(destination, unsafe_fraction)
		query.motion = Vector3.ZERO
		var rest: Dictionary = space.get_rest_info(query)
		if not rest.is_empty():
			normal = Vector3(rest.get("normal", Vector3.ZERO)).normalized()
			surface_position = Vector3(rest.get("point", center_position))
	if normal.length_squared() < 0.5:
		normal = (start - destination).normalized()
	return {
		"center_position": center_position,
		"surface_position": surface_position,
		"normal": normal,
		"safe_fraction": safe_fraction,
	}


func _draw_landing_marker(
	mesh: ImmediateMesh,
	material: StandardMaterial3D,
	center: Vector3,
	normal: Vector3
) -> void:
	var safe_normal := normal.normalized() if normal.length_squared() > 0.5 else Vector3.UP
	var tangent := safe_normal.cross(Vector3.RIGHT).normalized()
	if tangent.length_squared() < 0.5:
		tangent = safe_normal.cross(Vector3.FORWARD).normalized()
	var bitangent := safe_normal.cross(tangent).normalized()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	for index in range(25):
		var angle := TAU * float(index) / 24.0
		mesh.surface_set_color(Color(1.0, 0.20, 0.12))
		mesh.surface_add_vertex(
			center
			+ safe_normal * 0.018
			+ (tangent * cos(angle) + bitangent * sin(angle)) * 0.18
		)
	mesh.surface_end()
