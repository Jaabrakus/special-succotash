extends SceneTree

const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const VisualRigContract := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd"
)
const VisualRigResolver := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_resolver.gd"
)

const MODEL_PATH := "res://assets/weapons/m4a1/m4a1_potato_photoreal.glb"
const VISUAL_RIG_PATH := "res://config/weapon_visual_rigs/m4a1_potato_photoreal_v1.json"
const CANONICAL_M4_PROFILE := "res://config/weapons/m4a1.json"

const EXPECTED_BONES := [
	"root",
	"trigger",
	"magazine",
	"bullets",
	"charging_handle",
	"muzzle",
	"sights",
	"sight_type1",
	"sight_type2",
	"stock",
	"barrel",
]

const RUNTIME_SOCKET_NAMES := [
	"Socket_RightHand",
	"Socket_LeftHand",
	"Socket_Muzzle",
	"Socket_BarrelBase",
	"Socket_Buttstock",
	"Socket_Optic",
	"Socket_Ejection",
]

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_visual_rig_document()
	_check_gltf_model_and_skeleton()
	_check_runtime_mounting_parity()
	_finish()


func _check_visual_rig_document() -> void:
	var file := FileAccess.open(VISUAL_RIG_PATH, FileAccess.READ)
	_expect(file != null, "visual rig file exists at %s" % VISUAL_RIG_PATH)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_expect(parsed is Dictionary, "visual rig is valid JSON")
	if not parsed is Dictionary:
		return
	var doc := parsed as Dictionary
	var validation := VisualRigContract.validate(doc, true)
	_expect(bool(validation.get("ok", false)), "M4A1 potato photoreal visual rig passes contract validation: %s" % str(validation))
	
	var visual: Dictionary = doc.get("visual", {})
	var sockets: Dictionary = visual.get("weapon_sockets", {})
	for socket_name in VisualRigContract.REQUIRED_SOCKETS:
		_expect(sockets.has(socket_name), "visual rig contains required socket %s" % socket_name)


func _check_gltf_model_and_skeleton() -> void:
	_expect(ResourceLoader.exists(MODEL_PATH), "model glb exists: %s" % MODEL_PATH)
	var packed := load(MODEL_PATH) as PackedScene
	_expect(packed != null, "model glb loads as PackedScene")
	if packed == null:
		return
	var instance := packed.instantiate()
	_expect(instance != null, "model instantiates successfully")
	if instance == null:
		return

	# Skeleton validation
	var skeleton := _find_skeleton(instance)
	_expect(skeleton != null, "model contains Skeleton3D")
	if skeleton != null:
		for bone_name in EXPECTED_BONES:
			var idx := skeleton.find_bone(bone_name)
			_expect(idx >= 0, "skeleton contains bone: %s (idx: %d)" % [bone_name, idx])
			
	# Mesh validation
	var mesh_inst := _find_mesh_instance(instance)
	_expect(mesh_inst != null, "model contains MeshInstance3D")
	if mesh_inst != null and mesh_inst.mesh != null:
		var mesh := mesh_inst.mesh
		var tri_count := 0
		for surf_idx in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surf_idx)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if not indices.is_empty():
				tri_count += indices.size() / 3
			else:
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				tri_count += verts.size() / 3
		print("M4A1_POTATO_PHOTOREAL_METRIC triangle_count=%d" % tri_count)
		_expect(tri_count > 0, "model has geometry")
		_expect(tri_count <= 7000, "model meets strict potato triangle budget (<= 7,000 tris, actual: %d)" % tri_count)
		_expect(tri_count >= 2500, "model has photoreal silhouette density (>= 2,500 tris, actual: %d)" % tri_count)

	instance.free()


func _check_runtime_mounting_parity() -> void:
	# Test resolver with canonical m4a1 profile pointing to this new rig
	var canonical := WeaponContract.load_config(CANONICAL_M4_PROFILE)
	_expect(not canonical.is_empty(), "canonical M4A1 profile loads")
	var candidate := canonical.duplicate(true)
	candidate["visual_rig_id"] = "m4a1_potato_photoreal_v1"
	candidate["model_fbx"] = MODEL_PATH

	VisualRigResolver.clear_cache()
	var resolved := VisualRigResolver.resolve_for_presentation(candidate)
	_expect(not resolved.is_empty(), "resolver resolves candidate profile")
	_expect(String(resolved.get("model_fbx", "")) == MODEL_PATH, "resolved profile uses potato photoreal glb")

	var sockets: Dictionary = resolved.get("weapon_sockets", {})
	_expect(sockets.size() == VisualRigContract.REQUIRED_SOCKETS.size(), "resolved profile has all 7 canonical sockets")
	var muzzle := WeaponContract.vector3_from_map(sockets.get("muzzle_socket", {}), Vector3.ZERO)
	var barrel := WeaponContract.vector3_from_map(sockets.get("barrel_base_socket", {}), Vector3.ZERO)
	_expect(muzzle.distance_to(barrel) > 0.15, "barrel length is realistic (> 0.15m)")


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("M4A1_PHOTOREAL_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("M4A1_PHOTOREAL_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("M4A1_PHOTOREAL_POTATO_REGRESSION PASS")
		quit(0)
	else:
		print("M4A1_PHOTOREAL_POTATO_REGRESSION FAIL: ", failures)
		quit(1)
