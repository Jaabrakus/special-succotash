class_name GunsmithAnimationAssetCatalog
extends RefCounted

## Finds imported animation assets and turns file layout into stable, searchable
## Gunsmith entries. Scene and preview ownership remain in the lab.

var entries: Array[Dictionary] = []
var paths: Dictionary = {}


func scan(root_path: String) -> Dictionary:
	entries.clear()
	paths.clear()
	_scan_directory(root_path)
	entries.sort_custom(func(a: Dictionary, b: Dictionary):
		return String(a.get("display", "")).naturalnocasecmp_to(String(b.get("display", ""))) < 0
	)
	return {
		"entries": entries.duplicate(true),
		"paths": paths.duplicate(true),
	}


func _scan_directory(directory_path: String) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while file_name != "":
		if directory.current_is_dir() and not file_name.begins_with("."):
			_scan_directory("%s/%s" % [directory_path, file_name])
		elif file_name.ends_with(".fbx") and not file_name.begins_with("."):
			_register_file(directory_path, file_name)
		file_name = directory.get_next()
	directory.list_dir_end()


func _register_file(directory_path: String, file_name: String) -> void:
	var full_path := "%s/%s" % [directory_path, file_name]
	var folder := directory_path.get_file()
	var tag := ""
	if "Pistol" in folder:
		tag = "[Pistol] "
	elif "Locomotion" in folder or "Lite" in folder:
		tag = "[Rifle] "
	elif "Shooter" in folder:
		tag = "[Shooter] "
	var key := StringName("gunsmith_catalog_%s" % abs(full_path.hash()))
	paths[key] = full_path
	entries.append({
		"key": key,
		"display": tag + file_name.get_basename().capitalize(),
		"path": full_path,
	})
