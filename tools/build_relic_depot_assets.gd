extends SceneTree
## Offline construction. Authored derivatives only; never edits the source rig.
const BASE := "res://art_source/sketchfab_intake_20260906/prepared/"
const OUT := "res://assets/environment/relic_depot/"
const SKIN_OUT := "res://assets/characters/relic_nvg_operator/"
var report: Dictionary = {}
const BONE_MAP := {
	"GLTF_created_0_rootJoint": "Hips", "Spinelower_11": "Hips", "Spineupper_6": "Spine1",
	"Neck_1": "Neck", "head_0": "Head",
	"ArmUpper.L_3": "LeftArm", "ArmLower.L_2": "LeftForeArm",
	"ArmUpper.R_5": "RightArm", "ArmLower.R_4": "RightForeArm",
	"LegThigh.L_8": "LeftUpLeg", "LegShin.L_7": "LeftLeg",
	"LegThigh.R_10": "RightUpLeg", "LegShin.R_9": "RightLeg",
	"Footctrl.L_14": "LeftFoot", "Foot.L_13": "LeftFoot", "FootToe.L_12": "LeftToeBase",
	"Footctrl.R_24": "RightFoot", "Foot.R_23": "RightFoot", "FootToe.R_22": "RightToeBase",
	"HandWrist.L_21": "LeftHand", "Hand.L.001_20": "LeftHand", "Fingers.L_17": "LeftHandIndex1",
	"ThumbBase.L_19": "LeftHandThumb1", "ThumgEnd.L_18": "LeftHandThumb2",
	"HandWrist.R_31": "RightHand", "Hand.R.001_30": "RightHand", "Fingers.R_27": "RightHandIndex1",
	"ThumbBase.R_29": "RightHandThumb1", "ThumgEnd.R_28": "RightHandThumb2"
}
const ENDPOINTS := {
	"ArmUpper.L_3": ["ArmLower.L_2", "LeftForeArm"], "ArmLower.L_2": ["HandWrist.L_21", "LeftHand"],
	"ArmUpper.R_5": ["ArmLower.R_4", "RightForeArm"], "ArmLower.R_4": ["HandWrist.R_31", "RightHand"],
	"LegThigh.L_8": ["LegShin.L_7", "LeftLeg"], "LegShin.L_7": ["Foot.L_13", "LeftFoot"],
	"LegThigh.R_10": ["LegShin.R_9", "RightLeg"], "LegShin.R_9": ["Foot.R_23", "RightFoot"],
	"HandWrist.L_21": ["Fingers.L_17", "LeftHandIndex1"], "Hand.L.001_20": ["Fingers.L_17", "LeftHandIndex1"],
	"HandWrist.R_31": ["Fingers.R_27", "RightHandIndex1"], "Hand.R.001_30": ["Fingers.R_27", "RightHandIndex1"]
}
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SKIN_OUT))
	var packs := {
		"psx_industrial_pack": {"BarrelOil": 0.9, "CrateWood": 1.0, "CrateMetal": 1.1, "Dumpster": 1.4, "GeneratorUnit": 1.7, "Pallet": 0.16, "Tires": 0.85, "ConcretePipePile": 1.3},
		"psx_tropical_pack_v1": {"palm_tree": 8.0, "palm_tree_001": 7.5, "palm_tree_002": 8.5, "bush": 1.1, "grass": 0.4},
		"rocks_-_psx_low_poly": {"big rock": 2.7, "mediun rock": 1.5, "mediun rock 2": 1.8},
		"psx_shipping_containers_2": {"Object_4": -6.06, "Object_5": -6.06, "Object_6": -6.06, "Object_7": -6.06},
		"psx_old_warehouse": {"PSX Old Warehouse": -18.0}
	}
	for pack: String in packs:
		var scene := (load(BASE + pack + "/imported.scn") as PackedScene).instantiate()
		root.add_child(scene)
		for part: String in packs[pack]:
			var source := scene.find_child(part, true, false) as Node3D
			assert(source != null, part)
			_export_prop(source, pack, part, float(packs[pack][part]))
		scene.free()
	_build_skin()
	var file := FileAccess.open(OUT + "asset_manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("RELIC_ASSETS_BUILT ", report.keys())
	quit()

func _export_prop(source: Node3D, pack: String, part: String, requested_size: float) -> void:
	var output := Node3D.new()
	output.name = part.replace(" ", "_")
	var meshes: Array[Node] = source.find_children("*", "MeshInstance3D", true, false)
	if source is MeshInstance3D:
		meshes.push_front(source)
	var bounds := AABB()
	var first := true
	for item: MeshInstance3D in meshes:
		var box: AABB = item.global_transform * item.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	assert(not first)
	var factor := requested_size / bounds.size.y if requested_size > 0.0 else -requested_size / maxf(bounds.size.x, bounds.size.z)
	var origin := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	for item: MeshInstance3D in meshes:
		var copy := MeshInstance3D.new()
		copy.name = item.name
		copy.mesh = item.mesh
		copy.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * factor), -origin * factor) * item.global_transform
		output.add_child(copy)
		copy.owner = output
	var id: String = ("container_" + part.trim_prefix("Object_")) if pack == "psx_shipping_containers_2" else part.to_snake_case().replace(" ", "_")
	var path := OUT + id + ".glb"
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_scene(output, state) == OK)
	assert(document.write_to_filesystem(state, path) == OK)
	var packed := PackedScene.new()
	assert(packed.pack(output) == OK)
	assert(ResourceSaver.save(packed, OUT + id + ".scn", ResourceSaver.FLAG_COMPRESS) == OK)
	report[id] = {"source_pack": pack, "source_group": part, "path": path, "scale_applied": factor, "size_m": [bounds.size.x * factor, bounds.size.y * factor, bounds.size.z * factor], "pivot": "bottom_center"}
	output.free()

func _bone(sk: Skeleton3D, index: int) -> Transform3D:
	return sk.global_transform * sk.get_bone_global_rest(index)
func _build_skin() -> void:
	var native := (load("res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx") as PackedScene).instantiate()
	var source := (load(BASE + "ps1low_poly_night_vision_special_forces_soldier/imported.scn") as PackedScene).instantiate()
	root.add_child(native)
	root.add_child(source)
	var target := native.find_child("Skeleton3D", true, false) as Skeleton3D
	var sk := source.find_child("Skeleton3D", true, false) as Skeleton3D
	assert(target != null and sk != null)
	var output := Node3D.new()
	output.name = "RelicNVGSkin"
	var names := ["Arms", "Backpack", "BodyLegs", "Hands", "Head", "NVG", "Pouches"]
	var source_meshes := source.find_children("*", "MeshInstance3D", true, false)
	assert(source_meshes.size() == 7)
	# Calibrate source joint spacing to the existing head-to-hip contract; do not
	# change the target skeleton, collision capsule, weapon mounts or driver scale.
	var scale_factor: float = (_bone(target, target.find_bone("mixamorig_Head")).origin.y - _bone(target, target.find_bone("mixamorig_Hips")).origin.y) / (_bone(sk, sk.find_bone("head_0")).origin.y - _bone(sk, sk.find_bone("Spinelower_11")).origin.y)
	for index in source_meshes.size():
		var mesh := source_meshes[index] as MeshInstance3D
		var result := MeshInstance3D.new()
		result.name = names[index]
		var new_mesh := ArrayMesh.new()
		var new_skin := Skin.new()
		for bind in mesh.skin.get_bind_count():
			var source_index: int = sk.find_bone(mesh.skin.get_bind_name(bind))
			if source_index < 0:
				source_index = mesh.skin.get_bind_bone(bind)
			var source_name: String = sk.get_bone_name(source_index)
			var target_name: String = "mixamorig_" + str(BONE_MAP.get(source_name, "Hips"))
			var target_index: int = target.find_bone(target_name)
			assert(target_index >= 0)
			new_skin.add_named_bind(target_name, target.get_bone_global_rest(target_index).affine_inverse())
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface).duplicate(true)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var stride: int = weights.size() / vertices.size()
			for vertex in vertices.size():
				var point := Vector3.ZERO
				for slot in stride:
					var offset: int = vertex * stride + slot
					if weights[offset] < 0.000001:
						continue
					var bind: int = joints[offset]
					var source_index: int = sk.find_bone(mesh.skin.get_bind_name(bind))
					if source_index < 0:
						source_index = mesh.skin.get_bind_bone(bind)
					point += (_bone(sk, source_index) * mesh.skin.get_bind_pose(bind) * vertices[vertex]) * weights[offset]
				var posed := Vector3.ZERO
				var normal := Vector3.ZERO
				for slot in stride:
					var offset: int = vertex * stride + slot
					if weights[offset] < 0.000001:
						continue
					var bind: int = joints[offset]
					var source_index: int = sk.find_bone(mesh.skin.get_bind_name(bind))
					if source_index < 0:
						source_index = mesh.skin.get_bind_bone(bind)
					var name: String = sk.get_bone_name(source_index)
					assert(BONE_MAP.has(name), "Unmapped weighted source bone: " + name)
					var target_index: int = target.find_bone("mixamorig_" + str(BONE_MAP[name]))
					var from: Transform3D = _bone(sk, source_index)
					var to: Transform3D = _bone(target, target_index)
					var rotation := Basis.IDENTITY
					if ENDPOINTS.has(name):
						var pair: Array = ENDPOINTS[name]
						var a: Vector3 = _bone(sk, sk.find_bone(pair[0])).origin - from.origin
						var b: Vector3 = _bone(target, target.find_bone("mixamorig_" + str(pair[1]))).origin - to.origin
						rotation = Basis(Quaternion(a.normalized(), b.normalized()))
					posed += (to.origin + rotation * (point - from.origin) * scale_factor) * weights[offset]
					normal += rotation * normals[vertex] * weights[offset]
				vertices[vertex] = target.global_transform.affine_inverse() * posed
				normals[vertex] = normal.normalized()
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TANGENT] = null
			new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			new_mesh.surface_set_material(surface, mesh.mesh.surface_get_material(surface))
		result.mesh = new_mesh
		result.skin = new_skin
		output.add_child(result)
		result.owner = output
	var packed := PackedScene.new()
	assert(packed.pack(output) == OK)
	assert(ResourceSaver.save(packed, SKIN_OUT + "character_skin.scn", ResourceSaver.FLAG_COMPRESS) == OK)
	report.character = {"source_meshes": 7, "target_native_bones": target.get_bone_count(), "rest_scale": scale_factor, "mapping": BONE_MAP, "no_weapon_meshes": true}
	output.free()
	source.free()
	native.free()
