class_name SocomOperatorTeamAppearance
extends RefCounted

const PATH := "res://config/operator_team_appearance.json"
const CLOTH := preload("res://assets/shaders/operator_team_cloth.gdshader")
static var _profile: Dictionary = {}

static func profile() -> Dictionary:
	if _profile.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_profile = parsed if parsed is Dictionary else {}
	return _profile

static func color_for(team: int) -> Color:
	return Color(String(profile().get("teams", {}).get(str(team), "579fe8")))

static func palette_color(name: String) -> Color:
	return Color(String(profile().get("palette", {}).get(name, "579fe8")))

static func apply(model: Node, team: int, color_name: String = "") -> void:
	if model == null:
		return
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var ancestor := node.get_parent()
		var attached := false
		while ancestor != null and ancestor != model:
			if ancestor is BoneAttachment3D:
				attached = true
				break
			ancestor = ancestor.get_parent()
		if attached:
			continue
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if source == null or source.albedo_texture == null:
				continue
			var material := ShaderMaterial.new()
			material.shader = CLOTH
			material.set_shader_parameter("source_texture", source.albedo_texture)
			material.set_shader_parameter("base_tint", source.albedo_color)
			material.set_shader_parameter("team_color", palette_color(color_name) if not color_name.is_empty() else color_for(team))
			material.set_shader_parameter("cloth_brightness", float(profile().get("palette_brightness", {}).get(color_name, 1.0)))
			mesh.set_surface_override_material(surface, material)
