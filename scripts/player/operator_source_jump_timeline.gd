extends RefCounted

## Read-only projection of CharacterBody phases into source animation time.
## No jump impulses, ground prediction, permissions, or bone writes live here.
var previous_state: StringName = &""
var takeoff_slot: StringName = &""
var descending := false

func reset() -> void:
	previous_state = &""
	takeoff_slot = &""
	descending = false

func sample(state: StringName, vertical_speed: float, moving: bool,
		launch_speed: float, landing_elapsed: float, landing_duration: float) -> Dictionary:
	var slot: StringName = &""
	var progress := 0.0
	if state == &"AIRBORNE":
		if previous_state != &"AIRBORNE":
			takeoff_slot = &"jump_up" if moving else &"jump_up_standing"
			descending = vertical_speed <= 0.0
		# Once descent begins, steering or a small upward correction cannot
		# restart launch. Walking off a ledge starts directly in the air pose.
		descending = descending or vertical_speed <= 0.0
		slot = (&"jump_running_air" if takeoff_slot == &"jump_up" else &"jump_loop") if descending else takeoff_slot
		progress = clampf(-vertical_speed / maxf(launch_speed, 0.001), 0.0, 1.0) if descending else clampf(1.0 - vertical_speed / maxf(launch_speed, 0.001), 0.0, 1.0)
	elif state == &"LANDING":
		slot = &"jump_running_land" if takeoff_slot == &"jump_up" else &"jump_down"
		progress = clampf(landing_elapsed / maxf(landing_duration, 0.001), 0.0, 1.0)
	else:
		reset()
	previous_state = state
	return {"slot": slot, "progress": progress} if slot != &"" else {}
