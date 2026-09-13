class_name SocomOperatorTraversalStow
extends RefCounted

## Cosmetic geometry only. Never reparent, hide or move the actual weapon.
## The animation driver owns actual-weapon visibility and traversal lifetime.
const PROFILE_PATH := "res://config/traversal_weapon_stow.json"

var attachment: BoneAttachment3D
var visual: Node3D
var copied_mesh_count: int = 0
var source_instance_id: int = 0
var current_family: StringName = &""
var source_visual_signature: int = 0


func begin(skeleton: Skeleton3D, weapon_root: Node3D, family: StringName = &"TWO_HAND_RIFLE") -> bool:
	if not is_instance_valid(skeleton) or not is_instance_valid(weapon_root):
		end()
		return false
	var signature := _visual_signature(weapon_root)
	if is_instance_valid(attachment) and attachment.get_parent() == skeleton and source_instance_id == weapon_root.get_instance_id() and current_family == family and source_visual_signature == signature:
		return true
	end()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not parsed is Dictionary or not bool(parsed.get("enabled", false)):
		return false
	var settings: Dictionary = parsed.get("pistol" if family == &"TWO_HAND_PISTOL" else "primary", {})
	var bone := str(settings.get("bone", "mixamorig_Spine2"))
	if skeleton.find_bone(bone) < 0:
		return false
	var parts: Array[Dictionary] = []
	var bounds := AABB()
	var first := true
	var inverse_source := weapon_root.global_transform.affine_inverse()
	for node: Node in weapon_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not _visible_within(mesh, weapon_root): continue
		var relative := inverse_source * mesh.global_transform
		var part_bounds := relative * mesh.get_aabb()
		bounds = part_bounds if first else bounds.merge(part_bounds)
		first = false
		parts.append({"source":mesh,"transform":relative})
	if parts.is_empty(): return false
	var long_axis := bounds.size.max_axis_index()
	var direction := Vector3.ZERO
	direction[long_axis] = -1.0 if long_axis == 2 else 1.0
	var muzzle := weapon_root.find_child("Socket_Muzzle", true, false) as Node3D
	var stock := weapon_root.find_child("Socket_Buttstock", true, false) as Node3D
	if muzzle != null and stock != null:
		var measured := inverse_source.basis * (muzzle.global_position - stock.global_position)
		if measured.length() > 0.01: direction = measured.normalized()
	var alignment := Basis(Quaternion(direction, Vector3.UP))
	var length_scale := minf(1.0, float(settings.get("maximum_length_m", 1.2)) / maxf(bounds.size[long_axis], 0.001))
	attachment = BoneAttachment3D.new()
	attachment.name = "TraversalStowedWeaponAttachment"
	attachment.bone_name = bone
	attachment.override_pose = false
	attachment.set_meta("presentation_only", true)
	skeleton.add_child(attachment)
	visual = Node3D.new()
	visual.name = "TraversalStowedWeaponVisual"
	visual.process_mode = Node.PROCESS_MODE_DISABLED
	attachment.add_child(visual)
	var bone_scale := skeleton.global_basis.get_scale().abs()
	var inverse_scale := 1.0 / maxf(bone_scale.x, 0.001)
	visual.position = _vector(settings.get("position_m", [])) * inverse_scale
	visual.rotation_degrees = _vector(settings.get("rotation_degrees", []))
	visual.scale = Vector3.ONE * inverse_scale
	for part in parts:
		var source := part.source as MeshInstance3D
		var copy := MeshInstance3D.new()
		copy.name = "Stowed_" + str(source.name)
		copy.mesh = source.mesh
		copy.skeleton = NodePath("")
		copy.skin = null
		copy.cast_shadow = source.cast_shadow
		copy.layers = source.layers
		# Shared immutable resources only: no source nodes, scripts, controllers,
		# collision bodies, particles, sounds, sockets, timers or weapon state.
		for surface in source.mesh.get_surface_count():
			copy.set_surface_override_material(surface, source.get_active_material(surface))
		var relative: Transform3D = part.transform
		copy.transform = Transform3D(alignment * relative.basis * length_scale, alignment * (relative.origin - bounds.get_center()) * length_scale)
		visual.add_child(copy)
	copied_mesh_count = parts.size()
	source_instance_id = weapon_root.get_instance_id()
	current_family = family
	source_visual_signature = signature
	attachment.on_skeleton_update()
	return true


func end() -> void:
	if is_instance_valid(attachment):
		attachment.visible = false
		attachment.queue_free()
	attachment = null
	visual = null
	copied_mesh_count = 0
	source_instance_id = 0
	current_family = &""
	source_visual_signature = 0


static func _visual_signature(source: Node3D) -> int:
	# Weapon equip normally replaces its root. Also detect a tool swapping a
	# model/material under the same root; ignore animated transforms to avoid
	# rebuilding cosmetic geometry each frame of a pose transition.
	var values: Array = []
	for node: Node in source.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not _visible_within(mesh, source): continue
		values.append(mesh.get_instance_id())
		values.append(mesh.mesh.get_instance_id())
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface)
			values.append(material.get_instance_id() if material != null else 0)
	return hash(values)


static func _visible_within(mesh: Node3D, root: Node3D) -> bool:
	var cursor: Node = mesh
	while cursor != null and cursor != root:
		if cursor is Node3D and not (cursor as Node3D).visible: return false
		cursor = cursor.get_parent()
	return cursor == root


static func _vector(value: Variant) -> Vector3:
	if not value is Array or value.size() != 3: return Vector3.ZERO
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
