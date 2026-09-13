class_name LabLeakTargetDummy
extends CharacterBody3D

## Project Lab Leak: 100% Reliable Hitbox Target Combatant
## Direct CharacterBody3D Colliders (1:1 with Visual Mesh):
## - 🎯 Headshot: Sphere r=0.22m at y=1.68m (85 dmg, 1-2 shots)
## - 🛡️ Frontal Torso: Box 0.46m x 0.55m at y=1.25m (20 dmg, 5 shots)
## - 💪 Left/Right Arms: Boxes 0.38m x 0.35m at x=+-0.42m, y=1.22m (13.5 dmg, 7-8 shots)
## - 🦵 Left/Right Legs: Capsules r=0.16m, h=1.00m at x=+-0.15m, y=0.50m (13.5 dmg, 7-8 shots)

const TROOPER_SCENE := preload("res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx")
const TROOPER_TEXTURE := preload("res://assets/characters/ps1_gas_mask_soldier/trooper.png")
const AnimatedHurtboxRigScript := preload("res://scripts/combat/socom_animated_hurtbox_rig.gd")
const SourceFirearmDamage := preload("res://scripts/combat/source_firearm_damage.gd")
const SourceFirearmPolicy := preload("res://scripts/weapons/source_firearm_policy.gd")
var source_health: RefCounted = null

@export var max_health: float = 100.0
var current_health: float = 100.0
var is_alive: bool = true
var flinch_rotation := Vector3.ZERO

var model_root: Node3D
var health_label: Label3D
var hurtbox_rig: Node3D
var soldier_meshes: Array[MeshInstance3D] = []
var normal_material: StandardMaterial3D

func _ready() -> void:
	# The CharacterBody is only a stable gameplay owner. Damage queries hit the
	# animated Area3D rig below; no anatomical shape can alter movement collision.
	collision_layer = 0
	collision_mask = 0
	_build_soldier()
	_build_hitboxes()

func _build_soldier() -> void:
	model_root = TROOPER_SCENE.instantiate() as Node3D
	model_root.name = "TrooperModel"
	model_root.scale = Vector3.ONE * 62.0
	model_root.rotation.y = PI
	add_child(model_root)

	normal_material = StandardMaterial3D.new()
	normal_material.albedo_texture = TROOPER_TEXTURE
	normal_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_collect_soldier_meshes(model_root)
	_set_soldier_material(normal_material)

	# 3D Floating Health Label
	health_label = Label3D.new()
	health_label.name = "HealthLabel"
	health_label.text = "HOSTILE  100 HP"
	health_label.position.y = 2.10
	health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	health_label.font_size = 22
	health_label.modulate = Color(0.3, 1.0, 0.4)
	add_child(health_label)

func _collect_soldier_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		soldier_meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_soldier_meshes(child)


func _set_soldier_material(material: Material) -> void:
	for mesh in soldier_meshes:
		if is_instance_valid(mesh):
			mesh.material_override = material


func _build_hitboxes() -> void:
	var skeleton := _find_skeleton(model_root)
	if skeleton == null:
		push_error("Target dummy hurtboxes require the visible Skeleton3D")
		return
	hurtbox_rig = AnimatedHurtboxRigScript.new() as Node3D
	hurtbox_rig.name = "AnimatedHurtboxes"
	add_child(hurtbox_rig)
	hurtbox_rig.bind(skeleton, self)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func set_hurtbox_debug_visible(visible: bool) -> void:
	if hurtbox_rig:
		hurtbox_rig.set_debug_visible(visible)


func set_precision_core_debug(visible: bool, core_scale: float = 1.0) -> void:
	if hurtbox_rig:
		hurtbox_rig.set_precision_core_debug(visible, core_scale)


func apply_hurtbox_tuning(settings: Dictionary) -> void:
	if hurtbox_rig:
		hurtbox_rig.apply_radius_scales(settings)


func apply_hurtbox_geometry(settings: Dictionary) -> void:
	if hurtbox_rig:
		hurtbox_rig.apply_geometry_tuning(settings)


func apply_custom_hitboxes(settings: Variant) -> void:
	if hurtbox_rig:
		hurtbox_rig.apply_custom_hitboxes(settings)


func save_hurtbox_tuning() -> bool:
	return bool(hurtbox_rig.save_radius_scales()) if hurtbox_rig else false


func get_hurtbox_tuning() -> Dictionary:
	return hurtbox_rig.get_radius_scales() if hurtbox_rig else {}


func get_hurtbox_geometry() -> Dictionary:
	return hurtbox_rig.get_geometry_tuning() if hurtbox_rig else {}


func get_custom_hitboxes() -> Array[Dictionary]:
	return hurtbox_rig.get_custom_hitboxes() if hurtbox_rig else []


func get_hurtbox_rig() -> Node3D:
	return hurtbox_rig


func get_cached_hit_feedback_ids() -> Dictionary:
	return {
		"normal": normal_material.get_instance_id() if normal_material else 0,
		"meshes": soldier_meshes.size(),
	}

func _process(delta: float) -> void:
	if flinch_rotation.length_squared() > 0.0001:
		flinch_rotation = flinch_rotation.lerp(Vector3.ZERO, delta * 14.0)
		if model_root:
			model_root.rotation.x = flinch_rotation.x
			model_root.rotation.z = flinch_rotation.z

func take_bullet_damage(
	base_damage: float,
	hit_position: Vector3,
	hit_normal: Vector3,
	shooter_origin: Vector3 = Vector3.ZERO,
	headshot_multiplier: float = 3.5
) -> Dictionary:
	# Compatibility for legacy callers. New ballistic rays always resolve the
	# named hurtbox and call take_bullet_damage_region directly.
	var local_pos: Vector3 = global_transform.affine_inverse() * hit_position
	var guessed_region: StringName = &"TORSO"
	if local_pos.y >= 1.48:
		guessed_region = &"HEAD"
	elif local_pos.y < 0.92:
		guessed_region = &"LEFT_THIGH"
	elif absf(local_pos.x) >= 0.23:
		guessed_region = &"LEFT_UPPER_ARM"
	return take_bullet_damage_region(
		base_damage,
		guessed_region,
		hit_position,
		hit_normal,
		shooter_origin,
		headshot_multiplier
	)


func take_profiled_bullet_damage_region(
	base_damage: float,
	hit_region: StringName,
	hit_position: Vector3,
	hit_normal: Vector3,
	shooter_origin: Vector3,
	headshot_multiplier: float,
	directional_torso_modifiers_enabled: bool
) -> Dictionary:
	return take_bullet_damage_region(base_damage, hit_region, hit_position,
		hit_normal, shooter_origin, headshot_multiplier, directional_torso_modifiers_enabled)


func take_source_bullet_damage(combat: Dictionary, hit_region: StringName, _attacker_peer_id: int = 0) -> Dictionary:
	if not is_alive or not SourceFirearmPolicy.valid_impact(combat, hit_region):
		return {"accepted": false, "hit_region": hit_region}
	if source_health == null:
		source_health = SourceFirearmDamage.new()
		if not source_health.initialize(SourceFirearmPolicy.multiplayer_defaults()):
			source_health = null
			return {"accepted": false, "reason": "SOURCE_HEALTH_PROFILE_INVALID"}
		source_health.cap_legacy_health_ratio(current_health / maxf(max_health, 0.001))
	var before_health := current_health
	var result: Dictionary = source_health.apply_projectile(combat.impact_damage, combat.damage_modifier,
		combat.piercing, float(combat.get("distance_m", INF)), combat.effective_range_m,
		combat.maximum_range_m, SourceFirearmPolicy.source_region(hit_region))
	if not bool(result.get("accepted", false)): return result
	current_health = max_health * source_health.weighted_health_ratio()
	flinch_rotation.x = randf_range(-0.15, -0.28)
	flinch_rotation.z = randf_range(-0.10, 0.10)
	if health_label:
		health_label.text = "HOSTILE %.0f%% | %s" % [current_health, String(hit_region)]
	if not source_health.alive:
		_die("HEADSHOT" if hit_region == &"HEAD" else "SOURCE_BODY")
	result.merge({"damage": before_health - current_health, "hit_region": hit_region, "headshot": hit_region == &"HEAD", "remaining_health": current_health,
		"eliminated": not is_alive, "damage_model": SourceFirearmPolicy.DAMAGE_MODEL}, true)
	return result


func take_bullet_damage_region(
	base_damage: float,
	hit_region: StringName,
	hit_position: Vector3,
	_hit_normal: Vector3,
	shooter_origin: Vector3 = Vector3.ZERO,
	headshot_multiplier: float = 3.5,
	directional_torso_modifiers_enabled: bool = true
) -> Dictionary:
	if not is_alive:
		return {"accepted": false, "hit_region": hit_region}

	var region_text := String(hit_region)
	var is_headshot := region_text == "HEAD"
	var is_arm := "ARM" in region_text
	var is_leg := (
		"LEG" in region_text
		or "THIGH" in region_text
		or "CALF" in region_text
		or "FOOT" in region_text
	)
	var is_pelvis := region_text == "PELVIS"
	var is_limb := is_arm or is_leg

	var zone_mult := 1.0
	var hit_type := "TORSO"

	if is_headshot:
		# The equipped weapon profile owns this value. Gunsmith can author a
		# different headshot multiplier for each weapon.
		zone_mult = clampf(headshot_multiplier, 1.0, 10.0)
		hit_type = "HEADSHOT"
	elif is_limb:
		# Limbs (Arms & Legs): 13.5 dmg -> EXACT 7-8 SHOTS TO KILL
		zone_mult = 0.38
		hit_type = "ARM_LIMB" if is_arm else "LEG_LIMB"
	elif directional_torso_modifiers_enabled:
		# Sniper profiles leave torso damage at 1.0 from every direction.
		var forward_vec := -global_transform.basis.z.normalized()
		var incoming_dir := (shooter_origin - global_position).normalized() if shooter_origin != Vector3.ZERO else forward_vec
		var angle_dot := forward_vec.dot(incoming_dir)

		if angle_dot >= 0.25:
			# Frontal Braced Torso: 20 dmg (Exact 5 shots)
			zone_mult = 0.58
			hit_type = "BRACED_FRONT"
		else:
			# Side & Rear Torso: 25 dmg (Exact 4 shots)
			zone_mult = 0.72
			hit_type = "FLANK_REAR"

	# 2. Distance Falloff Calculation (Past 15m)
	var distance_m: float = global_position.distance_to(shooter_origin) if shooter_origin != Vector3.ZERO else 0.0
	var dist_falloff := 1.0
	if distance_m > 15.0:
		dist_falloff = clampf(1.0 - ((distance_m - 15.0) / 45.0) * 0.25, 0.75, 1.0)

	# Pelvis is not a hole and not a headshot. It uses the protected torso band.
	if is_pelvis:
		zone_mult = 0.58
		hit_type = "PELVIS"

	var actual_damage: float = base_damage * zone_mult * dist_falloff
	current_health = maxf(0.0, current_health - actual_damage)
	if source_health != null: source_health.cap_legacy_health_ratio(current_health / maxf(max_health, 0.001))

	# Physical flinch reaction
	flinch_rotation.x = randf_range(-0.15, -0.28)
	flinch_rotation.z = randf_range(-0.10, 0.10)

	if health_label:
		match hit_type:
			"HEADSHOT":
				health_label.text = "🎯 HEADSHOT! -%.0f (%.0f HP)" % [actual_damage, current_health]
				health_label.modulate = Color(1.0, 0.15, 0.15)
			"FLANK_REAR":
				health_label.text = "⚡ FLANK -%.0f (%.0f HP)" % [actual_damage, current_health]
				health_label.modulate = Color(1.0, 0.65, 0.2)
			"BRACED_FRONT":
				health_label.text = "🛡️ BRACED -%.0f (%.0f HP)" % [actual_damage, current_health]
				health_label.modulate = Color(0.4, 0.9, 1.0)
			"ARM_LIMB", "LEG_LIMB":
				health_label.text = "🦵 LIMB -%.0f (%.0f HP)" % [actual_damage, current_health]
				health_label.modulate = Color(0.7, 0.7, 0.8)
			_:
				health_label.text = "HOSTILE  %.0f HP (-%.0f)" % [current_health, actual_damage]
				health_label.modulate = Color(1.0, 1.0, 1.0)

	# Hit confirmation belongs to the HUD; impacts do not recolor the body.

	if current_health <= 0.0:
		_die(hit_type)

	return {
		"accepted": true,
		"hit_region": hit_region,
		"hit_type": hit_type,
		"damage": actual_damage,
		"remaining_health": current_health,
		"headshot": is_headshot
	}


func take_explosion_damage(
	damage_value: float,
	_explosion_origin: Vector3,
	_attacker_peer_id: int = 0
) -> Dictionary:
	if not is_alive:
		return {"accepted": false}
	var damage := maxf(0.0, damage_value)
	current_health = maxf(0.0, current_health - damage)
	if source_health != null: source_health.cap_legacy_health_ratio(current_health / maxf(max_health, 0.001))
	flinch_rotation.x = randf_range(-0.15, -0.28)
	flinch_rotation.z = randf_range(-0.10, 0.10)
	if health_label:
		health_label.text = "💥 FRAG -%.0f (%.0f HP)" % [damage, current_health]
		health_label.modulate = Color(1.0, 0.48, 0.16)
	if current_health <= 0.0:
		_die("EXPLOSION")
	return {
		"accepted": damage > 0.0,
		"damage": damage,
		"remaining_health": current_health,
		"eliminated": not is_alive,
	}

func _die(hit_type: String) -> void:
	is_alive = false
	if hurtbox_rig:
		hurtbox_rig.set_enabled(false)
	if health_label:
		if hit_type == "FLANK_REAR":
			health_label.text = "⚡ FLANK ELIMINATION"
		elif hit_type == "HEADSHOT":
			health_label.text = "🎯 HEADSHOT ELIMINATION"
		else:
			health_label.text = "💀 ELIMINATED"
		health_label.modulate = Color(1.0, 0.1, 0.1)

	# Fall over
	var t := create_tween()
	t.tween_property(model_root, "rotation:x", deg_to_rad(-85.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(model_root, "position:y", 0.15, 0.35)

	# Auto-respawn after 2.5 seconds
	get_tree().create_timer(2.5).timeout.connect(func():
		source_health = null
		current_health = max_health
		is_alive = true
		if hurtbox_rig and is_instance_valid(hurtbox_rig):
			hurtbox_rig.set_enabled(true)
		if model_root and is_instance_valid(model_root):
			var t_respawn := create_tween()
			t_respawn.tween_property(model_root, "rotation:x", 0.0, 0.3)
			t_respawn.parallel().tween_property(model_root, "position:y", 0.0, 0.3)
		if health_label and is_instance_valid(health_label):
			health_label.text = "HOSTILE  100 HP"
			health_label.modulate = Color(0.3, 1.0, 0.4)
	)
