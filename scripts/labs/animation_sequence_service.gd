class_name SocomAnimationSequenceService
extends RefCounted

const REGION_ORDER: Array[String] = [
	"full_body",
	"lower_body",
	"torso",
	"left_arm",
	"right_arm",
	"head",
]

## Pure sequence operations shared by the Studio controller and regressions.
## This object has no UI nodes and never writes imported animation resources.


func build_animation(
	segments: Array[Dictionary],
	clip_editor: RefCounted,
	layer_composer: RefCounted,
	fps: float
) -> Animation:
	var region_segments: Dictionary = {}
	for region in REGION_ORDER:
		region_segments[region] = []
	for segment in segments:
		var region := str(segment.get("layer", "full_body"))
		if not region_segments.has(region):
			region = "full_body"
		(region_segments[region] as Array).append(segment)
	var region_sources: Dictionary = {}
	for region in region_segments.keys():
		var lane: Array = region_segments[region]
		if lane.is_empty():
			continue
		var typed_lane: Array[Dictionary] = []
		for lane_segment in lane:
			typed_lane.append(lane_segment)
		var lane_animation: Animation = clip_editor.combine(typed_lane, fps)
		if lane_animation != null and lane_animation.get_track_count() > 0:
			region_sources[region] = lane_animation
	if region_sources.is_empty():
		return null
	if region_sources.size() == 1 and region_sources.has("full_body"):
		return region_sources["full_body"] as Animation
	return layer_composer.compose(region_sources, fps)


func toggle_region(selected_regions: Dictionary, region: String) -> void:
	if region == "full_body":
		selected_regions.clear()
		selected_regions["full_body"] = true
		return
	selected_regions.erase("full_body")
	if selected_regions.has(region):
		selected_regions.erase(region)
	else:
		selected_regions[region] = true
	if selected_regions.is_empty():
		selected_regions["full_body"] = true


func selected_region_keys(selected_regions: Dictionary) -> Array[String]:
	var selected: Array[String] = []
	for region in REGION_ORDER:
		if selected_regions.has(region):
			selected.append(region)
	if selected.is_empty():
		selected.append("full_body")
	return selected


func lane_has_segments(segments: Array[Dictionary], layer: String) -> bool:
	for segment in segments:
		if str(segment.get("layer", "full_body")) == layer:
			return true
	return false


func lane_has_segment_before(segments: Array[Dictionary], index: int, layer: String) -> bool:
	for candidate in range(index):
		if str(segments[candidate].get("layer", "full_body")) == layer:
			return true
	return false


func insert_transition(
	segments: Array[Dictionary],
	selected_index: int,
	transition: Dictionary,
	before_selected: bool
) -> int:
	if selected_index < 0 or selected_index >= segments.size():
		return -1
	var target_layer := str(segments[selected_index].get("layer", "full_body"))
	transition["layer"] = target_layer
	if before_selected:
		transition["transition_frames"] = 6 if lane_has_segment_before(segments, selected_index, target_layer) else 0
		segments.insert(selected_index, transition)
		segments[selected_index + 1]["transition_frames"] = 6
		return selected_index
	transition["transition_frames"] = 6
	segments.insert(selected_index + 1, transition)
	return selected_index + 1


func move_segment_in_lane(segments: Array[Dictionary], index: int, direction: int) -> bool:
	if index < 0 or index >= segments.size():
		return false
	var layer := str(segments[index].get("layer", "full_body"))
	var lane_indices: Array[int] = []
	for candidate in range(segments.size()):
		if str(segments[candidate].get("layer", "full_body")) == layer:
			lane_indices.append(candidate)
	var lane_position := lane_indices.find(index)
	var target_position := lane_position + direction
	if lane_position < 0 or target_position < 0 or target_position >= lane_indices.size():
		return false
	var target_index := lane_indices[target_position]
	var segment := segments[index]
	segments[index] = segments[target_index]
	segments[target_index] = segment
	return true


func cycle_segment_blend(segments: Array[Dictionary], index: int) -> int:
	if index < 0 or index >= segments.size():
		return -1
	var current := int(segments[index].get("transition_frames", 0))
	var next := 3 if current == 0 else (6 if current == 3 else 0)
	segments[index]["transition_frames"] = next
	return next
