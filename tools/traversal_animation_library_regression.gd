extends SceneTree

const ROUTE_MAP := "res://config/traversal_animation_map.json"
const EXPECTED_COUNTS := {
	"climbing": 181,
	"grenade": 11,
	"ladder": 40,
	"locomotion_additive": 13,
	"locomotion_air": 137,
	"locomotion_crawl": 50,
	"locomotion_crouch": 227,
	"locomotion_idle": 12,
	"locomotion_roll": 9,
	"locomotion_run": 451,
	"locomotion_turn": 24,
	"locomotion_walk": 382,
	"mantle_vault": 6,
	"narrow_ledge": 10,
	"rope": 28,
	"swimming": 15,
	"weapon_equip": 21,
	"weapon_pickup": 22,
	"weapon_recoil": 6,
	"weapon_reload": 15,
	"wheel_valve": 9,
	"zipline": 7,
}

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var file := FileAccess.open(ROUTE_MAP, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_expect(parsed is Dictionary, "route map is valid JSON")
	if not parsed is Dictionary:
		_finish()
		return
	var route_map := parsed as Dictionary
	_expect(String(route_map.get("root_motion_policy", "")) == "visual_only", "root motion remains presentation-only")
	var families: Dictionary = route_map.get("families", {})
	var route_total := 0
	for family_name: String in EXPECTED_COUNTS:
		var routes: Dictionary = families.get(family_name, {})
		var expected_count := int(EXPECTED_COUNTS[family_name])
		_expect(routes.size() == expected_count, "%s has %d routes" % [family_name, expected_count])
		route_total += routes.size()
		var sample_path := String(routes.values()[0]) if not routes.is_empty() else ""
		_expect(ResourceLoader.exists(sample_path, "PackedScene"), "%s sample scene exists" % family_name)
		var packed := load(sample_path) as PackedScene if not sample_path.is_empty() else null
		_expect(packed != null, "%s sample scene loads" % family_name)
		if packed != null:
			var instance := packed.instantiate()
			_expect(_find_descendant(instance, "Skeleton3D") != null, "%s sample has a skeleton" % family_name)
			_expect(_find_descendant(instance, "AnimationPlayer") != null, "%s sample has animation data" % family_name)
			instance.free()
	_expect(route_total == 1676, "all 1,676 AGLS animation routes are published")
	_finish()


func _find_descendant(node: Node, required_class: String) -> Node:
	if node.is_class(required_class):
		return node
	for child in node.get_children():
		var found := _find_descendant(child, required_class)
		if found != null:
			return found
	return null


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("TRAVERSAL_LIBRARY_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("TRAVERSAL_LIBRARY_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("TRAVERSAL_ANIMATION_LIBRARY_REGRESSION PASS")
		quit(0)
	else:
		print("TRAVERSAL_ANIMATION_LIBRARY_REGRESSION FAIL ", failures)
		quit(1)
