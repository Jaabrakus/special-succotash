extends RefCounted

const WeaponAnimationProfile := preload("res://scripts/weapons/weapon_animation_profile.gd")
const WEAPON_BASE_PATH := "res://assets/weapons/modular_pack/"

static func load_weapon(lab: Node,file_name: String) -> void:
	lab.selected_weapon_file = file_name
	lab.weapon_name = file_name
	lab._reset_fire_profile_defaults()
	lab.handling_profile = WeaponAnimationProfile.build_default(
		WeaponAnimationProfile.infer_family(lab.weapon_name, lab.selected_category),
		lab.animation_catalog.clip_paths if lab.animation_catalog else {}
	)

	lab._set_weapon_ik_enabled(false)
	lab._set_save_enabled(false)
	lab.weapon_master_pose_initialized = false

	if lab.current_weapon_mesh:
		lab.current_weapon_mesh.queue_free()
		lab.current_weapon_mesh = null
	if lab.current_silencer_mesh:
		lab.current_silencer_mesh.queue_free()
		lab.current_silencer_mesh = null
	if lab.current_scope_mesh:
		lab.current_scope_mesh.queue_free()
		lab.current_scope_mesh = null
	if lab.reload_magazine_proxy:
		lab.reload_magazine_proxy.queue_free()
		lab.reload_magazine_proxy = null

	var is_ak := (file_name == "ak-47")
	var is_9mm := (file_name == "9mm_pistol")
	var path := ""
	if is_ak:
		path = "res://assets/weapons/ps1_ak47/source/ak-47.fbx"
	elif is_9mm:
		path = "res://assets/weapons/9mm_pistol/source/model/model.dae"
	else:
		path = WEAPON_BASE_PATH + file_name + ".fbx"

	var scene := load(path) as PackedScene
	if not scene:
		push_error("Could not load weapon scene: %s" % path)
		return

	lab.current_weapon_mesh = scene.instantiate() as Node3D
	if lab.geometry_root == null and lab.weapon_pivot != null:
		lab.geometry_root = Node3D.new()
		lab.geometry_root.name = "GeometryRoot"
		lab.weapon_pivot.add_child(lab.geometry_root)
	if lab.socket_root == null and lab.weapon_pivot != null:
		lab.socket_root = Node3D.new()
		lab.socket_root.name = "SocketRoot"
		lab.weapon_pivot.add_child(lab.socket_root)

	lab.geometry_root.add_child(lab.current_weapon_mesh)

	var effective_size := Vector3.ZERO
	for c in lab.current_weapon_mesh.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			var mi: MeshInstance3D = c
			var raw_aabb = mi.mesh.get_aabb()
			effective_size = raw_aabb.size * mi.scale

	var true_raw_length := maxf(effective_size.x, maxf(effective_size.y, effective_size.z))
	var target_len := 0.68
	if "Pistol" in file_name or "Revolver" in file_name or is_9mm:
		target_len = 0.22
	elif "Submachine" in file_name or "Bullpup" in file_name:
		target_len = 0.50
	elif "Sniper" in file_name:
		target_len = 0.95
	elif "Shotgun" in file_name:
		target_len = 0.72

	if true_raw_length > 0.01:
		lab.auto_normalized_scale = (target_len / true_raw_length)
	else:
		lab.auto_normalized_scale = 0.13

	if is_ak:
		lab.auto_normalized_scale = 0.028
		lab.current_weapon_mesh.rotation_degrees = Vector3(0, 180, 0)
		lab.auto_grip_center_offset = Vector3(0.0, 0.01, -0.07)
		var ak_mat := StandardMaterial3D.new()
		ak_mat.albedo_texture = preload("res://assets/weapons/ps1_ak47/textures/AK-47TextureMap.png")
		ak_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		for c in lab.current_weapon_mesh.get_children():
			if c is MeshInstance3D: (c as MeshInstance3D).material_override = ak_mat
	elif is_9mm:
		lab.auto_normalized_scale = 0.025
		lab.current_weapon_mesh.rotation_degrees = Vector3(0, -90, 0)
		lab.auto_grip_center_offset = Vector3(0.0, -0.01, -0.04)
		lab._apply_9mm_textures(lab.current_weapon_mesh)
	else:
		lab.current_weapon_mesh.rotation_degrees = Vector3(0, -90, 0)
		lab.auto_grip_center_offset = Vector3(0.0, -0.015, -target_len * 0.26)
		lab._apply_camo_skin_to_weapon(lab.current_weapon_mesh, lab.selected_camo_idx)

	# Sockets directly attached to SocketRoot (in unscaled WeaponPivot meter-space)
	if lab.left_grip_marker: lab.left_grip_marker.queue_free()
	if lab.right_grip_marker: lab.right_grip_marker.queue_free()
	if lab.muzzle_marker: lab.muzzle_marker.queue_free()
	if lab.barrel_base_marker: lab.barrel_base_marker.queue_free()
	if lab.ejection_marker: lab.ejection_marker.queue_free()
	if lab.optic_marker: lab.optic_marker.queue_free()

	lab.left_grip_marker = lab._create_marker(Color(0.0, 0.95, 1.0), "Socket_LeftHand", 0.016)
	lab.right_grip_marker = lab._create_marker(Color(1.0, 0.55, 0.08), "Socket_RightHand", 0.012)
	lab.muzzle_marker = lab._create_marker(Color(1.0, 0.2, 0.2), "Socket_Muzzle", 0.016)
	lab.barrel_base_marker = lab._create_marker(Color(1.0, 0.4, 0.4), "Socket_BarrelBase", 0.012)
	lab.ejection_marker = lab._create_marker(Color(1.0, 0.85, 0.1), "Socket_Ejection", 0.012)
	lab.optic_marker = lab._create_marker(Color(0.2, 1.0, 0.4), "Socket_Optic", 0.012)

	lab.socket_root.add_child(lab.left_grip_marker)
	lab.socket_root.add_child(lab.right_grip_marker)
	lab.socket_root.add_child(lab.muzzle_marker)
	lab.socket_root.add_child(lab.barrel_base_marker)
	lab.socket_root.add_child(lab.ejection_marker)
	lab.socket_root.add_child(lab.optic_marker)

	lab._setup_unscaled_hand_gizmo()
	lab._setup_unscaled_weapon_gizmo()
	lab._set_active_gizmo(lab.active_gizmo_id)

	lab.left_grip_local_pos = Vector3(-0.04, -0.04, -0.30)
	lab.right_grip_local_pos = Vector3.ZERO
	lab.right_grip_profile_loaded = false
	lab.right_grip_needs_initialization = false
	lab.muzzle_local_pos = Vector3(0.0, 0.0, -target_len)
	lab.barrel_base_local_pos = Vector3(0.0, 0.0, -0.12)
	lab.ejection_local_pos = Vector3(0.05, 0.03, -0.10)
	lab.optic_local_pos = Vector3(0.0, 0.08, -0.18)

	lab._reset_gun_placement_line_profile()
	lab._try_load_saved_profile(lab.weapon_name)
	lab._setup_reload_magazine_proxy()

	if lab.selected_silencer != "None": lab._load_silencer(lab.selected_silencer)
	if lab.selected_scope != "None": lab._load_scope(lab.selected_scope)
	lab._refresh_handling_ui()

	lab.call_deferred("_finish_weapon_bootstrap")


static func setup_reload_magazine_proxy(lab: Node) -> void:
	# The modular rifle FBX is one baked mesh, so it has no detachable magazine
	# node. This separate presentation prop makes handoff timing editable without
	# destructively rewriting the imported source asset.
	lab.reload_magazine_proxy = MeshInstance3D.new()
	lab.reload_magazine_proxy.name = "ReloadMagazineVisual"
	var magazine_mesh := BoxMesh.new()
	magazine_mesh.size = Vector3(0.034, 0.145, 0.055)
	lab.reload_magazine_proxy.mesh = magazine_mesh
	var magazine_material := StandardMaterial3D.new()
	magazine_material.albedo_color = Color(0.075, 0.085, 0.09)
	magazine_material.metallic = 0.72
	magazine_material.roughness = 0.34
	lab.reload_magazine_proxy.material_override = magazine_material
	lab.reload_magazine_proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	lab.reload_magazine_proxy.visible = false
	lab.add_child(lab.reload_magazine_proxy)

static func apply_9mm_textures(lab: Node,node: Node) -> void:
	var body_tex = load("res://assets/weapons/9mm_pistol/textures/Body_albedo.jpeg") as Texture2D
	var slide_tex = load("res://assets/weapons/9mm_pistol/textures/Slide_albedo.jpeg") as Texture2D
	var mag_tex = load("res://assets/weapons/9mm_pistol/textures/Magazine_albedo.jpeg") as Texture2D

	for c in node.get_children():
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			var mat := StandardMaterial3D.new()
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			if "Body" in mi.name: mat.albedo_texture = body_tex
			elif "Slide" in mi.name: mat.albedo_texture = slide_tex
			elif "Mag" in mi.name: mat.albedo_texture = mag_tex
			else: mat.albedo_color = Color(0.2, 0.2, 0.2)
			mi.material_override = mat

static func apply_camo_skin_to_weapon(lab: Node,node: Node, camo_idx: int) -> void:
	var wood_color := Color(0.38, 0.24, 0.14)
	var steel_color := Color(0.22, 0.24, 0.26)
	var poly_color := Color(0.12, 0.12, 0.13)
	var bolt_color := Color(0.45, 0.48, 0.52)

	match camo_idx:
		1: # SOCOM Desert Tan
			wood_color = Color(0.72, 0.60, 0.44)
			steel_color = Color(0.55, 0.48, 0.36)
			poly_color = Color(0.20, 0.18, 0.15)
			bolt_color = Color(0.35, 0.35, 0.35)
		2: # SOCOM Woodland OD
			wood_color = Color(0.28, 0.35, 0.22)
			steel_color = Color(0.22, 0.25, 0.20)
			poly_color = Color(0.14, 0.16, 0.12)
			bolt_color = Color(0.40, 0.42, 0.40)
		3: # Midnight Spec-Ops
			wood_color = Color(0.08, 0.08, 0.09)
			steel_color = Color(0.12, 0.13, 0.14)
			poly_color = Color(0.06, 0.06, 0.07)
			bolt_color = Color(0.25, 0.25, 0.27)
		4: # Arctic Whiteout
			wood_color = Color(0.85, 0.88, 0.90)
			steel_color = Color(0.70, 0.75, 0.80)
			poly_color = Color(0.30, 0.35, 0.40)
			bolt_color = Color(0.60, 0.65, 0.70)
		5: # Titanium & Carbon
			wood_color = Color(0.15, 0.15, 0.16)
			steel_color = Color(0.65, 0.68, 0.72)
			poly_color = Color(0.10, 0.10, 0.11)
			bolt_color = Color(0.80, 0.82, 0.85)

	for c in node.get_children():
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			mi.material_override = null
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
