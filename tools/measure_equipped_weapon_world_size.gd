extends SceneTree

## Diagnostic: boots the real training range, equips catalog weapons through
## the authorized pickup path, and reports each weapon mesh's WORLD-space
## bounding-box size after the full parent transform chain. Ground truth for
## "does the gun render at operator scale".
## Run headless:
##   godot --headless --path . --script res://tools/measure_equipped_weapon_world_size.gd -- --automated-test

const MAIN_SCENE := preload("res://main.tscn")

const SAMPLES := [
	"ak-47",
	"m16a2",
	"m4a1",
	"mark_23",
	"9mm_sub",
	"m60e3",
	"m82a1a",
	"870",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	for _frame in 15:
		await process_frame
	var weapon_controller: Node = main.get("weapon_controller") as Node
	var player: Node = main.get("player") as Node
	var mannequin: Node = player.get_node_or_null("Mannequin") as Node
	if weapon_controller == null or mannequin == null:
		push_error("WEAPON_SIZE_MEASURE ERROR controller or mannequin missing")
		quit(1)
		return

	for weapon_id in SAMPLES:
		var ok := bool(weapon_controller.call(
			"apply_authorized_weapon_pickup",
			"res://config/weapons/%s.json" % weapon_id
		))
		for _frame in 4:
			await process_frame
		if not ok:
			print("WEAPON_SIZE %s equip FAILED" % weapon_id)
			continue
		var mesh := _find_weapon_mesh(mannequin)
		if mesh == null:
			print("WEAPON_SIZE %s mesh NOT FOUND after equip" % weapon_id)
			continue
		var aabb := _world_aabb(mesh)
		var size := aabb.size
		print(
			"WEAPON_SIZE %s world_aabb=%.3f x %.3f x %.3f (longest %.3f m)" % [
				weapon_id, size.x, size.y, size.z, maxf(size.x, maxf(size.y, size.z)),
			]
		)
	print("WEAPON_SIZE_MEASURE DONE")
	quit(0)


func _find_weapon_mesh(root_node: Node) -> Node3D:
	var candidates := root_node.find_children("WeaponMesh", "Node3D", true, false)
	return candidates[0] if not candidates.is_empty() else null


func _world_aabb(node: Node3D) -> AABB:
	var aabb := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current := stack.pop_back() as Node
		if current is MeshInstance3D:
			var mi := current as MeshInstance3D
			if mi.mesh != null:
				var box := mi.global_transform * mi.mesh.get_aabb()
				if first:
					aabb = box
					first = false
				else:
					aabb = aabb.merge(box)
		for child in current.get_children():
			stack.append(child)
	return aabb
