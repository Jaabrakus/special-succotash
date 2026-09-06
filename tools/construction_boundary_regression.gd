extends SceneTree

const BOUNDARIES := {
	"res://scripts/maps/socom_map_runtime.gd": [1400, "FacadeBuilder._build_favela_building(object)"],
	"res://scripts/labs/retarget_mapping_lab.gd": [1000, "SkeletonInspection._find_skeleton("],
	"res://scripts/player/test_mannequin.gd": [1000, "ProxyPrimitives._box_on("],
	"res://scripts/runtime/main_gameplay_hud.gd": [500, "HudBuilder._build_ui(self)"],
	"res://scripts/runtime/main_grenade_runtime.gd": [500, "EquipmentSelection.open_equipment_wheel(self)"],
	"res://scripts/player/operator_weapon_pose_ready.gd": [500, "AuthoredPose.apply_hand_follow(self,"],
	"res://scripts/player/operator_weapon_pose_kinematics.gd": [500, "AimAlignment._align_weapon_to_aim(self,"],
	"res://scripts/player/operator_weapon_pose_placement.gd": [500, "AimAlignment._measure_gunsmith_weapon_roll_error(self,"],
	"res://scripts/player/operator_locomotion_blend_tree.gd": [1000, "ModernRouteBuilder.build(self, root, available_clips)"],
}
const HELPERS := [
	"res://scripts/maps/socom_map_facade_builder.gd",
	"res://scripts/maps/socom_map_geometry.gd",
	"res://scripts/maps/socom_map_surface_materials.gd",
	"res://scripts/labs/retarget_skeleton_inspection.gd",
	"res://scripts/player/operator_proxy_primitives.gd",
	"res://scripts/runtime/main_gameplay_hud_builder.gd",
	"res://scripts/runtime/main_equipment_selection.gd",
	"res://scripts/runtime/main_held_grenade_visual.gd",
	"res://scripts/player/operator_weapon_authored_pose.gd",
	"res://scripts/player/operator_weapon_aim_alignment.gd",
	"res://scripts/player/operator_locomotion_route_builder.gd",
	"res://scripts/player/operator_pistol_carry_reach.gd",
]

func _initialize() -> void:
	var failures: Array[String] = []
	for path: String in BOUNDARIES:
		var source := FileAccess.get_file_as_string(path)
		if source.count("\n") > int(BOUNDARIES[path][0]):
			failures.append("budget: " + path)
		if not source.contains(String(BOUNDARIES[path][1])):
			failures.append("canonical delegation: " + path)
	for path: String in HELPERS:
		var source := FileAccess.get_file_as_string(path)
		if source.count("\n") > 500 or not source.begins_with("extends RefCounted"):
			failures.append("bounded non-node helper: " + path)
		if source.contains("func _process(") or source.contains("func _physics_process("):
			failures.append("duplicate frame owner: " + path)
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			failures.append("compile: " + path)
	print("CONSTRUCTION_BOUNDARY_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)
