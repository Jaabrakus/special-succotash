extends Node3D

@export var target_pivot: Marker3D
@export var camera_target : Node3D
@export var follow_target : Node3D
@export var spring_arm : SpringArm3D

@export_group("Camera Parameter")
@export var follow_target_height_offset = 1.27
@export var pitch_max = 80 
@export var pitch_min = -60
var yaw = float()
var pitch = float()
var yaw_sensitivity = .002
var pitch_sensitivity = .002
var previous_yaw = 0.0
var yaw_rpm = 0.0
@export var max_yaw_rpm = 30.0  # Maximum RPM in either direction

#aim cam position
var gamepad_pitch_miltiplier = 0.0
var normal_gamepad_multiplier = 20.0
var aim_gamepad_multiplier = 10.0
var target_spring_length: float = 0.0  # Default spring length when not aiming
var target_cam_x_pos: float = 0.0
@export var normal_spring_arm: float = -2.3
@export var aim_spring_arm: float = -0.5
@export var aim_cam_pos_x: float = -0.465
var aim_speed: float = 500.0

@export_group("Weapon Aiming Parameter")
@export var target_pivot_x_offset: float = 2.45


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	top_level = true
	target_pivot.rotation_degrees = Vector3.ZERO


func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() != 0:
		yaw += -event.relative.x * yaw_sensitivity
		pitch += event.relative.y * pitch_sensitivity


func _process(_delta: float) -> void:
	#Aiming
	if Input.is_action_pressed("aim"):
		gamepad_pitch_miltiplier = aim_gamepad_multiplier
		target_spring_length = aim_spring_arm
		target_cam_x_pos = aim_cam_pos_x
	else:
		gamepad_pitch_miltiplier = normal_gamepad_multiplier
		target_spring_length = normal_spring_arm
		target_cam_x_pos = aim_cam_pos_x


func _physics_process(delta):
	cam_yaw_rpm(delta)

	# Lerp to the target spring while aiming
	spring_arm.spring_length = lerp(spring_arm.spring_length, target_spring_length, 10.0 * delta)
	spring_arm.position.x = lerp(spring_arm.position.x, target_cam_x_pos, 10.0 * delta)
	
	# Gamepad input
	var gamepad_input = Vector2(Input.get_axis("lookright", "lookleft"), -Input.get_axis("lookdown", "lookup"))
	var camera_input = Vector2.ZERO

	# Apply gamepad input if present
	if gamepad_input.length() > 0.1:
		camera_input = gamepad_input
		yaw += camera_input.x * yaw_sensitivity * 3000 * delta
		pitch += camera_input.y * pitch_sensitivity * 1000 * delta
	
	# Apply rotations with smoothing
	camera_target.rotation.y = lerpf(camera_target.rotation.y, yaw, delta * 10)
	camera_target.rotation.x = lerpf(camera_target.rotation.x, pitch, delta * 10)
	pitch = clamp(pitch, deg_to_rad(pitch_min), deg_to_rad(pitch_max))

	#camera follow player
	if follow_target:
		self.global_position = follow_target.global_position + Vector3(0, follow_target_height_offset, 0)


	##weapon aim pivot
	if follow_target.is_strafing:
		target_pivot.rotation_degrees.x = move_toward(target_pivot.rotation_degrees.x, rad_to_deg(pitch) + target_pivot_x_offset, aim_speed * delta)
	else:
		if follow_target.direction != Vector3.ZERO:
			target_pivot.rotation_degrees.x = move_toward(target_pivot.rotation_degrees.x, rad_to_deg(pitch) + target_pivot_x_offset, aim_speed * delta)
		else:
			target_pivot.rotation_degrees.x = move_toward(target_pivot.rotation_degrees.x, rad_to_deg(pitch) + target_pivot_x_offset, aim_speed * delta)

	target_pivot.rotation_degrees.y = move_toward(target_pivot.rotation_degrees.y, clampf(follow_target.cam_angle_diff, -90, 90), aim_speed * delta)


func cam_yaw_rpm(delta):
	# Calculate desired yaw change
	var desired_yaw_change = yaw - previous_yaw
	var angular_velocity = desired_yaw_change / delta
	
	# Convert to RPM
	var desired_rpm = (angular_velocity / (2 * PI)) * 60
	var clamped_rpm = clamp(desired_rpm, -max_yaw_rpm, max_yaw_rpm)
	
	# Convert clamped RPM back to radians
	var clamped_angular_velocity = (clamped_rpm / 60) * (2 * PI)
	
	# Calculate the actual yaw change allowed
	var clamped_yaw_change = clamped_angular_velocity * delta
	
	# Apply the clamped yaw
	yaw = previous_yaw + clamped_yaw_change
	
	# Store for next frame
	previous_yaw = yaw
	yaw_rpm = clamped_rpm