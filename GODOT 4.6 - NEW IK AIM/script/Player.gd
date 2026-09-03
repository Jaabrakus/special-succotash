extends CharacterBody3D


const SPEED = 5.0
const JUMP_VELOCITY = 4.5

@export var animation_tree: AnimationTree
@export var camera_target: Node3D
var is_strafing: bool = true
var turn_speed: float = 8.0
var gravity = 9.8

#root motion parameter
var root_velocity = Vector3()
var root_motion_speed_multiplier: float = 1.0

### PLAYER DIRECTION
var input_dir: Vector2
var direction: Vector3

var currentspeed = Vector2.ZERO
var strafe_acceleration = 3
var targetspeed
var strafe_input:Vector2 = Vector2.ZERO
var camera_rotation: float = 0.0

## 'True' to enable Turn In Place
@export var enable_tip: bool = true
var cam_angle_diff = float()
var turn_in_place: bool = false
var tip_timer: float = 0.0
var tip_cool_down: float = 0.5


func _ready() -> void:
	add_to_group("player")
	animation_tree.set("parameters/FingersBlend2/blend_amount", 1.0)
	animation_tree.set("parameters/TIP TimeScale/scale", 1.4)


func _process(delta: float) -> void:
	turn_in_place = animation_tree.get("parameters/TIP/active") and !(direction != Vector3.ZERO)
	root_motion(delta, true)
	handle_strafe_animation(delta)
	handle_turn_in_place(delta)


func _physics_process(delta: float) -> void:
	if direction != Vector3.ZERO:
		tip_timer = 0.0
	else:
		tip_timer += delta

	_handle_input_direction(delta)
	_handle_rotation(delta)
	angle_rotation()

	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	velocity = Vector3(root_velocity.x, velocity.y, root_velocity.z)
	move_and_slide()


func _handle_input_direction(_delta: float):
	input_dir = Input.get_vector("right", "left", "backward", "forward")
	direction = Vector3(input_dir.x, 0, input_dir.y)
	
	if camera_target:
		camera_rotation = camera_target.global_transform.basis.get_euler().y
		direction = direction.rotated(Vector3.UP, camera_rotation).normalized()

func _handle_rotation(delta):
	if not camera_target:
		return
	
	if direction != Vector3.ZERO:
		if is_strafing:
			rotation.y = lerp_angle(rotation.y, camera_rotation, delta * turn_speed)
		else:
			rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), turn_speed * delta)


func root_motion(delta, enabled: bool):
	if !enabled:
		return

	#root motion code
	var root_pos = animation_tree.get_root_motion_position()
	var current_rotation = (animation_tree.get_root_motion_rotation_accumulator().inverse() * get_quaternion())
	root_velocity = current_rotation * root_pos / delta * root_motion_speed_multiplier
	var root_rotation =  animation_tree.get_root_motion_rotation() *2.0
	set_quaternion(get_quaternion() * root_rotation)

func angle_rotation():
	camera_rotation = camera_target.global_transform.basis.get_euler().y
	var cam_direction = Vector3.BACK.rotated(Vector3.UP, camera_rotation)
	var forward_direction = global_transform.basis.z.normalized() 

	if is_strafing:
		cam_angle_diff = rad_to_deg(forward_direction.signed_angle_to(cam_direction, Vector3.UP))
	else:
		if direction != Vector3.ZERO:
			cam_angle_diff = 0.0
		else:
			if tip_timer > tip_cool_down:
				cam_angle_diff = rad_to_deg(forward_direction.signed_angle_to(cam_direction, Vector3.UP))


func handle_strafe_animation(delta):
	#handle strafe blend
	targetspeed = Vector2(input_dir.x, input_dir.y).normalized()
	currentspeed = currentspeed.move_toward(-targetspeed, strafe_acceleration * delta)
	strafe_input = Vector2(currentspeed.x, -currentspeed.y)
	animation_tree.set("parameters/WALK/blend_position", strafe_input)


func handle_turn_in_place(_delta):
	#Handle turn in place
	if !enable_tip:
		return

	if direction != Vector3.ZERO:
		animation_tree.set("parameters/TIP/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	else:
		if tip_timer > tip_cool_down:
			if !turn_in_place:
				if cam_angle_diff >= 60:
					animation_tree.set("parameters/TIP Transition/transition_request", "left")
					animation_tree.set("parameters/TIP/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

				elif cam_angle_diff <= -70:
					animation_tree.set("parameters/TIP Transition/transition_request", "right")
					animation_tree.set("parameters/TIP/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	
