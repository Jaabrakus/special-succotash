extends SceneTree

const WEAPON_CONTRACT := preload("res://scripts/weapons/weapon_rig_contract.gd")
const VISUAL_RIG_RESOLVER := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_resolver.gd"
)
const RECOM_CATALOG_ADAPTER := preload(
	"res://scripts/labs/gunsmith/gunsmith_recom_catalog_adapter.gd"
)
const WEAPON_RIG_PREVIEW := preload("res://scripts/labs/weapon_rig_preview_loader.gd")
const GUNSMITH_WEAPON_PREVIEW_LOADER := preload(
	"res://scripts/labs/gunsmith/gunsmith_weapon_preview_loader.gd"
)
const TARGET_CATEGORIES := {
	"Pistols": true,
	"Assault Rifles": true,
	"Submachine Guns": true,
}
const EXCLUDED_WEAPON_IDS := {
	"designator": true,
	"air_to_ground_missile": true,
	"exploding_fuel": true,
}

var failures: Array[String] = []


func _initialize() -> void:
	var raw := WEAPON_CONTRACT.load_config("res://config/weapons/m16a2.json")
	var resolved := VISUAL_RIG_RESOLVER.resolve_for_presentation(raw)
	var assigned_id := String(raw.get("visual_rig_id", ""))
	var assigned_rig := VISUAL_RIG_RESOLVER.load_published(assigned_id)
	var assigned_visual: Dictionary = assigned_rig.get("visual", {})
	_expect(not raw.is_empty(), "M16A2 gameplay profile loads")
	_expect(
		not assigned_id.is_empty() and not assigned_rig.is_empty(),
		"M16A2 references its current published golden visual rig"
	)
	_expect(
		String(resolved.get("_visual_rig_id", "")) == assigned_id,
		"presentation resolver applies the assigned visual rig"
	)
	_expect(
		String(resolved.get("model_fbx", ""))
		== String(assigned_visual.get("model_fbx", "")),
		"runtime presentation uses the assigned rifle scene"
	)
	_expect(
		is_equal_approx(
			float(resolved.get("normalized_scale", 0.0)),
			float(assigned_visual.get("normalized_scale", -1.0))
		),
		"runtime presentation uses the assigned rifle scale"
	)
	var raw_damage := float((raw.get("ballistics", {}) as Dictionary).get("damage", 0.0))
	var resolved_damage := float(
		(resolved.get("ballistics", {}) as Dictionary).get("damage", 0.0)
	)
	_expect(
		is_equal_approx(raw_damage, resolved_damage),
		"visual rig cannot change M16A2 damage"
	)
	_expect(
		raw.get("fire_modes", []) == resolved.get("fire_modes", []),
		"visual rig cannot change M16A2 fire modes"
	)
	_expect(
		resolved.get("weapon_sockets", {}) == assigned_visual.get("weapon_sockets", {}),
		"assigned visual rig supplies its calibrated presentation sockets"
	)
	var inherited_pistol := WEAPON_CONTRACT.load_config(
		"res://config/weapons/9mm_pistol.json"
	)
	_expect(
		String(inherited_pistol.get("_visual_rig_assignment", "")) == "family_model",
		"sparse 9mm pistol inherits its published model-family calibration"
	)
	_expect(
		String(inherited_pistol.get("_visual_rig_id", "")) == "family_pistol_2_v2",
		"Pistol_2 model reuses one immutable family visual rig"
	)
	var gunsmith_pistol := RECOM_CATALOG_ADAPTER.load_editable_profile("9mm_pistol")
	_expect(
		_presentation_matches(gunsmith_pistol, inherited_pistol),
		"Gunsmith sparse-pistol fields match the canonical inherited visual rig"
	)
	var gunsmith_m16 := RECOM_CATALOG_ADAPTER.load_editable_profile("m16a2")
	_expect(
		_presentation_matches(gunsmith_m16, raw),
		"Gunsmith explicit-rifle fields match the canonical assigned visual rig"
	)
	var sparse_direct := _read_dictionary("res://config/weapons/9mm_pistol.json")
	sparse_direct["visual_rig_id"] = "family_pistol_1_v2"
	var complete_pool := _read_dictionary("res://config/weapons/assaultrifle_1.json")
	var direct_selection := RECOM_CATALOG_ADAPTER.select_editable_profile_source(
		sparse_direct,
		complete_pool
	)
	var direct_presentation := VISUAL_RIG_RESOLVER.resolve_for_presentation(
		direct_selection.get("profile", {})
	)
	_expect(
		String(direct_selection.get("source", "")) == "direct_assignment"
		and String(direct_presentation.get("_visual_rig_id", ""))
			== "family_pistol_1_v2",
		"Gunsmith direct assignment wins over a complete pooled visual profile"
	)
	var studio_pistol := WEAPON_RIG_PREVIEW.load_config(
		"res://config/weapons/9mm_pistol.json"
	)
	_expect(
		_presentation_matches(studio_pistol, inherited_pistol),
		"Animation Studio preview reads the same inherited pistol presentation"
	)
	_check_all_gunsmith_firearm_profiles()
	var asset_runtime_source := _read(
		"res://scripts/player/operator_asset_runtime.gd"
	)
	var animation_runtime_source := _read(
		"res://scripts/player/operator_animation_driver_runtime.gd"
	)
	var equipment_runtime_source := _read(
		"res://scripts/player/operator_weapon_equipment_runtime.gd"
	)
	var weapon_contract_source := _read(
		"res://scripts/weapons/weapon_rig_contract.gd"
	)
	var gunsmith_preview_source := _read(
		"res://scripts/labs/gunsmith/gunsmith_weapon_preview_loader.gd"
	)
	var guns_lab_2_source := _read("res://scripts/labs/gunsmith2/guns_lab_2.gd")
	var gunsmith_preview_api_source := _read(
		"res://scripts/labs/gunsmith/gunsmith_lab_preview_api.gd"
	)
	var family_publisher_source := _read(
		"res://tools/publish_firearm_family_visual_rigs.gd"
	)
	_expect(
		"VisualRigResolver.resolve_for_presentation(raw)" in weapon_contract_source,
		"shared weapon contract owns the one presentation-resolution boundary"
	)
	_expect(
		"var equipped_config := _load_equipped_weapon_config()" in asset_runtime_source,
		"weapon mesh attachment consumes the resolved weapon contract"
	)
	_expect(
		"equipped_weapon_config = WeaponContract.load_equipped_config()"
		in animation_runtime_source,
		"arm presentation consumes the same resolved weapon contract"
	)
	_expect(
		"var next_config := WeaponContract.normalize_config(raw_config, config_path)"
		in equipment_runtime_source,
		"authorized equipment swaps cannot bypass presentation resolution"
	)
	_expect(
		"RecomCatalogAdapter.load_editable_profile(lab.weapon_name)"
		in gunsmith_preview_source,
		"Gunsmith mesh preview and editable controls share one resolved profile"
	)
	_expect(
		GUNSMITH_WEAPON_PREVIEW_LOADER != null,
		"Gunsmith resolved-preview consumer parses successfully"
	)
	_expect(
		'extends "res://scripts/labs/gun_calibration_lab.gd"' in guns_lab_2_source
		and "GunsmithWeaponPreviewLoader.load_weapon(self, file_name)"
		in gunsmith_preview_api_source,
		"Guns Lab 2 inherits the same resolved Gunsmith mesh/profile preview chain"
	)
	_expect(
		"CONTRACT.published_documents_match(existing, document)"
		in family_publisher_source,
		"family publisher verifies the complete immutable document before reuse"
	)
	_finish()


func _check_all_gunsmith_firearm_profiles() -> void:
	var checked := 0
	for file_name in DirAccess.get_files_at("res://config/weapons"):
		if not file_name.ends_with(".json"):
			continue
		var path := "res://config/weapons/%s" % file_name
		var raw_profile := _read_dictionary(path)
		var weapon_id := String(raw_profile.get("weapon_id", file_name.get_basename()))
		if (
			not TARGET_CATEGORIES.has(String(raw_profile.get("category", "")))
			or EXCLUDED_WEAPON_IDS.has(weapon_id)
		):
			continue
		var canonical := WEAPON_CONTRACT.load_config(path)
		var editable := RECOM_CATALOG_ADAPTER.load_editable_profile(weapon_id)
		checked += 1
		_expect(
			_presentation_matches(editable, canonical),
			"Gunsmith %s presentation matches canonical runtime" % weapon_id
		)
	_expect(checked >= 30, "Gunsmith parity covers every in-scope saved firearm")


func _presentation_matches(candidate: Dictionary, canonical: Dictionary) -> bool:
	return (
		String(candidate.get("_visual_rig_id", ""))
		== String(canonical.get("_visual_rig_id", ""))
		and String(candidate.get("model_fbx", ""))
		== String(canonical.get("model_fbx", ""))
		and is_equal_approx(
			float(candidate.get("normalized_scale", 0.0)),
			float(canonical.get("normalized_scale", -1.0))
		)
		and _presentation_value_matches(
			candidate.get("model_rotation_degrees", {}),
			canonical.get("model_rotation_degrees", {})
		)
		and _presentation_value_matches(
			candidate.get("operator_mount", {}),
			canonical.get("operator_mount", {})
		)
		and _presentation_value_matches(
			candidate.get("grip_offset", {}),
			canonical.get("grip_offset", {})
		)
		and _presentation_value_matches(
			candidate.get("weapon_sockets", {}),
			canonical.get("weapon_sockets", {})
		)
	)


func _presentation_value_matches(candidate: Variant, canonical: Variant) -> bool:
	if candidate is Dictionary and canonical is Dictionary:
		var candidate_map := candidate as Dictionary
		var canonical_map := canonical as Dictionary
		if candidate_map.size() != canonical_map.size():
			return false
		for key: Variant in canonical_map:
			if not candidate_map.has(key):
				return false
			if not _presentation_value_matches(candidate_map[key], canonical_map[key]):
				return false
		return true
	var candidate_type := typeof(candidate)
	var canonical_type := typeof(canonical)
	if (
		candidate_type == TYPE_INT or candidate_type == TYPE_FLOAT
	) and (
		canonical_type == TYPE_INT or canonical_type == TYPE_FLOAT
	):
		return is_equal_approx(float(candidate), float(canonical))
	return candidate == canonical


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func _read_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var value: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("GUNS_LAB_2_RUNTIME_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("GUNS_LAB_2_RUNTIME_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("GUNS_LAB_2_RUNTIME_REGRESSION PASS")
		quit(0)
	else:
		print("GUNS_LAB_2_RUNTIME_REGRESSION FAIL ", failures)
		quit(1)
