extends SceneTree

## Renders an exported Auto-Rig Pro GLB directly, without the player controller,
## pose layers, weapon IK, grounding, or runtime adapter. This isolates Blender
## export/Godot import deformation from every live gameplay correction.

const DEFAULT_CANDIDATE := (
	"res://assets/characters/operator_rig_v2/"
	+ "operator_autorigpro_gameplay_library_additive_voxel_v1_humanoid.glb"
)
const OUTPUT_DIRECTORY := "/private/tmp/socom-operator-glb-direct-probe"
const ACTIONS := [&"native__aim_idle", &"native__run_forward_left", &"native__idle_crouch"]

var failures: Array[String] = []
var scene_root: Node3D
var camera: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIRECTORY)
	root.size = Vector2i(1200, 900)
	var candidate := OS.get_environment("OPERATOR_ARP_CANDIDATE")
	if candidate.is_empty():
		candidate = DEFAULT_CANDIDATE
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var source_path := (
		ProjectSettings.globalize_path(candidate) if candidate.begins_with("res://") else candidate
	)
	var import_error := document.append_from_file(source_path, state)
	_expect(import_error == OK, "candidate GLB parses directly")
	if import_error != OK:
		_finish()
		return
	scene_root = Node3D.new()
	root.add_child(scene_root)
	var instance := document.generate_scene(state) as Node3D
	_expect(instance != null, "candidate GLB instantiates directly")
	if instance == null:
		_finish()
		return
	scene_root.add_child(instance)
	var player := _find_first(instance, "AnimationPlayer") as AnimationPlayer
	var skeleton := _find_first(instance, "Skeleton3D") as Skeleton3D
	_expect(player != null, "direct GLB contains an AnimationPlayer")
	_expect(skeleton != null, "direct GLB contains a Skeleton3D")
	if player == null or skeleton == null:
		_finish()
		return
	_install_stage()
	await _frames(4)
	for token in ACTIONS:
		var action := _resolve_action(player.get_animation_list(), token)
		_expect(not action.is_empty(), "%s exists in direct GLB" % token)
		if action.is_empty():
			continue
		var animation := player.get_animation(action)
		player.play(action)
		player.seek(animation.length * 0.53, true)
		player.advance(0.0)
		await _frames(4)
		await _capture(String(token))
	_finish()


func _install_stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("63798b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.78, 0.82)
	environment.ambient_light_energy = 1.15
	var world := WorldEnvironment.new()
	world.environment = environment
	scene_root.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	light.light_energy = 1.25
	light.shadow_enabled = true
	scene_root.add_child(light)
	camera = Camera3D.new()
	camera.fov = 38.0
	camera.current = true
	scene_root.add_child(camera)


func _capture(label: String) -> void:
	var posed_bounds := _posed_mesh_bounds(scene_root)
	var target := posed_bounds.get_center()
	var half_height := maxf(posed_bounds.size.y * 0.5, 0.5)
	var distance := maxf(half_height / tan(deg_to_rad(camera.fov * 0.5)) * 1.25, 2.5)
	var views := {
		"front": Vector3(0.12, 0.04, 1.0).normalized(),
		"side": Vector3(1.0, 0.04, 0.12).normalized(),
		"rear": Vector3(-0.12, 0.04, -1.0).normalized(),
	}
	for view_name in views:
		camera.position = target + Vector3(views[view_name]) * distance
		camera.look_at(target, Vector3.UP)
		await _frames(3)
		RenderingServer.force_draw()
		await process_frame
		var image := root.get_texture().get_image()
		var path := "%s/%s_%s.png" % [OUTPUT_DIRECTORY, label, view_name]
		_expect(image != null and not image.is_empty(), "%s capture is readable" % path)
		if image != null and not image.is_empty():
			_expect(image.save_png(path) == OK, "%s capture saves" % path)


func _posed_mesh_bounds(node: Node) -> AABB:
	var points: Array[Vector3] = []
	_collect_mesh_bounds(node, points)
	_expect(not points.is_empty(), "posed mesh bounds are available")
	if points.is_empty():
		return AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds


func _collect_mesh_bounds(node: Node, points: Array[Vector3]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var bounds := mesh_instance.get_aabb()
		for x in [bounds.position.x, bounds.end.x]:
			for y in [bounds.position.y, bounds.end.y]:
				for z in [bounds.position.z, bounds.end.z]:
					points.append(mesh_instance.global_transform * Vector3(x, y, z))
	for child in node.get_children():
		_collect_mesh_bounds(child, points)


func _resolve_action(available: PackedStringArray, token: StringName) -> StringName:
	for candidate in available:
		var name := String(candidate)
		if name == token or name.ends_with("/" + token) or token in name:
			return StringName(name)
	return &""


func _find_first(node: Node, class_name_value: String) -> Node:
	if node.is_class(class_name_value):
		return node
	for child in node.get_children():
		var found := _find_first(child, class_name_value)
		if found != null:
			return found
	return null


func _frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("OPERATOR_GLB_DIRECT_PROBE PASS ", label)
	else:
		failures.append(label)
		push_error("OPERATOR_GLB_DIRECT_PROBE FAIL " + label)


func _finish() -> void:
	print("OPERATOR_GLB_DIRECT_PROBE_OUTPUT ", OUTPUT_DIRECTORY)
	quit(0 if failures.is_empty() else 1)
