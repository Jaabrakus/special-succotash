class_name SocomMainGrenadeTrajectory
extends RefCounted

const TacticalGrenadeThrower := preload(
	"res://scripts/tactical/tactical_grenade_thrower.gd"
)

var host


func configure(main_host: Node) -> void:
	host = main_host


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
	var camera_rig: Node3D = host.get("camera_rig") as Node3D
	var player: CharacterBody3D = host.get("player") as CharacterBody3D
	if preview == null or thrower == null or camera_rig == null or player == null:
		return
	var charge := float(thrower.call("charge_for_hold", hold_seconds))
	var mode := (
		TacticalGrenadeThrower.ThrowMode.UNDERHAND
		if underhand
		else TacticalGrenadeThrower.ThrowMode.OVERHAND
	)
	var forward: Vector3 = -camera_rig.get("camera").global_basis.z
	var velocity: Vector3 = thrower.call(
		"calculate_launch_velocity", forward, Vector3.UP, mode, charge
	)
	_draw(preview, arc_origin(), velocity, charge, player)
	if charge_bar != null:
		charge_bar.value = charge * 100.0
	if charge_label != null:
		var cooked_fuse := float(thrower.call("remaining_fuse", 3.0, hold_seconds))
		charge_label.text = "%s x%d  •  %s  •  POWER %d%%  •  SAFE FUSE %.1fs  •  RELEASE FIRE" % [
			type_name,
			selected_count,
			"UNDERHAND" if underhand else "OVERHAND",
			int(round(charge * 100.0)),
			cooked_fuse,
		]


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
) -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = Color(0.25, 0.95, 0.72).lerp(Color(1.0, 0.78, 0.22), charge)
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var previous := origin
	mesh.surface_set_color(material.emission)
	mesh.surface_add_vertex(origin)
	for index in range(1, 29):
		var time := float(index) * 0.075
		var point := origin + velocity * time + Vector3.DOWN * 0.5 * gravity * time * time
		var query := PhysicsRayQueryParameters3D.create(previous, point)
		query.exclude = [player.get_rid()]
		query.collide_with_areas = false
		var hit: Dictionary = host.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			point = Vector3(hit.get("position", point))
			mesh.surface_add_vertex(point)
			break
		mesh.surface_add_vertex(point)
		previous = point
	mesh.surface_end()
	preview.mesh = mesh
