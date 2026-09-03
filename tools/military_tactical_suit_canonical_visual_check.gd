extends SceneTree

const DEFAULT_SUIT_SCENE_PATH := (
	"res://assets/characters/military_tactical_suit/military_tactical_suit_canonical.glb"
)
const RETARGET_SERVICE := preload(
	"res://scripts/labs/animation_retarget_service.gd"
)
const ROOT_SANITIZER := preload(
	"res://scripts/player/operator_animation_root_sanitizer.gd"
)
const DEFAULT_CAPTURE_PATH := "/private/tmp/military-tactical-suit-canonical-poses.png"
const POSES := [
	{"label": "REST / CANONICAL 65", "path": "", "time": 0.0},
	{
		"label": "AIM IDLE",
		"path": "res://assets/animations/mixamo/Shooter Pack/rifle aiming idle.fbx",
		"time": 0.5,
	},
	{
		"label": "RUN FORWARD",
		"path": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/sprint forward.fbx",
		"time": 0.45,
	},
	{
		"label": "CROUCH IDLE",
		"path": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/idle crouching.fbx",
		"time": 0.5,
	},
	{
		"label": "PRONE IDLE",
		"path": "res://assets/animations/mixamo/Prone Forward Stop.fbx",
		"time": 0.5,
	},
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var suit_path := OS.get_environment("TACTICAL_SUIT_ASSET")
	if suit_path.is_empty():
		suit_path = DEFAULT_SUIT_SCENE_PATH
	var capture_path := OS.get_environment("TACTICAL_SUIT_CAPTURE")
	if capture_path.is_empty():
		capture_path = DEFAULT_CAPTURE_PATH
	var suit_scene := load(suit_path) as PackedScene
	if suit_scene == null:
		push_error("CANONICAL_SUIT_VISUAL_CHECK could not load %s" % suit_path)
		quit(1)
		return
	root.size = Vector2i(1600, 900)
	_setup_world()
	for index in range(POSES.size()):
		var pose: Dictionary = POSES[index]
		var model := suit_scene.instantiate() as Node3D
		model.position.x = (float(index) - 2.0) * 1.85
		root.add_child(model)
		_add_label(model, String(pose.label))
		if not String(pose.path).is_empty():
			_play_pose(model, StringName("pose_%d" % index), String(pose.path), float(pose.time))
	for _frame in range(24):
		await process_frame
	if DisplayServer.get_name() == "headless":
		push_error("CANONICAL_SUIT_VISUAL_CHECK requires a display-backed run")
		quit(1)
		return
	RenderingServer.force_draw()
	await process_frame
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(capture_path) != OK:
		push_error("CANONICAL_SUIT_VISUAL_CHECK could not save the review image")
		quit(1)
		return
	print("CANONICAL_SUIT_VISUAL_CHECK PASS %s" % capture_path)
	quit(0)


func _setup_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("18202a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("72849a")
	environment.ambient_light_energy = 0.28
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	key.light_energy = 0.72
	key.shadow_enabled = true
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
	fill.light_color = Color("8bb7df")
	fill.light_energy = 0.22
	root.add_child(fill)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 12.0)
	floor.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("465464")
	material.roughness = 0.95
	floor.material_override = material
	root.add_child(floor)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.15, 10.2)
	camera.fov = 43.0
	camera.current = true
	root.add_child(camera)
	camera.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)


func _add_label(model: Node3D, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = Vector3(0.0, 2.35, 0.0)
	label.font_size = 34
	label.outline_size = 8
	label.modulate = Color("8be0bd")
	label.no_depth_test = true
	model.add_child(label)


func _play_pose(model: Node3D, key: StringName, path: String, normalized_time: float) -> void:
	var skeleton := _find_skeleton(model)
	if skeleton == null:
		return
	var player := AnimationPlayer.new()
	player.name = "VisualCheckPlayer"
	skeleton.add_child(player)
	player.root_node = player.get_path_to(skeleton)
	var library := AnimationLibrary.new()
	player.add_animation_library("canonical", library)
	var loaded: bool = RETARGET_SERVICE.new().load_fbx(
		{"key": key, "path": path},
		library,
		player,
		skeleton,
		true,
		{},
		false,
		ROOT_SANITIZER,
		false
	)
	if not loaded:
		return
	var animation := library.get_animation(key)
	player.play(StringName("canonical/%s" % key))
	player.seek(animation.length * normalized_time, true)
	player.advance(0.0)
	skeleton.force_update_all_bone_transforms()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
