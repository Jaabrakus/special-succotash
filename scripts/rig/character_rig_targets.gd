class_name CharacterRigTargets
extends RefCounted

var pelvis := RigTarget.new()
var chest := RigTarget.new()

var right_hand := RigTarget.new()
var left_hand := RigTarget.new()

var right_elbow := RigTarget.new()
var left_elbow := RigTarget.new()

var right_foot := RigTarget.new()
var left_foot := RigTarget.new()

var right_knee := RigTarget.new()
var left_knee := RigTarget.new()

var head := RigTarget.new()

var look_target_world: Vector3 = Vector3.ZERO
var look_enabled: bool = false

var weapon_aim_direction_world: Vector3 = Vector3.FORWARD
var weapon_aim_enabled: bool = false


func clear_frame_intent() -> void:
	pelvis.clear()
	chest.clear()

	right_hand.clear()
	left_hand.clear()

	right_elbow.clear()
	left_elbow.clear()

	right_foot.clear()
	left_foot.clear()

	right_knee.clear()
	left_knee.clear()

	head.clear()

	look_enabled = false
	weapon_aim_enabled = false
