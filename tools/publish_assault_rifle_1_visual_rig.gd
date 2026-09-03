extends SceneTree

const CONTRACT := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd"
)
const SOURCE_PATH := "res://config/weapons/assaultrifle_1.json"
const OUTPUT_PATH := "res://config/weapon_visual_rigs/assaultrifle_1_v1.json"


func _initialize() -> void:
	if FileAccess.file_exists(OUTPUT_PATH):
		print("ASSAULTRIFLE_1_VISUAL_RIG already published: %s" % OUTPUT_PATH)
		quit(0)
		return
	var source_file := FileAccess.open(SOURCE_PATH, FileAccess.READ)
	var parsed: Variant = (
		JSON.parse_string(source_file.get_as_text())
		if source_file != null
		else null
	)
	if not parsed is Dictionary:
		push_error("AssaultRifle_1 source profile could not be read.")
		quit(1)
		return
	var document := CONTRACT.extract(
		parsed as Dictionary,
		"assaultrifle_1_v1",
		1,
		"published"
	)
	var validation := CONTRACT.validate(document, true)
	if not bool(validation.get("ok", false)):
		push_error("AssaultRifle_1 visual rig failed validation: %s" % [
			validation.get("errors", []),
		])
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir())
	)
	var output := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if output == null:
		push_error("AssaultRifle_1 visual rig could not be written.")
		quit(1)
		return
	output.store_string(JSON.stringify(document, "  "))
	output.close()
	print("ASSAULTRIFLE_1_VISUAL_RIG PUBLISHED %s" % OUTPUT_PATH)
	quit(0)
