extends RefCounted

## Records raw tree output. AnimationTree alone applies the frozen pose.
const LIBRARY := &"source_transition_snapshot"
var enabled := false
var skeleton: Skeleton3D
var tree: AnimationTree
var anchor: Node
var safe_to_capture: Callable
var animations: Dictionary = {}
var wrappers: Dictionary = {}
var positions := PackedVector3Array()
var rotations: Array[Quaternion] = []
var scales := PackedVector3Array()
var root_source := Vector3.ZERO
var coverage := 0.0
var latest_valid := false
var latest_process_frame := -1
var frozen_state: StringName = &""
var target_state: StringName = &""
var captures := 0
var freezes := 0
var releases := 0


func prepare(player: AnimationPlayer, target: Skeleton3D, active: bool) -> void:
	skeleton = target
	enabled = active and is_instance_valid(skeleton) and is_instance_valid(player)
	# Previous graph is already freed by the canonical driver on equip/rebuild.
	if is_instance_valid(player) and player.has_animation_library(LIBRARY):
		player.remove_animation_library(LIBRARY)
	if not enabled: return
	var library := AnimationLibrary.new()
	player.add_animation_library(LIBRARY, library)
	anchor = skeleton.get_node_or_null("SourceCameraAnchor")
	positions.resize(skeleton.get_bone_count())
	rotations.resize(skeleton.get_bone_count())
	scales.resize(skeleton.get_bone_count())
	var skeleton_path := player.get_node(player.root_node).get_path_to(skeleton)
	for state: StringName in [&"standing", &"idle", &"crouch", &"idle_crouch"]:
		var animation := Animation.new()
		animation.length = 1.0
		animation.loop_mode = Animation.LOOP_LINEAR
		for bone in skeleton.get_bone_count():
			var path := NodePath(String(skeleton_path) + ":" + skeleton.get_bone_name(bone))
			for type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
				var track := animation.add_track(type)
				animation.track_set_path(track, path)
				animation.track_insert_key(track, 0.0, Quaternion.IDENTITY if type == Animation.TYPE_ROTATION_3D else (Vector3.ONE if type == Animation.TYPE_SCALE_3D else Vector3.ZERO))
		if is_instance_valid(anchor):
			for property: String in ["root_source", "coverage"]:
				var track := animation.add_track(Animation.TYPE_VALUE)
				animation.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
				var anchor_path := player.get_node(player.root_node).get_path_to(anchor)
				animation.track_set_path(track, NodePath(String(anchor_path) + ":" + property))
				animation.track_insert_key(track, 0.0, Vector3.ZERO if property == "root_source" else 0.0)
		library.add_animation(state, animation)
		animations[state] = animation


func wrap(root: AnimationNodeBlendTree, state: StringName, original: StringName) -> StringName:
	if not enabled or not animations.has(state): return original
	var constant_name := StringName("source_snapshot_pose_" + String(state))
	var wrapper_name := StringName("source_snapshot_" + String(state))
	var constant := AnimationNodeAnimation.new()
	constant.animation = StringName(String(LIBRARY) + "/" + String(state))
	root.add_node(constant_name, constant)
	var blend := AnimationNodeBlend2.new()
	# Original stays on its own tree clock; zero-weight constant is harmless.
	blend.sync = true
	root.add_node(wrapper_name, blend)
	root.connect_node(wrapper_name, 0, original)
	root.connect_node(wrapper_name, 1, constant_name)
	wrappers[state] = StringName("parameters/%s/blend_amount" % wrapper_name)
	return wrapper_name


func bind(value: AnimationTree, safety: Callable) -> void:
	tree = value
	safe_to_capture = safety
	if enabled:
		tree.mixer_applied.connect(_capture_raw_result)


func request(from: StringName, to: StringName, eligible: bool) -> bool:
	# Stable topology: restore previous selectors; never reconnect live nodes.
	release()
	if not enabled or not eligible or not latest_valid or not animations.has(from) \
			or latest_process_frame < Engine.get_process_frames() - 1:
		return false
	var animation: Animation = animations[from]
	for bone in positions.size():
		animation.track_set_key_value(bone * 3, 0, positions[bone])
		animation.track_set_key_value(bone * 3 + 1, 0, rotations[bone])
		animation.track_set_key_value(bone * 3 + 2, 0, scales[bone])
	if is_instance_valid(anchor):
		animation.track_set_key_value(positions.size() * 3, 0, root_source)
		animation.track_set_key_value(positions.size() * 3 + 1, 0, coverage)
	tree.set(wrappers[from], 1.0)
	frozen_state = from
	target_state = to
	freezes += 1
	return true


func release() -> void:
	if is_instance_valid(tree):
		for path: StringName in wrappers.values(): tree.set(path, 0.0)
	if frozen_state != &"": releases += 1
	frozen_state = &""
	target_state = &""


func _capture_raw_result() -> void:
	latest_valid = false
	if not enabled or not is_instance_valid(skeleton) or not safe_to_capture.is_valid() or not bool(safe_to_capture.call()):
		release()
		return
	# Completion comes from the existing transition, never a second countdown.
	if frozen_state != &"" and StringName(tree.get("parameters/modern_transition/current_state")) == target_state \
			and float(tree.get("parameters/modern_transition/prev_xfading")) <= 0.0:
		release()
	for bone in skeleton.get_bone_count():
		positions[bone] = skeleton.get_bone_pose_position(bone)
		rotations[bone] = skeleton.get_bone_pose_rotation(bone)
		scales[bone] = skeleton.get_bone_pose_scale(bone)
		if not positions[bone].is_finite() or not rotations[bone].is_finite() or not scales[bone].is_finite():
			return
	root_source = Vector3.ZERO
	coverage = 0.0
	if is_instance_valid(anchor):
		root_source = anchor.get("root_source")
		coverage = float(anchor.get("coverage"))
		if not root_source.is_finite() or not is_finite(coverage): return
	latest_valid = true
	latest_process_frame = Engine.get_process_frames()
	captures += 1


func diagnostics() -> Dictionary:
	return {"enabled":enabled, "raw_captures":captures, "freezes":freezes,
		"releases":releases, "frozen_state":frozen_state, "target_state":target_state,
		"latest_valid":latest_valid, "bone_count":positions.size()}
