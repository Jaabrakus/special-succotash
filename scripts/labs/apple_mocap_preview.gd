class_name AppleMocapPreview
extends Control

const LINKS := [
	["human_top_head_3D", "human_center_head_3D"],
	["human_center_head_3D", "human_center_shoulder_3D"],
	["human_center_shoulder_3D", "human_spine_3D"],
	["human_spine_3D", "human_root_3D"],
	["human_center_shoulder_3D", "human_left_shoulder_3D"],
	["human_left_shoulder_3D", "human_left_elbow_3D"],
	["human_left_elbow_3D", "human_left_wrist_3D"],
	["human_center_shoulder_3D", "human_right_shoulder_3D"],
	["human_right_shoulder_3D", "human_right_elbow_3D"],
	["human_right_elbow_3D", "human_right_wrist_3D"],
	["human_root_3D", "human_left_hip_3D"],
	["human_left_hip_3D", "human_left_knee_3D"],
	["human_left_knee_3D", "human_left_ankle_3D"],
	["human_root_3D", "human_right_hip_3D"],
	["human_right_hip_3D", "human_right_knee_3D"],
	["human_right_knee_3D", "human_right_ankle_3D"],
]

var joints: Dictionary = {}


func show_frame(frame: Dictionary) -> void:
	joints = frame.get("joints", {})
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("10151d"))
	if joints.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(24, 42), "Extract a video to preview its tracked skeleton.", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("9aa7b8"))
		return
	for link in LINKS:
		var from := _point(link[0])
		var to := _point(link[1])
		if from.x >= 0.0 and to.x >= 0.0:
			draw_line(from, to, Color("52d7ee"), 4.0, true)
	for raw_joint in joints.values():
		if raw_joint is Dictionary and raw_joint.has("image"):
			var image: Dictionary = raw_joint["image"]
			var point := Vector2(float(image.get("x", 0.0)) * size.x, (1.0 - float(image.get("y", 0.0))) * size.y)
			draw_circle(point, 6.0, Color("7ef29a"))


func _point(name: String) -> Vector2:
	var joint: Dictionary = joints.get(name, {})
	if not joint.has("image"):
		return Vector2(-1, -1)
	var image: Dictionary = joint["image"]
	return Vector2(float(image.get("x", 0.0)) * size.x, (1.0 - float(image.get("y", 0.0))) * size.y)
