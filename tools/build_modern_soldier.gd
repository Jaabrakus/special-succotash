extends SceneTree

## Offline asset conversion. Never runs in gameplay.
const SOURCE := "res://art_source/modern_soldier/modern_soldier_native.glb"
const BASE := "res://assets/characters/ps1_dual_source_rig/ps1_dual_source_rig.scn"
const OUTPUT := "res://assets/characters/modern_soldier/modern_soldier.scn"
const Adapter := preload("res://scripts/player/operator_native_rig_adapter.gd")
var primary: Dictionary = {}
var source_rig: Skeleton3D
var target_rig: Skeleton3D
var transforms: Dictionary = {}
var target_indices: Dictionary = {}
var vertex_count := 0
var triangle_count := 0
var texture_cache: Dictionary = {}
var iso_report: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_file(SOURCE, state) == OK)
	var source := document.generate_scene(state) as Node3D
	root.add_child(source)
	source_rig = source.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var candidate := (load(BASE) as PackedScene).instantiate() as Node3D
	root.add_child(candidate)
	target_rig = candidate.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for mesh: Node in candidate.find_children("*", "MeshInstance3D", true, false):
		mesh.free()
	source_rig.reset_bone_poses()
	target_rig.reset_bone_poses()
	var args := OS.get_cmdline_user_args()
	if args.has("--iso-skeleton"):
		iso_report = preload("res://tools/modern_iso_proportion_builder.gd").apply(target_rig, args[args.find("--iso-skeleton") + 1])
	primary = Adapter.AGLS_TO_CANONICAL.duplicate()
	# The downloaded character has five spine joints; map the upper chest,
	# rather than mistaking its middle spine for the clavicle parent.
	primary.erase("spine_02")
	primary["spine_03"] = "mixamorig_Spine1"
	primary["spine_05"] = "mixamorig_Spine2"
	for side in ["l", "r"]:
		var label := "Left" if side == "l" else "Right"
		for finger in Adapter.AGLS_FINGER_TO_CANONICAL:
			for segment in range(1, 4):
				primary["%s_%02d_%s" % [finger, segment, side]] = "mixamorig_%sHand%s%d" % [label, Adapter.AGLS_FINGER_TO_CANONICAL[finger], segment]
	var frame := _frame(target_rig, false) * _frame(source_rig, true).inverse()
	var ratio := (_target_position("mixamorig_Head") - _target_position("mixamorig_Hips")).length() / (_source_position("head") - _source_position("pelvis")).length()
	if not iso_report.is_empty():
		ratio = (_target_position("mixamorig_Head").y - (_target_position("mixamorig_LeftFoot").y + _target_position("mixamorig_RightFoot").y) * .5) / (_source_position("head").y - (_source_position("foot_l").y + _source_position("foot_r").y) * .5)
	for native_name: String in primary:
		var canonical := String(primary[native_name])
		var source_index := source_rig.find_bone(native_name)
		var target_index := target_rig.find_bone(canonical)
		assert(source_index >= 0 and target_index >= 0, "Required anatomical mapping missing: " + native_name)
		var rotation := frame
		if native_name.begins_with("hand_") or "_0" in native_name and native_name.get_slice("_", 0) in Adapter.AGLS_FINGER_TO_CANONICAL:
			var side := native_name.right(1)
			rotation = _hand_frame(side, false) * _hand_frame(side, true).inverse()
		var child := _endpoint(native_name)
		if not child.is_empty():
			var source_direction := rotation * (_source_position(child) - _source_position(native_name)).normalized()
			var target_direction := (_target_position(primary[child]) - _target_position(canonical)).normalized()
			rotation = Basis(Quaternion(source_direction, target_direction)) * rotation
		var basis := rotation.scaled(Vector3.ONE * ratio)
		if not iso_report.is_empty() and not child.is_empty() and _target_position(primary[child]).distance_to(_target_position(canonical)) > .001:
			# Fit segment length explicitly; keep transverse modern mesh detail.
			var axis := (_source_position(child) - _source_position(native_name)).normalized()
			var longitudinal := _target_position(primary[child]).distance_to(_target_position(canonical)) / _source_position(child).distance_to(_source_position(native_name))
			var amount := longitudinal / ratio - 1.0
			var stretch := Basis(Vector3.RIGHT + axis * axis.x * amount, Vector3.UP + axis * axis.y * amount, Vector3.BACK + axis * axis.z * amount)
			basis = rotation * stretch.scaled(Vector3.ONE * ratio)
		transforms[native_name] = Transform3D(basis, _target_position(canonical) - basis * _source_position(native_name))
		target_indices[native_name] = target_index
	if not iso_report.is_empty():
		_fit_iso_anatomy(frame, ratio)
	var inverse_target := target_rig.global_transform.affine_inverse()
	# Runtime's existing outer model scale remains 62. Convert human-space
	# vertices back to that exact native skeleton space, not a new global scale.
	inverse_target = inverse_target * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE / 62.0), Vector3.ZERO)
	for mesh: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		# The supplied eyelash card has a solid-black base map and no opacity
		# mask in the archive. Preserve it in the source workbench, but do not
		# cover the eyes with an opaque black card in the runtime derivative.
		if mesh.name == "Eyelashes":
			continue
		_convert_mesh(mesh, candidate, inverse_target)
	candidate.set_meta("socom_modern_character", true)
	var packed := PackedScene.new()
	assert(packed.pack(candidate) == OK)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var output := OUTPUT if iso_report.is_empty() else "res://assets/characters/modern_soldier/modern_soldier_iso.scn"
	assert(ResourceSaver.save(packed, output, ResourceSaver.FLAG_COMPRESS) == OK)
	var report := {"source": SOURCE, "output": OUTPUT, "source_bones": source_rig.get_bone_count(), "runtime_bones": target_rig.get_bone_count(), "vertices": vertex_count, "triangles": triangle_count, "scale_ratio": ratio, "mapping": primary, "note": "Canonical rest, indices and animation contracts preserved; native source retained in Blender workbench."}
	report.output = output
	report.iso_proportions = iso_report
	if not iso_report.is_empty():
		report.note = "ISO control positions with coherent modern anatomical skin fit; canonical bone names, parents and rest orientations retained, rest translations adapted. Not an original ISO mesh."
	var file := FileAccess.open("res://art_source/modern_soldier/rig_conversion_report.json" if iso_report.is_empty() else "res://art_source/modern_soldier/iso_proportion_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("MODERN_BUILD ", JSON.stringify(report))
	source.free()
	candidate.free()
	quit()

func _fit_iso_anatomy(frame: Basis, ratio: float) -> void:
	# The ISO hips/spinelo/scap nodes are control pivots, not the downloaded
	# body's pelvis/chest/clavicle skin landmarks. Keep those rig pivots exact,
	# but fit the continuous trunk between anatomical hip and neck landmarks.
	var source_hip := (_source_position("thigh_l") + _source_position("thigh_r")) * .5
	var target_hip := (_target_position("mixamorig_LeftUpLeg") + _target_position("mixamorig_RightUpLeg")) * .5
	var source_neck := _source_position("neck_01")
	var target_neck := _target_position("mixamorig_Neck")
	var shoulder_width := _target_position("mixamorig_LeftArm").distance_to(_target_position("mixamorig_RightArm")) / _source_position("upperarm_l").distance_to(_source_position("upperarm_r"))
	var x := frame.x * shoulder_width
	var z := frame.z * ratio
	var span := source_neck - source_hip
	var y := (target_neck - target_hip - x * span.x - z * span.z) / span.y
	var body_basis := Basis(x, y, z)
	assert(body_basis.determinant() > 0.0, "Anatomy fit must not reflect/invert the body")
	var body := Transform3D(body_basis, target_hip - body_basis * source_hip)
	for name in ["pelvis", "spine_01", "spine_03", "spine_05"]:
		transforms[name] = body
	for side in ["l", "r"]:
		var name: String = "clavicle_" + side
		var arm: String = "upperarm_" + side
		var start := body * _source_position(name)
		var end := _target_position(primary[arm])
		transforms[name] = _segment_fit(_source_position(name), _source_position(arm), start, end, frame, ratio)
	iso_report["skin_fit"] = {"revision":2, "method":"continuous_anatomical_trunk_independent_of_control_pivots", "torso_scale_y":y.length(), "shoulder_scale":shoulder_width, "neck_anchor_error_m":(body * source_neck).distance_to(target_neck)}
	target_rig.set_meta("iso_proportions", iso_report)

func _segment_fit(a: Vector3, b: Vector3, target_a: Vector3, target_b: Vector3, frame: Basis, transverse_scale: float) -> Transform3D:
	var axis := (b - a).normalized()
	var rotation := Basis(Quaternion(frame * axis, (target_b - target_a).normalized())) * frame
	var amount := target_a.distance_to(target_b) / a.distance_to(b) / transverse_scale - 1.0
	var stretch := Basis(Vector3.RIGHT + axis * axis.x * amount, Vector3.UP + axis * axis.y * amount, Vector3.BACK + axis * axis.z * amount)
	var basis := rotation * stretch.scaled(Vector3.ONE * transverse_scale)
	return Transform3D(basis, target_a - basis * a)

func _source_position(name: String) -> Vector3:
	return (source_rig.global_transform * source_rig.get_bone_global_rest(source_rig.find_bone(name))).origin

func _target_position(name: String) -> Vector3:
	return (target_rig.global_transform * target_rig.get_bone_global_rest(target_rig.find_bone(name))).origin * 62.0

func _frame(rig: Skeleton3D, native: bool) -> Basis:
	var names := ["pelvis", "head", "hand_l", "hand_r"] if native else ["mixamorig_Hips", "mixamorig_Head", "mixamorig_LeftHand", "mixamorig_RightHand"]
	var positions: Array[Vector3] = []
	for name: String in names:
		positions.append((rig.global_transform * rig.get_bone_global_rest(rig.find_bone(name))).origin)
	var x := (positions[2] - positions[3]).normalized()
	var y := (positions[1] - positions[0]).normalized()
	var z := x.cross(y).normalized()
	return Basis(y.cross(z).normalized(), y, z).orthonormalized()

func _endpoint(name: String) -> String:
	var pairs := {"pelvis":"spine_01", "spine_01":"spine_03", "spine_03":"spine_05", "spine_05":"neck_01", "neck_01":"head"}
	if pairs.has(name):
		return pairs[name]
	for side in ["l", "r"]:
		for chain in [["clavicle_", "upperarm_", "lowerarm_", "hand_"], ["thigh_", "calf_", "foot_", "ball_"]]:
			for i in range(chain.size() - 1):
				if name == chain[i] + side:
					return chain[i + 1] + side
		if name == "hand_" + side:
			return "middle_01_" + side
		for finger in Adapter.AGLS_FINGER_TO_CANONICAL:
			for i in range(1, 3):
				if name == "%s_%02d_%s" % [finger, i, side]:
					return "%s_%02d_%s" % [finger, i + 1, side]
	return ""

func _hand_frame(side: String, native: bool) -> Basis:
	var label := "Left" if side == "l" else "Right"
	var wrist := _source_position("hand_" + side) if native else _target_position("mixamorig_" + label + "Hand")
	var middle := _source_position("middle_01_" + side) if native else _target_position("mixamorig_" + label + "HandMiddle1")
	var index := _source_position("index_01_" + side) if native else _target_position("mixamorig_" + label + "HandIndex1")
	var pinky := _source_position("pinky_01_" + side) if native else _target_position("mixamorig_" + label + "HandPinky1")
	var y := (middle - wrist).normalized()
	var across := (index - pinky).normalized()
	var z := across.cross(y).normalized()
	return Basis(y.cross(z).normalized(), y, z).orthonormalized()

func _mapped_ancestor(index: int) -> String:
	while index >= 0:
		var name := String(source_rig.get_bone_name(index))
		if primary.has(name):
			return name
		index = source_rig.get_bone_parent(index)
	return "pelvis"

func _convert_mesh(source: MeshInstance3D, owner_root: Node3D, to_local: Transform3D) -> void:
	assert(source.skin != null, "Unskinned character section: " + source.name)
	var new_mesh := ArrayMesh.new()
	var source_binds: Array[Transform3D] = []
	var mapped: Array[String] = []
	for bind in source.skin.get_bind_count():
		var index := source_rig.find_bone(source.skin.get_bind_name(bind))
		if index < 0:
			index = source.skin.get_bind_bone(bind)
		assert(index >= 0)
		source_binds.append(source_rig.global_transform * source_rig.get_bone_global_rest(index) * source.skin.get_bind_pose(bind))
		mapped.append(_mapped_ancestor(index))
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var stride := weights.size() / vertices.size()
		for v in vertices.size():
			var point := Vector3.ZERO
			var normal := Vector3.ZERO
			var tangent := Vector3.ZERO
			for slot in stride:
				var offset := v * stride + slot
				var bind := bones[offset]
				var key := mapped[bind]
				var transform: Transform3D = to_local * transforms[key] * source_binds[bind]
				point += (transform * vertices[v]) * weights[offset]
				normal += transform.basis.inverse().transposed() * normals[v] * weights[offset]
				if not tangents.is_empty():
					tangent += transform.basis * Vector3(tangents[v*4], tangents[v*4+1], tangents[v*4+2]) * weights[offset]
				bones[offset] = target_indices[key]
			vertices[v] = point
			normals[v] = normal.normalized()
			if not tangents.is_empty():
				tangent = tangent.normalized()
				tangents[v*4] = tangent.x
				tangents[v*4+1] = tangent.y
				tangents[v*4+2] = tangent.z
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = tangents
		arrays[Mesh.ARRAY_BONES] = bones
		new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := source.mesh.surface_get_material(surface).duplicate() as BaseMaterial3D
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_compress_material(material)
		new_mesh.surface_set_material(surface, material)
		vertex_count += vertices.size()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		triangle_count += indices.size() / 3
	var instance := MeshInstance3D.new()
	instance.name = source.name
	var importer := ImporterMesh.from_mesh(new_mesh)
	importer.generate_lods(25.0, 60.0, [])
	instance.mesh = importer.get_mesh()
	instance.skin = Skin.new()
	for bone in target_rig.get_bone_count():
		instance.skin.add_named_bind(target_rig.get_bone_name(bone), target_rig.get_bone_global_rest(bone).affine_inverse())
	instance.skeleton = NodePath("..")
	instance.set_meta("socom_modern_character", true)
	instance.set_meta("socom_team_cloth", source.get_meta("socom_team_cloth", false))
	instance.extra_cull_margin = 0.06
	target_rig.add_child(instance)
	instance.owner = owner_root

func _compress_material(material: BaseMaterial3D) -> void:
	for property in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "ao_texture"]:
		var original := material.get(property) as Texture2D
		if original == null:
			continue
		var id := original.get_instance_id()
		if not texture_cache.has(id):
			var image := original.get_image()
			if image.is_compressed():
				image.decompress()
			var limit := 2048 if "Head" in material.resource_name else 1024
			if maxi(image.get_width(), image.get_height()) > limit:
				image.resize(limit, limit, Image.INTERPOLATE_LANCZOS)
			image.generate_mipmaps(property == "normal_texture")
			var compressed := PortableCompressedTexture2D.new()
			compressed.keep_compressed_buffer = true
			compressed.set_basisu_compressor_params(0, 1.0)
			compressed.create_from_image(image, PortableCompressedTexture2D.COMPRESSION_MODE_BASIS_UNIVERSAL, property == "normal_texture")
			texture_cache[id] = compressed
		material.set(property, texture_cache[id])
	print("MODERN_MATERIAL ", material.resource_name)
