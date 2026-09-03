class_name SocomBulletPenetration
extends RefCounted

## CS:GO-style dual-raycast bullet penetration and wallbanging engine.
## Calculates entry, exit points, material thickness, and damage degradation.

enum MaterialType {
	GENERIC,
	WOOD,
	DRYWALL,
	PLASTIC,
	GLASS,
	SHEET_METAL,
	CONCRETE,
	FLESH
}

# Material penetration modifiers (relative to CS:GO Source Engine specs)
const MATERIAL_PROPERTIES := {
	MaterialType.GENERIC: {"density": 1.0, "max_thickness_m": 0.20, "penetration_mult": 0.80},
	MaterialType.WOOD: {"density": 0.5, "max_thickness_m": 0.40, "penetration_mult": 0.90},
	MaterialType.DRYWALL: {"density": 0.3, "max_thickness_m": 0.50, "penetration_mult": 0.95},
	MaterialType.PLASTIC: {"density": 0.4, "max_thickness_m": 0.35, "penetration_mult": 0.90},
	MaterialType.GLASS: {"density": 0.1, "max_thickness_m": 0.80, "penetration_mult": 0.98},
	MaterialType.SHEET_METAL: {"density": 1.8, "max_thickness_m": 0.12, "penetration_mult": 0.65},
	MaterialType.CONCRETE: {"density": 3.0, "max_thickness_m": 0.08, "penetration_mult": 0.35},
	MaterialType.FLESH: {"density": 0.6, "max_thickness_m": 0.60, "penetration_mult": 0.85},
}

const MAX_PENETRATION_COUNT := 3
const REVERSE_RAY_SEARCH_DISTANCE_M := 0.80
const MINIMUM_SURFACE_STEP_M := 0.02


static func identify_material(collider: Object) -> MaterialType:
	if collider == null:
		return MaterialType.GENERIC
	if collider.has_meta("surface_material"):
		var mat_name: String = str(collider.get_meta("surface_material")).to_lower()
		if "wood" in mat_name: return MaterialType.WOOD
		if "drywall" in mat_name or "plaster" in mat_name: return MaterialType.DRYWALL
		if "glass" in mat_name: return MaterialType.GLASS
		if "metal" in mat_name: return MaterialType.SHEET_METAL
		if "concrete" in mat_name or "stone" in mat_name or "brick" in mat_name: return MaterialType.CONCRETE
		if "flesh" in mat_name or "body" in mat_name: return MaterialType.FLESH

	var obj_name: String = ""
	if collider is Node:
		obj_name = (collider as Node).name.to_lower()
	if "wood" in obj_name or "door" in obj_name or "crate" in obj_name or "box" in obj_name:
		return MaterialType.WOOD
	if "glass" in obj_name or "window" in obj_name:
		return MaterialType.GLASS
	if "metal" in obj_name or "fence" in obj_name or "barrel" in obj_name:
		return MaterialType.SHEET_METAL
	if "concrete" in obj_name or "wall" in obj_name or "floor" in obj_name or "brick" in obj_name:
		return MaterialType.CONCRETE
	if "dummy" in obj_name or "player" in obj_name or "trooper" in obj_name:
		return MaterialType.FLESH

	return MaterialType.GENERIC


## Traces a bullet path, penetrating through thin walls and reporting all impacts in order.
static func trace_bullet(
	space_state: PhysicsDirectSpaceState3D,
	start_pos: Vector3,
	direction: Vector3,
	max_range: float,
	initial_damage: float,
	penetration_power: float = 1.5,
	exclude_rids: Array[RID] = []
) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if space_state == null:
		return results

	var current_pos := start_pos
	var current_dir := direction.normalized()
	var remaining_damage := initial_damage
	var remaining_range := max_range
	var penetrations_left := MAX_PENETRATION_COUNT
	var local_exclude := exclude_rids.duplicate()

	while penetrations_left >= 0 and remaining_damage > 1.0 and remaining_range > 0.1:
		var ray_target := current_pos + current_dir * remaining_range
		var ray_query := PhysicsRayQueryParameters3D.create(current_pos, ray_target)
		ray_query.collide_with_areas = true
		ray_query.collide_with_bodies = true
		ray_query.exclude = local_exclude

		var hit := space_state.intersect_ray(ray_query)
		if hit.is_empty():
			# Traveled full range into open air
			break

		var hit_pos: Vector3 = hit.position
		var hit_normal: Vector3 = hit.normal
		var hit_collider: Object = hit.collider
		var hit_rid: RID = hit.rid
		var hit_distance: float = current_pos.distance_to(hit_pos)
		remaining_range = maxf(0.0, remaining_range - hit_distance)

		# Check if we hit an anatomical target / character hurtbox
		var is_hurtbox := false
		if hit_collider is Area3D:
			is_hurtbox = (
				hit_collider.has_method("is_anatomical_hurtbox")
				or hit_collider.has_method("get_hit_region")
				or hit_collider.has_meta("hurtbox_region")
				or hit_collider.has_meta("anatomical_region")
			)
		elif hit_collider != null and (hit_collider.has_method("take_bullet_damage_region") or hit_collider.has_method("apply_damage")):
			is_hurtbox = true

		if is_hurtbox:
			results.append({
				"entry_pos": hit_pos,
				"exit_pos": hit_pos,
				"normal": hit_normal,
				"collider": hit_collider,
				"rid": hit_rid,
				"damage": remaining_damage,
				"is_wallbang": (results.size() > 0),
				"is_target": true,
				"material": MaterialType.FLESH,
				"thickness_m": 0.0
			})
			# Pass through flesh with minor degradation for collateral hits
			local_exclude.append(hit_rid)
			remaining_damage *= 0.70
			current_pos = hit_pos + current_dir * MINIMUM_SURFACE_STEP_M
			penetrations_left -= 1
			continue

		# Hit an environmental solid wall / obstacle: Calculate exit point
		var material := identify_material(hit_collider)
		var mat_props: Dictionary = MATERIAL_PROPERTIES.get(material, MATERIAL_PROPERTIES[MaterialType.GENERIC])
		var max_pen_thickness: float = float(mat_props.get("max_thickness_m", 0.20)) * clampf(penetration_power, 0.5, 3.0)

		# Step ahead and cast backwards to find the wall exit surface
		var probe_start := hit_pos + current_dir * minf(REVERSE_RAY_SEARCH_DISTANCE_M, max_pen_thickness + 0.05)
		var reverse_query := PhysicsRayQueryParameters3D.create(probe_start, hit_pos)
		reverse_query.collide_with_areas = false
		reverse_query.collide_with_bodies = true

		var exit_hit := space_state.intersect_ray(reverse_query)
		var exit_pos := hit_pos
		var thickness := 0.0

		if not exit_hit.is_empty() and exit_hit.collider == hit_collider:
			exit_pos = exit_hit.position
			thickness = hit_pos.distance_to(exit_pos)
		else:
			# Single thin plane or no opposite face detected within search limit
			thickness = 0.04
			exit_pos = hit_pos + current_dir * thickness

		results.append({
			"entry_pos": hit_pos,
			"exit_pos": exit_pos,
			"normal": hit_normal,
			"collider": hit_collider,
			"rid": hit_rid,
			"damage": remaining_damage,
			"is_wallbang": (results.size() > 0),
			"is_target": false,
			"material": material,
			"thickness_m": thickness
		})

		# Check if thickness exceeds maximum penetration capacity
		if thickness > max_pen_thickness:
			# Bullet stopped by heavy wall
			break

		# Calculate damage loss: CS:GO formula
		var pen_mult: float = float(mat_props.get("penetration_mult", 0.75))
		var density: float = float(mat_props.get("density", 1.0))
		var thickness_loss := (thickness / maxf(max_pen_thickness, 0.01)) * 0.50
		remaining_damage = remaining_damage * pen_mult * (1.0 - thickness_loss)

		# Advance past the wall exit point
		current_pos = exit_pos + current_dir * MINIMUM_SURFACE_STEP_M
		penetrations_left -= 1
		local_exclude.append(hit_rid)

	return results
