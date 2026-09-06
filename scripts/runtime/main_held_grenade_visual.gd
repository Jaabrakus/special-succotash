extends RefCounted

# Presentation construction only; no process callback or attachment ownership change.
const GRENADE_VISUAL_SCENES: Array[PackedScene] = [
	preload("res://assets/models/grenades/frag_west_cc0.glb"),
	preload("res://assets/models/grenades/flashbang_west_cc0.glb"),
	preload("res://assets/models/grenades/smoke_west_cc0.glb"),
]

const HELD_GRENADE_VISUAL_SCALE := 0.55

static func _build_held_grenade_visual(runtime: Node) -> void:
	if runtime.player == null:
		return
	var mannequin := runtime.player.get_node_or_null("Mannequin") as Node
	var driver: Node = mannequin.get("production_animation") as Node if mannequin != null else null
	var skeleton: Skeleton3D = driver.get("skeleton") as Skeleton3D if driver != null else null
	if skeleton == null:
		return
	runtime.held_grenade_attachment = BoneAttachment3D.new()
	runtime.held_grenade_attachment.name = "HeldGrenadeAttachment"
	runtime.held_grenade_attachment.bone_name = "mixamorig_RightHand"
	skeleton.add_child(runtime.held_grenade_attachment)
	# The imported operator skeleton carries a 64x bone scale. BoneAttachment3D
	# rewrites its own transform from the bone every frame, so its child must
	# cancel that scale while retaining the hand's animated position and rotation.
	var inherited_scale: Vector3 = runtime.held_grenade_attachment.global_basis.get_scale()
	var inverse_bone_scale := Vector3(
		1.0 / maxf(inherited_scale.x, 0.001),
		1.0 / maxf(inherited_scale.y, 0.001),
		1.0 / maxf(inherited_scale.z, 0.001)
	)
	runtime.held_grenade_mesh = Node3D.new()
	runtime.held_grenade_mesh.name = "HeldGrenadeVisual"
	runtime.held_grenade_mesh.scale = inverse_bone_scale
	runtime.held_grenade_mesh.position = Vector3(0.0, 0.012, -0.006) * inverse_bone_scale
	runtime.held_grenade_attachment.add_child(runtime.held_grenade_mesh)
	_update_held_grenade_visual(runtime)
	_set_held_grenade_visible(runtime, false)


static func _update_held_grenade_visual(runtime: Node) -> void:
	if runtime.held_grenade_mesh == null:
		return
	for child in runtime.held_grenade_mesh.get_children():
		child.queue_free()
	var visual := GRENADE_VISUAL_SCENES[runtime.selected_type].instantiate() as Node3D
	if visual == null:
		return
	visual.name = "TypeVisual"
	visual.scale = Vector3.ONE * HELD_GRENADE_VISUAL_SCALE
	runtime.held_grenade_mesh.add_child(visual)


static func _set_held_grenade_visible(runtime: Node, enabled: bool) -> void:
	if runtime.held_grenade_mesh != null:
		runtime.held_grenade_mesh.visible = enabled
