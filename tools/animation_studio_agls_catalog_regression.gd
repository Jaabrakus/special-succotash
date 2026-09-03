extends SceneTree

const Repository := preload("res://scripts/labs/animation_workshop_repository.gd")
const AGLS_IMPORTED_ROOT := "res://assets/external/agls_intake/imported"

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var repository := Repository.new()
	var scenes := repository.scan_imported_scenes(AGLS_IMPORTED_ROOT, "AGLS")
	_expect(scenes.size() == 1676, "Animation Studio discovers all 1,676 AGLS scenes")
	_expect(_has_path_fragment(scenes, "/weapon_reload/ALSP2_Reloading_Rifle_M4A4.scn"), "M4A4 reload is discoverable")
	_expect(_has_path_fragment(scenes, "/weapon_reload/ALSP2_Reload_Pistol.scn"), "pistol reload is discoverable")
	_expect(_has_path_fragment(scenes, "/weapon_recoil/ALSv2_Rifle_Recoil_Offset_01.scn"), "rifle recoil is discoverable")
	_expect(_has_path_fragment(scenes, "/locomotion_run/"), "run library is discoverable")
	_expect(_has_path_fragment(scenes, "/locomotion_crouch/"), "crouch library is discoverable")
	var entries := repository.build_entries([], scenes, {})
	_expect(entries.size() == 1676, "imported scenes become previewable clip entries")
	var reload_entry: Dictionary = {}
	for entry in entries:
		if "/weapon_reload/ALSP2_Reloading_Rifle_M4A4.scn" in String(entry.get("path", "")):
			reload_entry = entry
			break
	_expect(String(reload_entry.get("type", "")) == "FBX", "AGLS scene uses the existing retarget playback path")
	_expect(repository.suggest_slot(reload_entry) == "reload", "reload clip suggests the reload state")
	_finish()


func _has_path_fragment(entries: Dictionary, fragment: String) -> bool:
	for path_value in entries.values():
		if fragment in String(path_value):
			return true
	return false


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("ANIMATION_STUDIO_AGLS_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("ANIMATION_STUDIO_AGLS_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("ANIMATION_STUDIO_AGLS_CATALOG_REGRESSION PASS")
		quit(0)
	else:
		print("ANIMATION_STUDIO_AGLS_CATALOG_REGRESSION FAIL ", failures)
		quit(1)
