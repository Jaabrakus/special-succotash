extends RefCounted

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const Geometry := preload("res://scripts/maps/socom_map_geometry.gd")
const Materials := preload("res://scripts/maps/socom_map_surface_materials.gd")

static func _build_opening_wall(object: Dictionary, window_opening: bool) -> Node3D:
	var root := Node3D.new()
	root.name = String(object.get("name", "Window Wall" if window_opening else "Doorway Wall")).validate_node_name()
	root.position = MapDocument.data_to_vector(object.get("position", {}))
	root.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	Geometry._set_object_meta(root, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(4.0, 3.0, 0.3))
	var properties: Dictionary = object.get("properties", {})
	var opening_width := clampf(float(properties.get("opening_width", 1.25)), 0.6, maxf(size.x - 0.4, 0.6))
	var opening_height := clampf(float(properties.get("opening_height", 1.25 if window_opening else 2.2)), 0.5, maxf(size.y - 0.2, 0.5))
	var side_width := maxf((size.x - opening_width) * 0.5, 0.1)
	Geometry._add_compound_box(root, "LeftPier", Vector3(side_width, size.y, size.z), Vector3(-(opening_width + side_width) * 0.5, 0.0, 0.0), object)
	Geometry._add_compound_box(root, "RightPier", Vector3(side_width, size.y, size.z), Vector3((opening_width + side_width) * 0.5, 0.0, 0.0), object)
	if window_opening:
		var sill_height := maxf((size.y - opening_height) * 0.48, 0.55)
		var header_height := maxf(size.y - opening_height - sill_height, 0.1)
		Geometry._add_compound_box(root, "WindowSill", Vector3(opening_width, sill_height, size.z), Vector3(0.0, -size.y * 0.5 + sill_height * 0.5, 0.0), object)
		Geometry._add_compound_box(root, "WindowHeader", Vector3(opening_width, header_height, size.z), Vector3(0.0, size.y * 0.5 - header_height * 0.5, 0.0), object)
	else:
		var header_height := maxf(size.y - opening_height, 0.1)
		Geometry._add_compound_box(root, "DoorHeader", Vector3(opening_width, header_height, size.z), Vector3(0.0, size.y * 0.5 - header_height * 0.5, 0.0), object)
	return root


static func _build_favela_building(object: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = String(object.get("name", "Favela Building Assembly")).validate_node_name()
	root.position = MapDocument.data_to_vector(object.get("position", {}))
	root.rotation_degrees = MapDocument.data_to_vector(object.get("rotation_degrees", {}))
	Geometry._set_object_meta(root, object)
	var size := MapDocument.data_to_vector(object.get("size", {}), Vector3(8.0, 4.4, 7.0))
	var properties: Dictionary = object.get("properties", {})
	var entries: Array = properties.get("entries", ["south"])
	var windows: Array = properties.get("windows", ["north"])
	var door_width := clampf(float(properties.get("door_width", 1.55)), 0.8, minf(size.x, size.z) - 0.8)
	var door_height := clampf(float(properties.get("door_height", 2.35)), 1.8, size.y - 0.2)
	var window_width := clampf(float(properties.get("window_width", 1.65)), 0.8, minf(size.x, size.z) - 0.8)
	var window_height := clampf(float(properties.get("window_height", 1.25)), 0.7, size.y - 1.0)
	var wall_thickness := 0.35
	var base_color := MapDocument.data_to_color(object.get("color", {}), Color("d1b58c"))
	var trim_color := MapDocument.data_to_color(properties.get("trim_color", {}), Color("e3d8bd"))
	var roof_color := MapDocument.data_to_color(properties.get("roof_color", {}), Color("62564f"))
	var damage_side := String(properties.get("damage_side", "south"))
	var downspout_side := String(properties.get("downspout_side", "east"))
	var masonry_texture_path := String(properties.get("masonry_texture_path", ""))
	var wood_texture_path := String(properties.get("wood_texture_path", ""))
	var wood_wall_sides: Array = properties.get("wood_wall_sides", [])
	var building_id := String(object.get("id", "favela_building"))

	var slab_object := _building_part_object(object, "slab", roof_color, "concrete")
	Geometry._add_compound_box(root, "FloorSlab", Vector3(size.x, 0.35, size.z), Vector3(0.0, 0.175, 0.0), slab_object)
	Geometry._add_compound_box(root, "RoofSlab", Vector3(size.x, 0.35, size.z), Vector3(0.0, size.y + 0.175, 0.0), slab_object)

	for side_index in 4:
		var side: String = ["north", "south", "east", "west"][side_index]
		var wall_position := Vector3(0.0, size.y * 0.5, 0.0)
		var wall_size := Vector3(size.x, size.y, wall_thickness)
		var wall_yaw := 0.0
		var exterior_sign := 1.0
		if side == "north":
			wall_position.z = -size.z * 0.5
			exterior_sign = -1.0
		elif side == "south":
			wall_position.z = size.z * 0.5
		elif side == "east":
			wall_position.x = size.x * 0.5
			wall_size.x = size.z
			wall_yaw = 90.0
		elif side == "west":
			wall_position.x = -size.x * 0.5
			wall_size.x = size.z
			wall_yaw = 90.0
			exterior_sign = -1.0
		var wall_color := base_color.lightened(0.045 * float((side_index + building_id.length()) % 3))
		if side_index == 2:
			wall_color = wall_color.darkened(0.06)
		var wall_object := _building_part_object(object, "%s_wall" % side, wall_color, "default")
		var wall_texture_path := wood_texture_path if side in wood_wall_sides else masonry_texture_path
		_apply_authored_surface_texture(
			wall_object,
			wall_texture_path,
			0.46 if side in wood_wall_sides else 0.34,
			0.08 if side in wood_wall_sides else 0.04,
			Color("b4aa99") if side in wood_wall_sides else Color("d4cab8")
		)
		wall_object["position"] = MapDocument.vector_to_data(wall_position)
		wall_object["rotation_degrees"] = MapDocument.vector_to_data(Vector3(0.0, wall_yaw, 0.0))
		wall_object["size"] = MapDocument.vector_to_data(wall_size)
		var wall_properties: Dictionary = wall_object.get("properties", {})
		wall_properties["building_side"] = side
		wall_object["properties"] = wall_properties
		var wall_node: Node3D
		if side in entries:
			wall_properties["opening_width"] = door_width
			wall_properties["opening_height"] = door_height
			wall_object["properties"] = wall_properties
			wall_node = _build_opening_wall(wall_object, false)
			_add_door_architecture(wall_node, wall_size, door_width, door_height, exterior_sign, trim_color, roof_color, wall_object)
		elif side in windows:
			wall_properties["opening_width"] = window_width
			wall_properties["opening_height"] = window_height
			wall_object["properties"] = wall_properties
			wall_node = _build_opening_wall(wall_object, true)
			_add_window_architecture(wall_node, wall_size, window_width, window_height, exterior_sign, trim_color, roof_color, wall_object)
		else:
			wall_node = Node3D.new()
			wall_node.name = "%sWall" % side.capitalize()
			wall_node.position = wall_position
			wall_node.rotation_degrees.y = wall_yaw
			Geometry._set_object_meta(wall_node, wall_object)
			Geometry._add_compound_box(wall_node, "WallMass", wall_size, Vector3.ZERO, wall_object)
		root.add_child(wall_node)
		if side == damage_side:
			_add_exposed_brick_relief(wall_node, wall_size, exterior_sign, wall_object)
		else:
			_add_irregular_plaster_patch(wall_node, wall_size, exterior_sign, wall_color, side_index, wall_object)
		_add_foundation_band(wall_node, wall_size, exterior_sign, roof_color, wall_object)
		if side == downspout_side:
			_add_downspout(wall_node, wall_size, exterior_sign, wall_object)
			_add_electrical_service(wall_node, wall_size, exterior_sign, wall_object)

	_add_corner_pilasters(root, size, trim_color.darkened(0.14), object)
	_add_roof_cornice(root, size, roof_color, object)

	var parapet_height := clampf(float(properties.get("parapet_height", 0.35)), 0.0, 0.8)
	if parapet_height > 0.05:
		var parapet_object := _building_part_object(object, "parapet", base_color.darkened(0.16), "default")
		var parapet_y := size.y + 0.35 + parapet_height * 0.5
		Geometry._add_compound_box(root, "NorthParapet", Vector3(size.x, parapet_height, 0.22), Vector3(0.0, parapet_y, -size.z * 0.5 + 0.11), parapet_object)
		Geometry._add_compound_box(root, "SouthParapet", Vector3(size.x, parapet_height, 0.22), Vector3(0.0, parapet_y, size.z * 0.5 - 0.11), parapet_object)
		Geometry._add_compound_box(root, "EastParapet", Vector3(0.22, parapet_height, size.z), Vector3(size.x * 0.5 - 0.11, parapet_y, 0.0), parapet_object)
		Geometry._add_compound_box(root, "WestParapet", Vector3(0.22, parapet_height, size.z), Vector3(-size.x * 0.5 + 0.11, parapet_y, 0.0), parapet_object)
	return root


static func _building_part_object(source: Dictionary, suffix: String, color: Color, surface_kind: String) -> Dictionary:
	var result := source.duplicate(true)
	result["id"] = "%s_%s" % [String(source.get("id", "building")), suffix]
	result["color"] = MapDocument.color_to_data(color)
	var properties: Dictionary = (source.get("properties", {}) as Dictionary).duplicate(true)
	properties["painterly_material"] = true
	properties["painterly_material_v2"] = true
	properties["surface_kind"] = surface_kind
	properties["roughness"] = 1.0
	properties["normal_strength"] = 0.035
	properties.erase("texture_path")
	result["properties"] = properties
	return result


static func _apply_authored_surface_texture(
	object: Dictionary, texture_path: String, uv_scale: float,
	tint_weight: float, texture_multiplier: Color
) -> void:
	if texture_path.is_empty():
		return
	var properties: Dictionary = (object.get("properties", {}) as Dictionary).duplicate(true)
	properties["texture_path"] = texture_path
	properties["surface_kind"] = "default"
	properties["uv_scale"] = uv_scale
	properties["texture_tint_weight"] = tint_weight
	properties["texture_multiplier"] = MapDocument.color_to_data(texture_multiplier)
	object["properties"] = properties


static func _add_door_architecture(
	wall: Node3D, wall_size: Vector3, opening_width: float, opening_height: float,
	exterior_sign: float, trim_color: Color, awning_color: Color, source: Dictionary
) -> void:
	var trim_object := _building_part_object(source, "door_trim", trim_color, "default")
	var face_z := exterior_sign * (wall_size.z * 0.5 + 0.055)
	var center_y := -wall_size.y * 0.5 + opening_height * 0.5
	Geometry._add_visual_box(wall, "LeftDoorJamb", Vector3(0.13, opening_height + 0.08, 0.10), Vector3(-opening_width * 0.5 - 0.065, center_y, face_z), Vector3.ZERO, trim_object)
	Geometry._add_visual_box(wall, "RightDoorJamb", Vector3(0.13, opening_height + 0.08, 0.10), Vector3(opening_width * 0.5 + 0.065, center_y, face_z), Vector3.ZERO, trim_object)
	Geometry._add_visual_box(wall, "DoorLintel", Vector3(opening_width + 0.26, 0.15, 0.10), Vector3(0.0, -wall_size.y * 0.5 + opening_height + 0.075, face_z), Vector3.ZERO, trim_object)
	var door_hinge := Node3D.new()
	door_hinge.name = "OpenDoorHinge"
	door_hinge.position = Vector3(-opening_width * 0.5 + 0.05, center_y, 0.0)
	door_hinge.rotation_degrees.y = 58.0 * exterior_sign
	wall.add_child(door_hinge)
	var door_object := _building_part_object(source, "door_leaf", awning_color.darkened(0.22), "default")
	var source_properties: Dictionary = source.get("properties", {})
	_apply_authored_surface_texture(
		door_object, String(source_properties.get("wood_texture_path", "")), 0.48, 0.06, Color("a89b87")
	)
	Geometry._add_visual_box(
		door_hinge, "OpenDoorLeaf",
		Vector3(opening_width * 0.78, opening_height * 0.94, 0.085),
		Vector3(opening_width * 0.39, 0.0, 0.0), Vector3.ZERO, door_object
	)
	_add_corrugated_awning(wall, wall_size, opening_width + 0.65, opening_height, exterior_sign, awning_color, source)
	var properties: Dictionary = source.get("properties", {})
	var sign_text := String(properties.get("sign_text", ""))
	var building_side := String(properties.get("building_side", ""))
	if not sign_text.is_empty() and building_side == String(properties.get("sign_side", "south")):
		_add_facade_sign(wall, wall_size, opening_height, exterior_sign, sign_text, source)


static func _add_facade_sign(
	wall: Node3D, wall_size: Vector3, opening_height: float,
	exterior_sign: float, sign_text: String, source: Dictionary
) -> void:
	var board_width := clampf(0.62 + float(sign_text.length()) * 0.23, 1.7, minf(wall_size.x * 0.62, 3.6))
	var board_y := -wall_size.y * 0.5 + opening_height + 0.82
	var board_z := exterior_sign * (wall_size.z * 0.5 + 0.085)
	var board_object := _building_part_object(source, "facade_sign", Color("374847"), "default")
	var properties: Dictionary = source.get("properties", {})
	_apply_authored_surface_texture(
		board_object, String(properties.get("wood_texture_path", "")), 0.55, 0.20, Color("827869")
	)
	Geometry._add_visual_box(
		wall, "FacadeSignBoard", Vector3(board_width, 0.52, 0.13),
		Vector3(0.0, board_y, board_z), Vector3.ZERO, board_object
	)
	var label := Label3D.new()
	label.name = "FacadeSignText"
	label.text = sign_text
	label.font_size = 64
	label.pixel_size = 0.0062
	label.outline_size = 8
	label.modulate = Color("f1dfae")
	label.outline_modulate = Color("202b2b")
	label.position = Vector3(0.0, board_y, board_z + exterior_sign * 0.075)
	label.rotation_degrees.y = 180.0 if exterior_sign < 0.0 else 0.0
	wall.add_child(label)


static func _add_window_architecture(
	wall: Node3D, wall_size: Vector3, opening_width: float, opening_height: float,
	exterior_sign: float, trim_color: Color, shutter_color: Color, source: Dictionary
) -> void:
	var sill_height := maxf((wall_size.y - opening_height) * 0.48, 0.55)
	var center_y := -wall_size.y * 0.5 + sill_height + opening_height * 0.5
	var face_z := exterior_sign * (wall_size.z * 0.5 + 0.055)
	var trim_object := _building_part_object(source, "window_trim", trim_color, "default")
	Geometry._add_visual_box(wall, "LeftWindowJamb", Vector3(0.11, opening_height + 0.18, 0.09), Vector3(-opening_width * 0.5 - 0.055, center_y, face_z), Vector3.ZERO, trim_object)
	Geometry._add_visual_box(wall, "RightWindowJamb", Vector3(0.11, opening_height + 0.18, 0.09), Vector3(opening_width * 0.5 + 0.055, center_y, face_z), Vector3.ZERO, trim_object)
	Geometry._add_visual_box(wall, "WindowHeaderTrim", Vector3(opening_width + 0.22, 0.11, 0.09), Vector3(0.0, center_y + opening_height * 0.5 + 0.055, face_z), Vector3.ZERO, trim_object)
	Geometry._add_visual_box(wall, "WindowSillTrim", Vector3(opening_width + 0.34, 0.13, 0.18), Vector3(0.0, center_y - opening_height * 0.5 - 0.05, face_z + exterior_sign * 0.04), Vector3.ZERO, trim_object)
	var shutter_object := _building_part_object(source, "shutters", shutter_color.darkened(0.18), "default")
	var source_properties: Dictionary = source.get("properties", {})
	_apply_authored_surface_texture(
		shutter_object, String(source_properties.get("wood_texture_path", "")), 0.52, 0.08, Color("a99d8a")
	)
	var shutter_width := minf(opening_width * 0.30, 0.52)
	Geometry._add_visual_box(wall, "LeftShutter", Vector3(shutter_width, opening_height + 0.04, 0.08), Vector3(-opening_width * 0.5 - shutter_width * 0.58, center_y, face_z + exterior_sign * 0.03), Vector3(0.0, -10.0 * exterior_sign, 0.0), shutter_object)
	Geometry._add_visual_box(wall, "RightShutter", Vector3(shutter_width, opening_height + 0.04, 0.08), Vector3(opening_width * 0.5 + shutter_width * 0.58, center_y, face_z + exterior_sign * 0.03), Vector3(0.0, 10.0 * exterior_sign, 0.0), shutter_object)
	_add_window_sash_and_glass(wall, wall_size, opening_width, opening_height, center_y, exterior_sign, source)
	var grille_object := _building_part_object(source, "window_grille", Color("384342"), "default")
	for index in 3:
		var grille_x := (float(index) - 1.0) * opening_width * 0.27
		Geometry._add_visual_box(wall, "WindowGrilleVertical%d" % index, Vector3(0.035, opening_height * 0.88, 0.045), Vector3(grille_x, center_y, face_z + exterior_sign * 0.06), Vector3.ZERO, grille_object)
	for index in 2:
		var grille_y := center_y + (float(index) - 0.5) * opening_height * 0.38
		Geometry._add_visual_box(wall, "WindowGrilleHorizontal%d" % index, Vector3(opening_width * 0.92, 0.035, 0.045), Vector3(0.0, grille_y, face_z + exterior_sign * 0.06), Vector3.ZERO, grille_object)


static func _add_window_sash_and_glass(
	wall: Node3D, wall_size: Vector3, opening_width: float, opening_height: float,
	center_y: float, exterior_sign: float, source: Dictionary
) -> void:
	var sash_width := opening_width * 0.82
	var sash_height := opening_height * 0.80
	var glass_z := -exterior_sign * wall_size.z * 0.12
	var glass := MeshInstance3D.new()
	glass.name = "WindowGlass"
	var glass_mesh := BoxMesh.new()
	glass_mesh.size = Vector3(sash_width * 0.94, sash_height * 0.94, 0.018)
	glass.mesh = glass_mesh
	glass.position = Vector3(0.0, center_y, glass_z)
	var glass_material := StandardMaterial3D.new()
	glass_material.albedo_color = Color(0.25, 0.48, 0.53, 0.42)
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_material.roughness = 0.22
	glass_material.metallic = 0.08
	glass_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.material_override = glass_material
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.add_child(glass)

	var source_properties: Dictionary = source.get("properties", {})
	var sash_object := _building_part_object(source, "window_sash", Color("625244"), "default")
	_apply_authored_surface_texture(
		sash_object, String(source_properties.get("wood_texture_path", "")), 0.58, 0.05, Color("9f927f")
	)
	var sash_z := glass_z + exterior_sign * 0.025
	var rail := 0.065
	Geometry._add_visual_box(wall, "WindowSashLeft", Vector3(rail, sash_height, 0.055), Vector3(-sash_width * 0.5, center_y, sash_z), Vector3.ZERO, sash_object)
	Geometry._add_visual_box(wall, "WindowSashRight", Vector3(rail, sash_height, 0.055), Vector3(sash_width * 0.5, center_y, sash_z), Vector3.ZERO, sash_object)
	Geometry._add_visual_box(wall, "WindowSashTop", Vector3(sash_width, rail, 0.055), Vector3(0.0, center_y + sash_height * 0.5, sash_z), Vector3.ZERO, sash_object)
	Geometry._add_visual_box(wall, "WindowSashBottom", Vector3(sash_width, rail, 0.055), Vector3(0.0, center_y - sash_height * 0.5, sash_z), Vector3.ZERO, sash_object)
	Geometry._add_visual_box(wall, "WindowMullionVertical", Vector3(rail * 0.72, sash_height, 0.060), Vector3(0.0, center_y, sash_z + exterior_sign * 0.01), Vector3.ZERO, sash_object)
	Geometry._add_visual_box(wall, "WindowMullionHorizontal", Vector3(sash_width, rail * 0.72, 0.060), Vector3(0.0, center_y, sash_z + exterior_sign * 0.01), Vector3.ZERO, sash_object)


static func _add_corrugated_awning(
	wall: Node3D, wall_size: Vector3, width: float, opening_height: float,
	exterior_sign: float, color: Color, source: Dictionary
) -> void:
	var awning_root := Node3D.new()
	awning_root.name = "CorrugatedDoorAwning"
	awning_root.position = Vector3(
		0.0,
		-wall_size.y * 0.5 + opening_height + 0.34,
		exterior_sign * (wall_size.z * 0.5 + 0.48)
	)
	awning_root.rotation_degrees.x = exterior_sign * 7.0
	wall.add_child(awning_root)
	var panel_object := _building_part_object(source, "corrugated_awning", color.darkened(0.08), "default")
	var rib_count := 11
	var rib_width := width / float(rib_count)
	for index in rib_count:
		var x := -width * 0.5 + rib_width * (float(index) + 0.5)
		var ridge_y := 0.025 if index % 2 == 0 else -0.025
		Geometry._add_visual_box(awning_root, "Corrugation%02d" % index, Vector3(rib_width * 1.04, 0.065, 0.95), Vector3(x, ridge_y, 0.0), Vector3.ZERO, panel_object)
	for side in [-1.0, 1.0]:
		Geometry._add_visual_box(awning_root, "AwningBrace%s" % ("L" if side < 0.0 else "R"), Vector3(0.07, 0.07, 0.88), Vector3(side * width * 0.40, -0.22, -0.05), Vector3(22.0 * exterior_sign, 0.0, 0.0), panel_object)


static func _add_irregular_plaster_patch(
	wall: Node3D, wall_size: Vector3, exterior_sign: float, wall_color: Color,
	variant: int, source: Dictionary
) -> void:
	var patch_width := minf(wall_size.x * 0.22, 1.55)
	var patch_height := minf(wall_size.y * 0.20, 0.95)
	var patch_x := wall_size.x * (0.31 if variant % 2 == 0 else -0.31)
	var patch_y := wall_size.y * (-0.16 if variant % 3 == 0 else 0.18)
	var outline: Array[Vector2] = [
		Vector2(-0.53, -0.19), Vector2(-0.31, -0.51), Vector2(0.12, -0.45),
		Vector2(0.54, -0.20), Vector2(0.43, 0.29), Vector2(0.08, 0.52),
		Vector2(-0.39, 0.37),
	]
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normal := Vector3(0.0, 0.0, exterior_sign)
	var face_z := exterior_sign * (wall_size.z * 0.5 + 0.058)
	for index in outline.size():
		var first := outline[index]
		var second := outline[(index + 1) % outline.size()]
		for point: Vector2 in [Vector2.ZERO, first, second]:
			surface_tool.set_normal(normal)
			surface_tool.add_vertex(Vector3(
				patch_x + point.x * patch_width,
				patch_y + point.y * patch_height,
				face_z
			))
	var patch := MeshInstance3D.new()
	patch.name = "IrregularPlasterPatch"
	patch.mesh = surface_tool.commit()
	var patch_color := wall_color.darkened(0.14) if variant % 2 == 0 else wall_color.lightened(0.11)
	patch.material_override = Materials._material_for_object(_building_part_object(source, "plaster_patch", patch_color, "default"))
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.add_child(patch)


static func _add_foundation_band(
	wall: Node3D, wall_size: Vector3, exterior_sign: float,
	color: Color, source: Dictionary
) -> void:
	var foundation_object := _building_part_object(source, "foundation", color.darkened(0.28), "default")
	var face_z := exterior_sign * (wall_size.z * 0.5 + 0.075)
	Geometry._add_visual_box(
		wall, "RaisedFoundationCourse", Vector3(wall_size.x * 0.94, 0.30, 0.11),
		Vector3(0.0, -wall_size.y * 0.5 + 0.15, face_z), Vector3.ZERO, foundation_object
	)
	for index in 3:
		var seam_x := (float(index) - 1.0) * wall_size.x * 0.24
		Geometry._add_visual_box(
			wall, "FoundationJoint%d" % index, Vector3(0.025, 0.27, 0.018),
			Vector3(seam_x, -wall_size.y * 0.5 + 0.15, face_z + exterior_sign * 0.06),
			Vector3.ZERO, _building_part_object(source, "foundation_joint", color.darkened(0.42), "default")
		)


static func _add_electrical_service(wall: Node3D, wall_size: Vector3, exterior_sign: float, source: Dictionary) -> void:
	var service_object := _building_part_object(source, "electrical_service", Color("4a5554"), "default")
	var x := -wall_size.x * 0.32
	var face_z := exterior_sign * (wall_size.z * 0.5 + 0.095)
	Geometry._add_visual_box(
		wall, "ElectricalMeterBox", Vector3(0.34, 0.46, 0.16),
		Vector3(x, -wall_size.y * 0.05, face_z), Vector3.ZERO, service_object
	)
	var conduit := MeshInstance3D.new()
	conduit.name = "ElectricalConduit"
	var conduit_mesh := CylinderMesh.new()
	conduit_mesh.top_radius = 0.028
	conduit_mesh.bottom_radius = 0.028
	conduit_mesh.height = wall_size.y * 0.48
	conduit_mesh.radial_segments = 8
	conduit.mesh = conduit_mesh
	conduit.position = Vector3(x, -wall_size.y * 0.29, face_z)
	conduit.material_override = Materials._material_for_object(service_object)
	wall.add_child(conduit)


static func _add_corner_pilasters(root: Node3D, size: Vector3, color: Color, source: Dictionary) -> void:
	var pilaster_object := _building_part_object(source, "corner_pilaster", color, "default")
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			Geometry._add_visual_box(
				root, "CornerPilaster%s%s" % ["W" if x_sign < 0.0 else "E", "N" if z_sign < 0.0 else "S"],
				Vector3(0.30, size.y + 0.12, 0.30),
				Vector3(x_sign * size.x * 0.5, size.y * 0.5, z_sign * size.z * 0.5),
				Vector3.ZERO, pilaster_object
			)


static func _add_roof_cornice(root: Node3D, size: Vector3, color: Color, source: Dictionary) -> void:
	var cornice_object := _building_part_object(source, "roof_cornice", color.darkened(0.12), "default")
	var cornice_y := size.y + 0.28
	Geometry._add_visual_box(root, "NorthRoofCornice", Vector3(size.x + 0.34, 0.22, 0.26), Vector3(0.0, cornice_y, -size.z * 0.5), Vector3.ZERO, cornice_object)
	Geometry._add_visual_box(root, "SouthRoofCornice", Vector3(size.x + 0.34, 0.22, 0.26), Vector3(0.0, cornice_y, size.z * 0.5), Vector3.ZERO, cornice_object)
	Geometry._add_visual_box(root, "EastRoofCornice", Vector3(0.26, 0.22, size.z), Vector3(size.x * 0.5, cornice_y, 0.0), Vector3.ZERO, cornice_object)
	Geometry._add_visual_box(root, "WestRoofCornice", Vector3(0.26, 0.22, size.z), Vector3(-size.x * 0.5, cornice_y, 0.0), Vector3.ZERO, cornice_object)


static func _add_exposed_brick_relief(wall: Node3D, wall_size: Vector3, exterior_sign: float, source: Dictionary) -> void:
	var mortar_object := _building_part_object(source, "damage_mortar", Color("6d635b"), "default")
	var brick_object := _building_part_object(source, "exposed_brick", Color("87513d"), "default")
	var face_z := exterior_sign * (wall_size.z * 0.5 + 0.045)
	var patch_x := wall_size.x * 0.28
	var patch_y := wall_size.y * 0.12
	Geometry._add_visual_box(wall, "BrokenPlasterRecess", Vector3(1.28, 0.84, 0.055), Vector3(patch_x, patch_y, face_z), Vector3(0.0, 0.0, -4.0), mortar_object)
	for index in 8:
		var row := index / 3
		var column := index % 3
		var brick_x := patch_x - 0.43 + float(column) * 0.40 + (0.18 if row % 2 == 1 else 0.0)
		var brick_y := patch_y - 0.27 + float(row) * 0.27
		Geometry._add_visual_box(wall, "ExposedBrick%02d" % index, Vector3(0.34, 0.17, 0.075), Vector3(brick_x, brick_y, face_z + exterior_sign * 0.045), Vector3(0.0, 0.0, float((index % 3) - 1) * 2.5), brick_object)


static func _add_downspout(wall: Node3D, wall_size: Vector3, exterior_sign: float, source: Dictionary) -> void:
	var pipe_object := _building_part_object(source, "downspout", Color("3d4646"), "default")
	var pipe := MeshInstance3D.new()
	pipe.name = "Downspout"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.045
	mesh.bottom_radius = 0.052
	mesh.height = wall_size.y * 0.88
	mesh.radial_segments = 8
	pipe.mesh = mesh
	pipe.position = Vector3(wall_size.x * 0.43, -wall_size.y * 0.04, exterior_sign * (wall_size.z * 0.5 + 0.075))
	pipe.material_override = Materials._material_for_object(pipe_object)
	wall.add_child(pipe)
	Geometry._add_visual_box(wall, "RoofGutter", Vector3(wall_size.x * 0.94, 0.08, 0.09), Vector3(0.0, wall_size.y * 0.47, exterior_sign * (wall_size.z * 0.5 + 0.075)), Vector3.ZERO, pipe_object)
