class_name GunsmithWeaponSceneExporter
extends RefCounted

## Converts an authored Gunsmith weapon snapshot into the runtime PackedScene.

const SCENE_DIRECTORY := "res://scenes/weapons/"


static func export_scene(snapshot: Dictionary) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENE_DIRECTORY))
	var weapon_id := String(snapshot.get("weapon_id", "weapon")).to_lower()
	var root := Node3D.new()
	root.name = String(snapshot.get("display_name", weapon_id))
	var weapon_mesh := snapshot.get("weapon_mesh") as Node3D
	if weapon_mesh != null:
		var model_copy := weapon_mesh.duplicate() as Node3D
		model_copy.name = "WeaponMesh"
		root.add_child(model_copy)
		model_copy.owner = root
		_add_socket(root, "Socket_LeftHand", snapshot.get("left_hand_socket", Vector3.ZERO))
		_add_socket(root, "Socket_RightHand", snapshot.get("right_hand_socket", Vector3.ZERO))
		_add_socket(root, "Socket_Muzzle", snapshot.get("muzzle_socket", Vector3.ZERO))
		_add_socket(root, "Socket_BarrelBase", snapshot.get("barrel_base_socket", Vector3.ZERO))
		_add_socket(root, "Socket_Buttstock", snapshot.get("buttstock_socket", Vector3.ZERO))
		_add_socket(root, "Socket_Ejection", snapshot.get("ejection_socket", Vector3.ZERO))
		_add_socket(root, "Socket_Optic", snapshot.get("optic_socket", Vector3.ZERO))
		_add_attachment(root, snapshot.get("silencer_mesh") as Node3D, "Attachment_Silencer")
		_add_attachment(root, snapshot.get("scope_mesh") as Node3D, "Attachment_Scope")
	var packed := PackedScene.new()
	var pack_result := packed.pack(root)
	if pack_result != OK:
		root.free()
		return {"ok": false, "error": error_string(pack_result)}
	var path := SCENE_DIRECTORY + weapon_id + ".tscn"
	var save_result := ResourceSaver.save(packed, path)
	root.free()
	if save_result != OK:
		return {"ok": false, "error": error_string(save_result)}
	return {"ok": true, "path": path}


static func _add_socket(root: Node3D, socket_name: String, position_value: Variant) -> void:
	var socket := Marker3D.new()
	socket.name = socket_name
	socket.position = position_value as Vector3 if position_value is Vector3 else Vector3.ZERO
	root.add_child(socket)
	socket.owner = root


static func _add_attachment(root: Node3D, source: Node3D, attachment_name: String) -> void:
	if source == null:
		return
	var attachment := source.duplicate() as Node3D
	attachment.name = attachment_name
	root.add_child(attachment)
	attachment.owner = root
