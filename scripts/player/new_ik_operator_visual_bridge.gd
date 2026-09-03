class_name SocomNewIkOperatorVisualBridge
extends Node3D

## Visual-only bridge for the authored Godot IK player.
##
## The parent SOCOM CharacterBody3D remains the sole movement owner. The SOCOM
## camera remains the sole aim owner. This bridge only translates those two
## authoritative inputs into the imported AnimationTree and TargetPivot.

const VISUAL_SCENE := preload("res://scenes/player/new_ik_operator_visual.tscn")
const AIM_PITCH_OFFSET_DEG := 2.45
const AIM_YAW_LIMIT_DEG := 90.0
const SOURCE_TO_SOCOM_YAW := PI

var visual_root: Node3D
var skeleton: Skeleton3D
var animation_tree: AnimationTree
var target_pivot: Marker3D
var gun: Node3D
var enabled: bool = false


func _ready() -> void:
	visual_root = VISUAL_SCENE.instantiate() as Node3D
	if visual_root == null:
		push_error("New IK operator visual could not be instantiated")
		return
	visual_root.name = "AuthoredGodotIkVisual"
	# The purchased scene is authored facing +Z. SOCOM's player/camera contract
	# faces -Z, so correct only the imported visual instead of rotating gameplay.
	visual_root.rotation.y = SOURCE_TO_SOCOM_YAW
	add_child(visual_root)

	skeleton = visual_root.get_node_or_null("Model/GeneralSkeleton") as Skeleton3D
	animation_tree = visual_root.get_node_or_null("AnimationTree") as AnimationTree
	target_pivot = visual_root.get_node_or_null("TargetPivot") as Marker3D
	gun = visual_root.get_node_or_null(
		"Model/GeneralSkeleton/RShoulderBoneAttachment3D2/WeaponHolder/Gun"
	) as Node3D

	_disable_reference_gameplay_nodes(visual_root)
	if animation_tree != null:
		animation_tree.active = true
		animation_tree.set("parameters/FingersBlend2/blend_amount", 1.0)
		animation_tree.set("parameters/TIP/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	enabled = skeleton != null and animation_tree != null and target_pivot != null
	if not enabled:
		push_error("New IK operator visual is missing Skeleton, AnimationTree, or TargetPivot")


func sync_from_socom_player(player: CharacterBody3D, aim_rig: Node, _delta: float) -> void:
	if not enabled or player == null:
		return

	var local_velocity := player.global_basis.inverse() * player.velocity
	var top_speed := maxf(float(player.get("move_speed")), 0.001)
	var strafe_blend := Vector2(local_velocity.x, -local_velocity.z) / top_speed
	if strafe_blend.length() > 1.0:
		strafe_blend = strafe_blend.normalized()
	animation_tree.set("parameters/WALK/blend_position", strafe_blend)

	var aim_yaw := player.global_rotation.y
	var aim_pitch := 0.0
	if aim_rig != null:
		aim_yaw = float(aim_rig.get("aim_yaw"))
		aim_pitch = float(aim_rig.get("aim_pitch"))
		if aim_rig.has_method("get_shared_body_aim_yaw_pitch"):
			var shared_angles: Vector2 = aim_rig.call("get_shared_body_aim_yaw_pitch")
			aim_yaw = shared_angles.x
			aim_pitch = shared_angles.y

	var relative_yaw := wrapf(aim_yaw - player.global_rotation.y, -PI, PI)
	target_pivot.rotation.x = aim_pitch + deg_to_rad(AIM_PITCH_OFFSET_DEG)
	target_pivot.rotation.y = clampf(
		relative_yaw,
		-deg_to_rad(AIM_YAW_LIMIT_DEG),
		deg_to_rad(AIM_YAW_LIMIT_DEG)
	)


func set_weapon_visible(weapon_visible: bool) -> void:
	if gun != null:
		gun.visible = weapon_visible


func get_visual_skeleton() -> Skeleton3D:
	return skeleton


func _disable_reference_gameplay_nodes(root: Node) -> void:
	for child in root.find_children("*", "Camera3D", true, false):
		var camera := child as Camera3D
		if camera != null:
			camera.current = false
	for child in root.find_children("*", "CollisionShape3D", true, false):
		var collision := child as CollisionShape3D
		if collision != null:
			collision.disabled = true
	var reference_camera := root.get_node_or_null("Camera")
	if reference_camera != null:
		reference_camera.process_mode = Node.PROCESS_MODE_DISABLED
		if reference_camera is Node3D:
			(reference_camera as Node3D).visible = false
