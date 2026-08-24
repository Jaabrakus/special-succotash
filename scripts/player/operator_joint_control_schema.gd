class_name SocomOperatorJointControlSchema
extends RefCounted

## One control vocabulary for Gunsmith, Animation Studio, and live tuning.
## Controls change additive rotations or IK targets. They never scale bones.

const ROTATION_JOINTS := [
	&"hips",
	&"spine", &"spine1", &"spine2", &"neck", &"head",
	&"left_shoulder", &"right_shoulder",
	&"left_upper_arm", &"right_upper_arm",
	&"left_upper_leg", &"right_upper_leg",
	&"left_lower_leg", &"right_lower_leg",
	&"left_foot", &"right_foot",
	&"left_toe", &"right_toe",
]
const ELBOW_POLE_JOINTS := [&"left_forearm", &"right_forearm"]
const HAND_TARGET_JOINTS := [&"left_hand", &"right_hand"]
const SELECTABLE_JOINTS := ROTATION_JOINTS + ELBOW_POLE_JOINTS + HAND_TARGET_JOINTS


static func control_mode(joint_name: StringName) -> StringName:
	if joint_name in ELBOW_POLE_JOINTS:
		return &"elbow_pole"
	if joint_name in HAND_TARGET_JOINTS:
		return &"hand_target"
	return &"rotation"


static func display_name(joint_name: StringName) -> String:
	return String(joint_name).replace("_", " ").capitalize()


static func axis_labels(joint_name: StringName) -> PackedStringArray:
	if joint_name == &"head":
		return PackedStringArray(["Nod Up / Down", "Look Left / Right", "Lean Curve Left / Right"])
	match control_mode(joint_name):
		&"elbow_pole":
			return PackedStringArray(["Out / In", "Up / Down", "Forward / Back"])
		&"hand_target":
			return PackedStringArray(["Along Weapon", "Up / Down", "Side / Side"])
		_:
			return PackedStringArray(["Bend", "Turn", "Twist"])


static func help_text(joint_name: StringName) -> String:
	if joint_name == &"head":
		return "Curves the head through the neck and upper spine. This is the base for future lean mechanics."
	if joint_name in [&"left_upper_leg", &"right_upper_leg", &"left_lower_leg", &"right_lower_leg"]:
		return "Rotates this leg joint without changing bone length or gameplay collision."
	if joint_name in [&"left_foot", &"right_foot", &"left_toe", &"right_toe"]:
		return "Rotates this foot contact joint without moving the authoritative body."
	match control_mode(joint_name):
		&"elbow_pole":
			return "Moves the elbow IK pole. Arm length stays locked."
		&"hand_target":
			return "Moves the saved weapon grip target. The arm solves to it in every animation."
		_:
			return "Adds a bounded local rotation after each compatible animation. Bone length stays locked."
