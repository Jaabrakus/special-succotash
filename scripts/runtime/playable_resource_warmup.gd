class_name SocomPlayableResourceWarmup
extends RefCounted

## Loads large playable resources while the launcher remains responsive. The
## references are held through the scene change, then released after the map,
## operator, and shared animation library have adopted them.

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const OperatorAnimationDriver := preload("res://scripts/player/operator_animation_driver.gd")
const TROOPER_SCENE_PATH := (
	"res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"
)
const ENVIRONMENT_TEXTURE_PATHS: Array[String] = [
	"res://assets/textures/environment/original_materials/broadleaf_foliage_albedo_v1.png",
	"res://assets/textures/environment/original_materials/dark_concrete_albedo_v1.png",
	"res://assets/textures/environment/original_materials/dry_grass_albedo_v1.png",
	"res://assets/textures/environment/original_materials/packed_earth_albedo_v1.png",
	"res://assets/textures/environment/original_materials/pine_bark_albedo_v1.png",
	"res://assets/textures/environment/original_materials/pine_needles_albedo_v1.png",
	"res://assets/textures/environment/original_materials/rough_rock_albedo_v1.png",
	"res://assets/textures/environment/original_materials/warm_masonry_albedo_v1.png",
]

static var held_resources: Array[Resource] = []
static var last_requested_paths: PackedStringArray = PackedStringArray()
static var operator_cache_warmed_for_session := false


static func warm_for_play(
	tree: SceneTree,
	scene_path: String,
	map_document: Dictionary,
	progress_callback: Callable = Callable()
) -> void:
	if (
		DisplayServer.get_name() == "headless"
		and not OS.get_cmdline_user_args().has("--test-playable-warmup")
	):
		return
	var paths := _collect_paths(scene_path, map_document)
	last_requested_paths = PackedStringArray(paths)
	var pending: Array[String] = []
	for path in paths:
		if ResourceLoader.has_cached(path):
			var cached := ResourceLoader.load(path)
			if cached != null:
				held_resources.append(cached)
			continue
		var error := ResourceLoader.load_threaded_request(path)
		if error == OK:
			pending.append(path)
	var total := maxi(pending.size(), 1)
	if progress_callback.is_valid():
		progress_callback.call(0.02)
	await tree.process_frame
	while not pending.is_empty():
		for index in range(pending.size() - 1, -1, -1):
			var path := pending[index]
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				var resource := ResourceLoader.load_threaded_get(path)
				if resource != null:
					held_resources.append(resource)
				pending.remove_at(index)
			elif status in [
				ResourceLoader.THREAD_LOAD_FAILED,
				ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
			]:
				pending.remove_at(index)
		if progress_callback.is_valid():
			progress_callback.call(
				(1.0 - float(pending.size()) / float(total)) * 0.86
			)
		await tree.process_frame
	if progress_callback.is_valid():
		progress_callback.call(0.90)
	await tree.process_frame
	_warm_operator_animation_cache(tree)
	if progress_callback.is_valid():
		progress_callback.call(1.0)


static func release() -> void:
	held_resources.clear()


static func _warm_operator_animation_cache(tree: SceneTree) -> void:
	if operator_cache_warmed_for_session:
		return
	var temporary_root := Node3D.new()
	temporary_root.name = "PlayableOperatorWarmup"
	temporary_root.process_mode = Node.PROCESS_MODE_DISABLED
	tree.root.add_child(temporary_root)
	var driver := OperatorAnimationDriver.new()
	driver.name = "WarmupAnimationDriver"
	temporary_root.add_child(driver)
	operator_cache_warmed_for_session = true
	temporary_root.free()


static func _collect_paths(scene_path: String, map_document: Dictionary) -> Array[String]:
	var unique: Dictionary = {}
	_add_path(unique, scene_path)
	_add_path(unique, TROOPER_SCENE_PATH)
	for path in ENVIRONMENT_TEXTURE_PATHS:
		_add_path(unique, path)
	for preset: Dictionary in MapDocument.SURFACE_PRESETS.values():
		_add_path(unique, String(preset.get("texture_path", "")))
	var equipped := WeaponContract.load_equipped_config()
	_add_path(unique, String(equipped.get("model_fbx", "")))
	_collect_resource_strings(map_document, unique)
	var result: Array[String] = []
	result.assign(unique.keys())
	result.sort()
	return result


static func _collect_resource_strings(value: Variant, unique: Dictionary) -> void:
	if value is Dictionary:
		for child in (value as Dictionary).values():
			_collect_resource_strings(child, unique)
	elif value is Array:
		for child in value:
			_collect_resource_strings(child, unique)
	elif value is String:
		_add_path(unique, String(value))


static func _add_path(unique: Dictionary, path: String) -> void:
	if path.begins_with("res://") and ResourceLoader.exists(path):
		unique[path] = true
