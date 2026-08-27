extends SceneTree

## Second pass over the generated catalog weapon profiles: attaches geometry
## calibration (normalized scale, model rotation, sockets, grip) so weapons
## render at operator scale instead of raw FBX size.
##
## Sources of calibration, in priority order:
##   1. Existing geometry keys already in the profile (never overwritten, so
##      Gunsmith-authored tuning wins).
##   2. An authored sibling profile that uses the same model_fbx.
##   3. Measurement: the FBX's local AABB is measured headless; scale brings
##      the long axis to the category target length, rotation turns the long
##      axis to +X forward, and sockets are the generic template proportionally
##      fitted to the measured length.
##
## Run headless:
##   godot --headless --path . --script res://tools/calibrate_catalog_weapon_profiles.gd

const CONFIG_DIRECTORY := "res://config/weapons/"
const MODULAR_DIRECTORY := "res://assets/weapons/modular_pack/"

# The authored profiles trusted as geometry donors, most precise first.
const DONOR_ORDER: Array[String] = [
	"m16a2", "ak-47", "assaultrifle_1", "assaultrifle_2", "assaultrifle_3",
	"assaultrifle_4", "bullpup_1", "shotgun_1", "sniperrifle_1", "submachinegun_1",
]

const GEOMETRY_KEYS: Array[String] = [
	"normalized_scale",
	"model_rotation_degrees",
	"grip_offset",
	"operator_mount",
	"arm_rig_pose",
	"weapon_sockets",
	"socket_contract_authored",
]

# Generic family socket template, in normalised weapon metres, spanning
# buttstock -0.30 to muzzle +0.70 (basis length 1.0 m, +X forward).
const TEMPLATE_LENGTH := 1.0
const TEMPLATE_SOCKETS := {
	"muzzle_socket": Vector3(0.70, 0.02, 0.0),
	"left_hand_ik_target": Vector3(0.20, -0.03, 0.0),
	"ejection_port": Vector3(0.05, 0.03, 0.06),
	"optic_rail": Vector3(0.05, 0.08, 0.0),
	"barrel_base_socket": Vector3(-0.01, 0.11, -0.12),
	"buttstock_socket": Vector3(-0.01, 0.08, -0.30),
}

const TARGET_LENGTH_BY_CATEGORY := {
	"Pistols": 0.24,
	"Submachine Guns": 0.55,
	"Shotguns": 0.95,
	"Assault Rifles": 0.90,
	"Sniper Rifles": 1.05,
	"Machine Guns": 1.05,
}

var _donor_by_fbx: Dictionary = {}
var failures: int = 0


func _initialize() -> void:
	var catalog_file := FileAccess.open(CONFIG_DIRECTORY + "recom_weapons_catalog.json", FileAccess.READ)
	var catalog: Dictionary = (
		(JSON.parse_string(catalog_file.get_as_text()) as Dictionary) if catalog_file else {}
	)
	catalog_file.close()

	_index_donors()

	var calibrated: int = 0
	var inherited: int = 0
	var measured: int = 0
	var kept: int = 0
	for raw_record: Variant in (catalog.get("weapons", []) as Array):
		var record := raw_record as Dictionary
		var weapon_id := String(record.get("weapon_id", ""))
		if not TARGET_LENGTH_BY_CATEGORY.has(String(record.get("category", ""))):
			continue
		var path := CONFIG_DIRECTORY + weapon_id + ".json"
		if not FileAccess.file_exists(path):
			_fail("profile missing for %s" % weapon_id)
			continue
		var profile: Dictionary = _read_json(path)
		if profile.is_empty():
			_fail("profile unreadable for %s" % weapon_id)
			continue

		if _has_geometry(profile):
			kept += 1
			continue

		var fbx := String(profile.get("model_fbx", ""))
		var applied := false
		if _donor_by_fbx.has(fbx):
			var donor: Dictionary = _read_json(CONFIG_DIRECTORY + String(_donor_by_fbx[fbx]) + ".json")
			var copied: Array[String] = []
			for key in GEOMETRY_KEYS:
				if donor.has(key):
					profile[key] = donor[key]
					copied.append(key)
			if not copied.is_empty():
				applied = true
				inherited += 1
				print("CALIBRATE inherited %s <- %s (%s)" % [weapon_id, _donor_by_fbx[fbx], fbx.get_file()])

		if not applied:
			var derived := _derive_geometry_from_mesh(fbx, String(record.get("category", "Assault Rifles")))
			if derived.is_empty():
				_fail("could not measure %s (%s)" % [weapon_id, fbx])
				continue
			for key in derived:
				profile[key] = derived[key]
			measured += 1
			print(
				"CALIBRATE measured %s (%s) scale=%.4f rot_y=%.0f length=%.2fm" % [
					weapon_id, fbx.get_file(),
					float(derived.get("normalized_scale", 1.0)),
					float((derived.get("model_rotation_degrees", {}) as Dictionary).get("y", 0.0)),
					_derived_length(derived),
				]
			)

		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_fail("profile not writable for %s" % weapon_id)
			continue
		file.store_string(JSON.stringify(profile, "  "))
		file.close()
		calibrated += 1

	print(
		"CATALOG_PROFILE_CALIBRATION calibrated=%d (inherited=%d measured=%d) already-calibrated=%d failures=%d" % [
			calibrated, inherited, measured, kept, failures,
		]
	)
	if failures > 0:
		push_error("CATALOG_PROFILE_CALIBRATION failed")
		quit(1)
		return
	print("CATALOG_PROFILE_CALIBRATION PASS")
	quit(0)


func _fail(message: String) -> void:
	failures += 1
	push_error("CATALOG_PROFILE_CALIBRATION ERROR: " + message)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _has_geometry(profile: Dictionary) -> bool:
	return profile.has("normalized_scale") or profile.has("weapon_sockets")


func _index_donors() -> void:
	for weapon_id in DONOR_ORDER:
		var donor: Dictionary = _read_json(CONFIG_DIRECTORY + weapon_id + ".json")
		var fbx := String(donor.get("model_fbx", ""))
		if fbx.is_empty() or not donor.has("normalized_scale"):
			continue
		# More precise donors (authored sockets or non-unit scale) win the slot.
		var precise := (
			bool(donor.get("socket_contract_authored", false))
			or absf(float(donor.get("normalized_scale", 1.0)) - 1.0) > 0.001
		)
		if not _donor_by_fbx.has(fbx) or precise:
			_donor_by_fbx[fbx] = weapon_id


func _derive_geometry_from_mesh(fbx: String, category: String) -> Dictionary:
	var scene := load(fbx) as PackedScene
	if scene == null:
		return {}
	var root_node := scene.instantiate() as Node3D
	if root_node == null:
		return {}
	root.add_child(root_node)
	var aabb := _combined_aabb(root_node)
	root_node.queue_free()
	if aabb.size == Vector3.ZERO:
		return {}

	var long_axis := 0
	if aabb.size.y > aabb.size[long_axis]:
		long_axis = 1
	if aabb.size.z > aabb.size[long_axis]:
		long_axis = 2
	var target := float(TARGET_LENGTH_BY_CATEGORY.get(category, 0.9))
	var normalized_scale := target / maxf(aabb.size[long_axis], 0.0001)

	# Forward is +X in the calibrated pivot. Turn the imported long axis to +X.
	var rotation_y := 0.0
	if long_axis == 2:
		rotation_y = -90.0
	elif long_axis == 0:
		rotation_y = 0.0
	else:
		# Vertical models (unexpected) get the default rifle treatment.
		rotation_y = -90.0

	var factor := target / TEMPLATE_LENGTH
	var sockets := {}
	for socket_name: Variant in TEMPLATE_SOCKETS:
		var position: Vector3 = TEMPLATE_SOCKETS[socket_name] * Vector3(factor, 1.0, factor)
		sockets[String(socket_name)] = {"x": position.x, "y": position.y, "z": position.z}

	return {
		"normalized_scale": normalized_scale,
		"model_rotation_degrees": {"x": 0.0, "y": rotation_y, "z": 0.0},
		"grip_offset": {"pos_x": 0.0, "pos_y": 0.0, "pos_z": 0.0, "rot_x": 0.0, "rot_y": 0.0, "rot_z": 0.0},
		"weapon_sockets": sockets,
		"socket_contract_authored": false,
	}


func _combined_aabb(node: Node3D) -> AABB:
	var aabb := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var mesh_aabb := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		if first:
			aabb = mesh_aabb
			first = false
		else:
			aabb = aabb.merge(mesh_aabb)
	return aabb


func _derived_length(derived: Dictionary) -> float:
	var sockets: Dictionary = derived.get("weapon_sockets", {})
	var muzzle: Dictionary = sockets.get("muzzle_socket", {})
	var butt: Dictionary = sockets.get("buttstock_socket", {})
	return absf(float(muzzle.get("x", 0.7)) - float(butt.get("x", -0.3)))
