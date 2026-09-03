@tool
extends SceneTree

const WEAPON_SPECS := {
	"assault_rifle": {"target_length_m": 0.82, "grip_ratio": 0.25, "foregrip_ratio": 0.60},
	"submachinegun": {"target_length_m": 0.62, "grip_ratio": 0.28, "foregrip_ratio": 0.55},
	"pistol": {"target_length_m": 0.22, "grip_ratio": 0.35, "foregrip_ratio": 0.45},
	"shotgun": {"target_length_m": 0.95, "grip_ratio": 0.25, "foregrip_ratio": 0.58},
	"sniper": {"target_length_m": 1.15, "grip_ratio": 0.22, "foregrip_ratio": 0.55},
	"bullpup": {"target_length_m": 0.72, "grip_ratio": 0.45, "foregrip_ratio": 0.70},
}

func _init() -> void:
	print("=== SOCOM-141 AUTOMATED WEAPON SCALER & SOCKET GENERATOR ===")
	var count := process_all_weapons()
	print("Successfully processed and saved %d weapon scenes!" % count)
	quit(0)

func process_all_weapons() -> int:
	var files: Array[Dictionary] = [
		{"name": "m4a1", "fbx": "res://assets/weapons/modular_pack/AssaultRifle_1.fbx", "type": "assault_rifle"},
		{"name": "ak47", "fbx": "res://assets/weapons/ps1_ak47/source/ak-47.fbx", "type": "assault_rifle"},
		{"name": "mp5", "fbx": "res://assets/weapons/modular_pack/SubMachineGun_1.fbx", "type": "submachinegun"},
		{"name": "m16a2", "fbx": "res://assets/weapons/modular_pack/AssaultRifle2_1.fbx", "type": "assault_rifle"},
		{"name": "shotgun_1", "fbx": "res://assets/weapons/modular_pack/Shotgun_1.fbx", "type": "shotgun"},
		{"name": "sniperrifle_1", "fbx": "res://assets/weapons/modular_pack/SniperRifle_1.fbx", "type": "sniper"},
		{"name": "pistol_1", "fbx": "res://assets/weapons/modular_pack/Pistol_1.fbx", "type": "pistol"},
	]
	var processed := 0
	for item in files:
		if _process_weapon(item):
			processed += 1
	return processed

func _process_weapon(item: Dictionary) -> bool:
	var weapon_name: String = item["name"]
	var fbx_path: String = item["fbx"]
	var type: String = item["type"]
	var spec: Dictionary = WEAPON_SPECS.get(type, WEAPON_SPECS["assault_rifle"])

	if not ResourceLoader.exists(fbx_path):
		print("Skipping %s: file not found (%s)" % [weapon_name, fbx_path])
		return false

	var fbx_scene := load(fbx_path) as PackedScene
	if fbx_scene == null:
		print("Failed to load PackedScene for %s" % weapon_name)
		return false

	var temp_instance := fbx_scene.instantiate() as Node3D
	var aabb := _calculate_combined_aabb(temp_instance)
	temp_instance.free()

	# Determine primary length dimension (often Z or X depending on export orientation)
	var raw_length := aabb.size.z
	var rot_y_deg := 0.0
	if aabb.size.x > aabb.size.z and aabb.size.x > aabb.size.y:
		raw_length = aabb.size.x
		rot_y_deg = 90.0

	var target_len: float = spec["target_length_m"]
	var scale_factor := target_len / maxf(0.001, raw_length)

	# Build the clean scene tree
	var root := Node3D.new()
	root.name = weapon_name.to_upper()

	var mesh_node := fbx_scene.instantiate() as Node3D
	mesh_node.name = "WeaponMesh"
	mesh_node.scale = Vector3.ONE * scale_factor
	if rot_y_deg != 0.0:
		mesh_node.rotation_degrees.y = rot_y_deg
	root.add_child(mesh_node)
	mesh_node.owner = root

	# Compute proportional sockets in weapon space
	var grip_ratio: float = spec["grip_ratio"]
	var foregrip_ratio: float = spec["foregrip_ratio"]

	var half_len := target_len * 0.5
	var muzzle_z := half_len
	var buttstock_z := -half_len
	var grip_z := -half_len + (target_len * grip_ratio)
	var foregrip_z := -half_len + (target_len * foregrip_ratio)

	var y_center := (aabb.position.y + aabb.size.y * 0.5) * scale_factor
	var y_top := (aabb.position.y + aabb.size.y * 0.85) * scale_factor
	var y_bottom := (aabb.position.y + aabb.size.y * 0.15) * scale_factor
	var x_side := (aabb.size.x * 0.5) * scale_factor

	_add_socket(mesh_node, root, "Socket_RightHand", Vector3(0.0, y_bottom, grip_z))
	_add_socket(mesh_node, root, "Socket_LeftHand", Vector3(0.0, y_center, foregrip_z))
	_add_socket(mesh_node, root, "Socket_Muzzle", Vector3(0.0, y_center, muzzle_z))
	_add_socket(mesh_node, root, "Socket_BarrelBase", Vector3(0.0, y_center, grip_z + (foregrip_z - grip_z) * 0.5))
	_add_socket(mesh_node, root, "Socket_Buttstock", Vector3(0.0, y_center, buttstock_z))
	_add_socket(mesh_node, root, "Socket_Ejection", Vector3(x_side * 0.8, y_top * 0.85, grip_z + 0.05))
	_add_socket(mesh_node, root, "Socket_Optic", Vector3(0.0, y_top, grip_z + 0.02))

	var packed := PackedScene.new()
	var result := packed.pack(root)
	if result == OK:
		var save_path := "res://scenes/weapons/%s.tscn" % weapon_name.to_lower()
		ResourceSaver.save(packed, save_path)
		print("Saved weapon scene: %s (scale=%.4f, length=%.2fm)" % [save_path, scale_factor, target_len])
		root.free()
		return true
	else:
		print("Failed to pack scene for %s, error code: %d" % [weapon_name, result])
		root.free()
		return false

func _add_socket(parent: Node, scene_owner: Node, socket_name: String, local_pos: Vector3) -> void:
	var marker := Marker3D.new()
	marker.name = socket_name
	marker.position = local_pos
	parent.add_child(marker)
	marker.owner = scene_owner

func _calculate_combined_aabb(node: Node) -> AABB:
	var aabb := AABB()
	var first := true
	for child in node.find_children("*", "VisualInstance3D", true, false):
		var vi := child as VisualInstance3D
		if vi != null:
			var child_aabb := vi.get_aabb()
			if first:
				aabb = child_aabb
				first = false
			else:
				aabb = aabb.merge(child_aabb)
	if first:
		return AABB(Vector3(-0.05, -0.1, -0.4), Vector3(0.1, 0.2, 0.8))
	return aabb
