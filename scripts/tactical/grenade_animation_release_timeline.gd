class_name SocomGrenadeAnimationReleaseTimeline
extends RefCounted

## Visual animation timing only. Gameplay remains responsible for authoritatively
## spawning and consuming the grenade when the driver emits the release cue.

const DEFAULT_RELEASE_FRACTION := 0.56
const RELEASE_FRACTIONS := {
	&"grenade_toss": 0.56,
	&"crouch_grenade_toss": 0.56,
	&"grenade_throw": 0.53,
}


static func is_grenade_clip(clip_name: StringName) -> bool:
	return "grenade" in String(clip_name).to_lower()


static func release_fraction(clip_name: StringName) -> float:
	return clampf(
		float(RELEASE_FRACTIONS.get(clip_name, DEFAULT_RELEASE_FRACTION)),
		0.05,
		0.95
	)


static func release_time_seconds(clip_name: StringName, playback_duration: float) -> float:
	return maxf(playback_duration, 0.0) * release_fraction(clip_name)
