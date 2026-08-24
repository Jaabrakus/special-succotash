class_name SocomAnimationLayerComposer
extends RefCounted

## Bakes compatible bone tracks from several animations into one reusable clip.
## Each body region owns a disjoint bone set, so the result is deterministic and
## does not require multiple AnimationPlayers at runtime.

const REGIONS: Array[String] = [
	"lower_body", "torso", "left_arm", "right_arm", "head",
]


func compose(sources: Dictionary, fps: float = 30.0) -> Animation:
	var full_body: Animation = sources.get("full_body") as Animation
	# A one-shot upper-body preview must keep the action clip's duration while
	# borrowing only the legs from the current locomotion clip.
	var reference: Animation = sources.get("duration_reference") as Animation
	if reference == null:
		reference = full_body
	if reference == null:
		reference = sources.get("lower_body") as Animation
	if reference == null:
		for region in REGIONS:
			if sources.get(region) is Animation:
				reference = sources[region] as Animation
				break
	if reference == null:
		return null
	var result := Animation.new()
	result.length = maxf(reference.length, 1.0 / maxf(fps, 1.0))
	result.step = 1.0 / maxf(fps, 1.0)
	result.loop_mode = reference.loop_mode
	for region in REGIONS:
		var source: Animation = sources.get(region) as Animation
		if source == null:
			source = full_body
		if source == null:
			continue
		_copy_region_tracks(source, result, region)
	return result


func _copy_region_tracks(source: Animation, target: Animation, region: String) -> void:
	var source_length := maxf(source.length, 0.0001)
	for source_track in range(source.get_track_count()):
		if _region_for_track(source.track_get_path(source_track)) != region:
			continue
		var target_track := target.add_track(source.track_get_type(source_track))
		target.track_set_path(target_track, source.track_get_path(source_track))
		target.track_set_interpolation_type(target_track, source.track_get_interpolation_type(source_track))
		target.track_set_interpolation_loop_wrap(target_track, source.track_get_interpolation_loop_wrap(source_track))
		for key_index in range(source.track_get_key_count(source_track)):
			var normalized_time := source.track_get_key_time(source_track, key_index) / source_length
			target.track_insert_key(
				target_track,
				clampf(normalized_time, 0.0, 1.0) * target.length,
				source.track_get_key_value(source_track, key_index),
				source.track_get_key_transition(source_track, key_index)
			)


func _region_for_track(path: NodePath) -> String:
	var bone_name := String(path).split(":")[-1].to_lower()
	if "leftshoulder" in bone_name or "leftarm" in bone_name or "lefthand" in bone_name or "armupper.l" in bone_name or "armlower.l" in bone_name or "hand.l" in bone_name:
		return "left_arm"
	if "rightshoulder" in bone_name or "rightarm" in bone_name or "righthand" in bone_name or "armupper.r" in bone_name or "armlower.r" in bone_name or "hand.r" in bone_name:
		return "right_arm"
	if "neck" in bone_name or "head" in bone_name or "eye" in bone_name:
		return "head"
	if "spine" in bone_name and not "spinelower" in bone_name:
		return "torso"
	if (
		"hips" in bone_name
		or "spinelower" in bone_name
		or "upleg" in bone_name
		or "legthigh" in bone_name
		or "legshin" in bone_name
		or "leftleg" in bone_name
		or "rightleg" in bone_name
		or "foot" in bone_name
		or "toe" in bone_name
	):
		return "lower_body"
	return ""
