class_name SocomOperatorWeaponPresentationOwner
extends RefCounted

## Sole mutation boundary for the rendered weapon after import calibration.
## Animation, IK, camera, and gameplay may request a pose, but none of them
## should independently reparent, hide, or write the weapon transform.

var weapon: Node3D
var animation_parent: Node
var solver_anchor: Node3D
var hand_mount_transform := Transform3D.IDENTITY
var owner_name: StringName = &"UNBOUND"
var mutation_count: int = 0
var parent_transition_count: int = 0
var last_mutation: StringName = &"NONE"


func bind(
	attached_weapon: Node3D,
	authored_parent: Node,
	world_solver_anchor: Node3D,
	authored_hand_mount: Transform3D
) -> void:
	weapon = attached_weapon
	animation_parent = authored_parent
	solver_anchor = world_solver_anchor
	hand_mount_transform = authored_hand_mount
	owner_name = &"RELAXED_RIFLE_LOCOMOTION"
	last_mutation = &"BIND"


func update_hand_mount(value: Transform3D) -> void:
	hand_mount_transform = value


func set_owner(next_owner: StringName) -> void:
	owner_name = next_owner


func use_solver_parent(preserve_world: bool = true) -> void:
	if weapon == null or solver_anchor == null or weapon.get_parent() == solver_anchor:
		return
	weapon.reparent(solver_anchor, preserve_world)
	parent_transition_count += 1
	_record(&"SOLVER_PARENT")


func use_animation_parent(restore_mount: bool = true) -> void:
	if weapon == null or animation_parent == null:
		return
	if weapon.get_parent() != animation_parent:
		weapon.reparent(animation_parent, false)
		parent_transition_count += 1
	if restore_mount:
		weapon.transform = hand_mount_transform
	_record(&"ANIMATION_PARENT")


func restore_animation_mount_before_solver() -> void:
	if weapon == null:
		return
	if animation_parent != null and weapon.get_parent() == animation_parent:
		weapon.transform = hand_mount_transform
	_record(&"RESTORE_HAND_MOUNT")


func set_world_transform(value: Transform3D) -> void:
	if weapon == null:
		return
	weapon.global_transform = value
	_record(&"WORLD_TRANSFORM")


func set_world_basis(value: Basis) -> void:
	if weapon == null:
		return
	weapon.global_basis = value
	_record(&"WORLD_BASIS")


func set_world_position(value: Vector3) -> void:
	if weapon == null:
		return
	weapon.global_position = value
	_record(&"WORLD_POSITION")


func translate_world(delta: Vector3) -> void:
	if weapon == null or delta.length_squared() <= 0.0000000001:
		return
	weapon.global_position += delta
	_record(&"WORLD_TRANSLATE")


func set_local_transform(value: Transform3D) -> void:
	if weapon == null:
		return
	weapon.transform = value
	_record(&"LOCAL_TRANSFORM")


func set_visible(enabled: bool) -> void:
	if weapon == null:
		return
	weapon.visible = enabled
	_record(&"VISIBILITY")


func snapshot() -> Dictionary:
	return {
		"owner": owner_name,
		"parent": str(weapon.get_parent().name) if weapon != null and weapon.get_parent() != null else "NONE",
		"visible": weapon.visible if weapon != null else false,
		"mutation_count": mutation_count,
		"parent_transition_count": parent_transition_count,
		"last_mutation": last_mutation,
	}


func _record(kind: StringName) -> void:
	mutation_count += 1
	last_mutation = kind
