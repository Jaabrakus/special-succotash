extends RefCounted

## Presentation clocks only. Snapshots remain owned by gameplay/server systems.
const PATH := "res://config/contextual_hud.json"
var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
var remaining := {"weapon": 0.0, "health": 0.0, "throwable": 0.0}
var glance_elapsed := 0.0

func save_profile() -> Error:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(profile, "\t") + "\n")
	return OK

func reveal(channel: String, duration: float = -1.0) -> void:
	remaining[channel] = maxf(float(remaining.get(channel, 0.0)),
		float(profile.get("event_hold_seconds", 2.0)) if duration < 0.0 else duration)

func advance(delta: float) -> void:
	var dt := maxf(delta, 0.0)
	for channel in remaining:
		remaining[channel] = maxf(-float(profile.fade_seconds), float(remaining[channel]) - dt)
	glance_elapsed += dt
	var interval := maxf(1.0, float(profile.glance_interval_seconds))
	if glance_elapsed >= interval:
		glance_elapsed = fmod(glance_elapsed, interval)
		for channel in remaining:
			reveal(channel, float(profile.glance_hold_seconds))

func alpha(channel: String, critical: bool = false) -> float:
	if critical or not bool(profile.enabled):
		return 1.0
	var fraction := clampf(1.0 + float(remaining[channel]) / maxf(0.01, float(profile.fade_seconds)), 0.0, 1.0)
	return lerpf(float(profile.idle_alpha), 1.0, fraction)
