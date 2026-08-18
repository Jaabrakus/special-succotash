extends SceneTree

const CANDIDATES: Array[String] = [
	"res://assets/animations/mixamo/Strafe Right.fbx",
	"res://assets/animations/mixamo/strafe left.fbx",
	"res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/run left.fbx",
	"res://assets/animations/mixamo/Strafe.fbx",
	"res://assets/animations/mixamo/strafe (2).fbx",
	"res://assets/animations/mixamo/Shooter Pack/strafe.fbx",
	"res://assets/animations/mixamo/Shooter Pack/strafe (2).fbx",
	"res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/run right.fbx",
]


func _initialize() -> void:
	for path in CANDIDATES:
		_audit(path)
	quit(0)


func _audit(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		print("STRAFE_CANDIDATE missing ", path)
		return
	var instance := packed.instantiate()
	var player := _find_animation_player(instance)
	if player == null:
		print("STRAFE_CANDIDATE no_player ", path)
		instance.queue_free()
		return
	var animation_name := _animation_name(player)
	var animation := player.get_animation(animation_name)
	var hip_yaw := NAN
	var upper_tracks := 0
	for track in range(animation.get_track_count()):
		var track_path := str(animation.track_get_path(track))
		if "Hips" in track_path and animation.track_get_type(track) == Animation.TYPE_ROTATION_3D and animation.track_get_key_count(track) > 0:
			var rotation: Quaternion = animation.track_get_key_value(track, 0)
			hip_yaw = rad_to_deg(rotation.get_euler().y)
		if _is_upper_body_path(track_path):
			upper_tracks += 1
	print(
		"STRAFE_CANDIDATE path=%s animation=%s length=%.3f tracks=%d upper=%d first_hip_yaw=%+.2f"
		% [path, animation_name, animation.length, animation.get_track_count(), upper_tracks, hip_yaw]
	)
	instance.queue_free()


func _animation_name(player: AnimationPlayer) -> StringName:
	if player.has_animation(&"mixamo_com"):
		return &"mixamo_com"
	for animation_name in player.get_animation_list():
		if animation_name != &"RESET":
			return animation_name
	return &""


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _is_upper_body_path(path: String) -> bool:
	for token in ["Spine", "Neck", "Head", "Shoulder", "Arm", "ForeArm", "Hand"]:
		if token in path:
			return true
	return false
