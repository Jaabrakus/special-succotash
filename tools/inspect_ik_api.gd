extends SceneTree

func _init() -> void:
	for class_label in ["SkeletonModifier3D", "IKModifier3D", "TwoBoneIK3D", "ModifierBoneTarget3D", "BoneAttachment3D", "Skeleton3D"]:
		print("CLASS ", class_label, " parent=", ClassDB.get_parent_class(class_label), " exists=", ClassDB.class_exists(class_label))
		if ClassDB.class_exists(class_label):
			for enum_name in ClassDB.class_get_enum_list(class_label, true):
				print("  ENUM ", enum_name, " ", ClassDB.class_get_enum_constants(class_label, enum_name, true))
			for property in ClassDB.class_get_property_list(class_label, true):
				print("  PROPERTY ", property.get("name", ""), " type=", property.get("type", -1))
			for method in ClassDB.class_get_method_list(class_label, true):
				var method_name := String(method.get("name", ""))
				if class_label in ["IKModifier3D", "TwoBoneIK3D"] or "bone" in method_name.to_lower() or "target" in method_name.to_lower() or "modif" in method_name.to_lower() or "override" in method_name.to_lower():
					print("  ", method_name, " args=", method.get("args", []))
	var two_bone := TwoBoneIK3D.new()
	two_bone.set_setting_count(2)
	print("INSTANCE TWO BONE PROPERTIES")
	for property in two_bone.get_property_list():
		print("  ", property.get("name", ""), " = ", two_bone.get(StringName(property.get("name", ""))))
	two_bone.free()
	quit()
