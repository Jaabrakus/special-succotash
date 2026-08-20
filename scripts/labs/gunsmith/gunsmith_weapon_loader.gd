class_name GunsmithWeaponLoader
extends RefCounted

const WEAPON_BASE_PATH := "res://assets/weapons/modular_pack/"


static func get_weapon_file_path(file_name: String) -> String:
	if file_name == "ak-47":
		return "res://assets/weapons/ps1_ak47/source/ak-47.fbx"
	if file_name == "9mm_pistol":
		return "res://assets/weapons/9mm_pistol/source/model/model.dae"
	return WEAPON_BASE_PATH + file_name + ".fbx"


static func instantiate_weapon(file_name: String) -> Node3D:
	var path := get_weapon_file_path(file_name)
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if not scene:
		return null
	return scene.instantiate() as Node3D


static func apply_camo_skin(root_mesh: Node3D, camo_idx: int) -> void:
	if not root_mesh:
		return
	var wood_color := Color(0.35, 0.20, 0.10)
	var steel_color := Color(0.12, 0.12, 0.14)
	var poly_color := Color(0.08, 0.08, 0.08)
	var bolt_color := Color(0.55, 0.55, 0.60)

	match camo_idx:
		1: # Desert Tan
			poly_color = Color(0.65, 0.55, 0.38)
			wood_color = Color(0.55, 0.45, 0.30)
		2: # Olive Drab
			poly_color = Color(0.28, 0.35, 0.22)
			wood_color = Color(0.22, 0.28, 0.18)
		3: # Arctic White
			poly_color = Color(0.85, 0.88, 0.90)
			wood_color = Color(0.70, 0.72, 0.75)
		4: # SpecOps Blackout
			poly_color = Color(0.04, 0.04, 0.05)
			wood_color = Color(0.05, 0.05, 0.06)
			steel_color = Color(0.06, 0.06, 0.07)

	var stack: Array[Node] = [root_mesh]
	while not stack.is_empty():
		var node := stack.pop_back() as Node
		for child in node.get_children():
			stack.append(child)
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh:
				for s in range(mi.mesh.get_surface_count()):
					var surf_mat := mi.mesh.surface_get_material(s)
					var mat_name := surf_mat.resource_name.to_lower() if surf_mat else ""
					var sm := StandardMaterial3D.new()
					sm.roughness = 0.45
					sm.metallic = 0.75

					if "wood" in mat_name:
						sm.albedo_color = wood_color
						sm.roughness = 0.6
						sm.metallic = 0.1
					elif "darkmetal" in mat_name or "receiver" in mat_name:
						sm.albedo_color = steel_color
					elif "black" in mat_name or "grip" in mat_name or "stock" in mat_name:
						sm.albedo_color = poly_color
						sm.metallic = 0.2
					elif "metal" in mat_name or "bolt" in mat_name:
						sm.albedo_color = bolt_color
						sm.metallic = 0.9
						sm.roughness = 0.25
					else:
						sm.albedo_color = steel_color

					mi.set_surface_override_material(s, sm)
