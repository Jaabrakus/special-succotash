extends SceneTree
## Derived unassigned candidates: geometry draft plus shared directional policy.
const Contract := preload("res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd")
const DIRECTORY := "res://art_source/retro1212_calibration/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for entry: Array in [["9mm_sub","family_smg_4_directional_v1","uzi_candidate"],["870","family_shotgun_2_directional_v1","pump_candidate"]]:
		var draft: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY+entry[0]+".visual_rig.draft.json"))
		var directional: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapon_visual_rigs/"+entry[1]+".json"))
		var visual: Dictionary = draft.visual
		visual.handling_profile = directional.visual.handling_profile.duplicate(true)
		visual.model_fbx = "res://assets/weapons/retro_1212/"+entry[2]+".scn"
		draft.source_model_fbx = visual.model_fbx
		if entry[0] == "870":
			var witness: Dictionary
			for item: Dictionary in draft.calibration.surface_witnesses:
				if item.socket == "left_hand_ik_target":
					witness = item
					break
			witness.ray_from = [0.25,-0.2,0.0]
			witness.reason = "Rear third of the actual wooden pump, preserving a bent support elbow with seated stock."
			var surface := _surface_hit(visual.model_fbx,witness)
			if not surface.is_finite():
				push_error("Pump rear-third surface ray failed")
				quit(1)
				return
			visual.weapon_sockets.left_hand_ik_target = {"x":surface.x,"y":surface.y,"z":surface.z}
			visual.handling_profile.dynamic_hold.ready_shoulder_pocket.downward_m = 0.07
			for item: Dictionary in draft.calibration.surface_witnesses:
				if item.socket != "right_hand_grip_target":
					continue
				item.ray_from = [-0.02,0.055,0.3]
				item.reason = "Forward wooden stock wrist, closer to trigger, actual right-side palm/finger-root contact."
				var trigger_surface := _surface_hit(visual.model_fbx,item)
				if not trigger_surface.is_finite():
					push_error("Pump trigger surface ray failed")
					quit(1)
					return
				visual.weapon_sockets.right_hand_grip_target = {"x":trigger_surface.x,"y":trigger_surface.y,"z":trigger_surface.z}
		# Original family marker-forward is +Z; source model-forward is +X.
		# The rigid pivot conversion compensates translation to retain its palm.
		var grip: Dictionary = visual.grip_offset
		var original_basis := Basis.from_euler(Vector3(grip.rot_x,grip.rot_y,grip.rot_z)*PI/180.0)
		var axis_conversion := Basis(Vector3.UP, -PI*0.5)
		var converted_basis := original_basis*axis_conversion
		var original_origin := Vector3(grip.pos_x,grip.pos_y,grip.pos_z)
		var right := _v(visual.weapon_sockets.right_hand_grip_target)
		var new_origin := original_origin-converted_basis*right
		var rotation := converted_basis.get_euler()*180.0/PI
		visual.grip_offset = {"pos_x":new_origin.x,"pos_y":new_origin.y,"pos_z":new_origin.z,"rot_x":rotation.x,"rot_y":rotation.y,"rot_z":rotation.z}
		# Support wrist is expressed in the same pivot coordinate frame.
		var hand: Dictionary = visual.support_hand_pose
		var hand_basis := Basis.from_euler(Vector3(hand.palm_pitch_deg,hand.palm_yaw_deg,hand.palm_roll_deg)*PI/180.0)
		var converted_hand := (axis_conversion.inverse()*hand_basis).get_euler()*180.0/PI
		hand.palm_pitch_deg = converted_hand.x
		hand.palm_yaw_deg = converted_hand.y
		hand.palm_roll_deg = converted_hand.z
		draft.calibration.status = "canonical_fit_candidate_unassigned"
		draft.calibration["directional_policy_source"] = entry[1]
		draft.calibration["axis_conversion"] = "pivot old_basis * Ry(-90deg), trigger-preserving translation; inverse support wrist coordinate conversion"
		draft.calibration.erase("schema_blocker")
		draft.certification.character_contact_verified = false
		draft.certification.geometry_only = false
		draft.certification["review_status"] = "candidate_pending_canonical_physical_and_native_proof"
		draft.certification.required_stances = ["STANDING","CROUCHED","PRONE"]
		var result := Contract.validate(draft)
		if not result.ok:
			push_error(str(result.errors))
			quit(1)
			return
		var path: String = DIRECTORY+entry[0]+".runtime_candidate.json"
		var output := FileAccess.open(path,FileAccess.WRITE)
		output.store_string(JSON.stringify(draft,"\t"))
		print("RETRO1212_UNASSIGNED_RIG ",path)
	quit(0)

func _v(value: Dictionary) -> Vector3:
	return Vector3(value.x,value.y,value.z)

func _surface_hit(path: String, witness: Dictionary) -> Vector3:
	var model := (load(path) as PackedScene).instantiate()
	root.add_child(model)
	var mesh := model.find_child(String(witness.mesh),true,false) as MeshInstance3D
	var origin := Vector3(witness.ray_from[0],witness.ray_from[1],witness.ray_from[2])
	var direction := Vector3(witness.ray_direction[0],witness.ray_direction[1],witness.ray_direction[2])
	var closest := Vector3(INF,INF,INF)
	if mesh:
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for index in range(0,indices.size(),3):
				var hit: Variant = Geometry3D.segment_intersects_triangle(origin,origin+direction*2.0,mesh.global_transform*vertices[indices[index]],mesh.global_transform*vertices[indices[index+1]],mesh.global_transform*vertices[indices[index+2]])
				if hit != null and origin.distance_to(hit) < origin.distance_to(closest):
					closest = hit
	model.free()
	return closest
