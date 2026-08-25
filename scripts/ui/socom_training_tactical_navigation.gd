class_name SocomTrainingTacticalNavigation
extends RefCounted

const MapGameplay := preload("res://scripts/maps/socom_map_gameplay_contract.gd")


static func configure_sites(compass: Node, document: Dictionary) -> void:
	if compass == null or not compass.has_method("replace_anchor_group"):
		return
	var layout := MapGameplay.demolition_layout(document)
	var entries: Array[Dictionary] = []
	var alpha_sites: Array = layout.get("alpha_targets", [])
	for index in alpha_sites.size():
		entries.append({
			"id": StringName("alpha_site_%d" % index),
			"label": "ALPHA" if alpha_sites.size() == 1 else "ALPHA %d" % (index + 1),
			"world_pos": Vector3(alpha_sites[index]),
			"color": Color("4fa3ff"),
		})
	var bravo_sites: Array = layout.get("bravo_targets", [])
	for index in bravo_sites.size():
		entries.append({
			"id": StringName("bravo_site_%d" % index),
			"label": "BRAVO" if bravo_sites.size() == 1 else "BRAVO %d" % (index + 1),
			"world_pos": Vector3(bravo_sites[index]),
			"color": Color("ff655e"),
		})
	compass.call("replace_anchor_group", &"objective_sites", entries)


static func refresh_bomb(
	compass: Node,
	player: Node3D,
	carried: bool,
	planted: bool,
	visuals: Array
) -> void:
	if compass == null or not compass.has_method("replace_anchor_group"):
		return
	var entries: Array[Dictionary] = []
	if carried and player != null:
		entries.append({
			"id": &"training_bomb",
			"label": "BOMB CARRIER",
			"world_pos": player.global_position,
			"color": Color("f4d34f"),
		})
	else:
		for visual: Variant in visuals:
			if visual is Node3D and is_instance_valid(visual) and (visual as Node3D).visible:
				entries.append({
					"id": &"training_bomb",
					"label": "BOMB PLANTED" if planted else "BOMB",
					"world_pos": (visual as Node3D).global_position,
					"color": Color("f4d34f"),
				})
				break
	compass.call("replace_anchor_group", &"bomb", entries)
