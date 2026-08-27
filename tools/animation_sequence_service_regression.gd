extends SceneTree

const SequenceService := preload("res://scripts/labs/animation_sequence_service.gd")
const ClipEditor := preload("res://scripts/labs/animation_clip_editor.gd")
const LayerComposer := preload("res://scripts/player/animation_layer_composer.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var service = SequenceService.new()
	var regions := {"full_body": true}
	service.toggle_region(regions, "left_arm")
	service.toggle_region(regions, "head")
	_expect(service.selected_region_keys(regions) == ["left_arm", "head"], "sequence service owns multi-region body selection")
	service.toggle_region(regions, "full_body")
	_expect(service.selected_region_keys(regions) == ["full_body"], "full-body selection clears masked lanes")

	var source := _make_animation()
	var segments: Array[Dictionary] = [{
		"animation": source,
		"start": 0.0,
		"end": 0.5,
		"display": "first",
		"layer": "full_body",
		"transition_frames": 0,
	}, {
		"animation": source,
		"start": 0.5,
		"end": 1.0,
		"display": "second",
		"layer": "full_body",
		"transition_frames": 3,
	}]
	_expect(service.lane_has_segments(segments, "full_body"), "sequence service detects populated body lanes")
	_expect(service.lane_has_segment_before(segments, 1, "full_body"), "sequence service detects earlier lane clips")
	_expect(service.cycle_segment_blend(segments, 1) == 6, "connector blend cycles from three to six frames")
	_expect(service.move_segment_in_lane(segments, 1, -1), "clips can move within their body lane")
	_expect(segments[0]["display"] == "second", "lane move preserves the requested ordering")
	var transition := segments[0].duplicate(true)
	transition["display"] = "transition"
	var selected_index := service.insert_transition(segments, 1, transition, true)
	_expect(selected_index == 1 and segments[1]["display"] == "transition", "transition clips attach before the selected cut")

	var built: Animation = service.build_animation(segments, ClipEditor.new(), LayerComposer.new(), 30.0)
	_expect(built != null and built.get_track_count() == 1, "sequence service bakes a playable output animation")
	_expect(built.length > 1.0, "baked sequence contains every connected cut")
	_finish()


func _make_animation() -> Animation:
	var animation := Animation.new()
	animation.length = 1.0
	var track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track, NodePath("GeneralSkeleton:mixamorig_Hips"))
	animation.track_insert_key(track, 0.0, Vector3.ZERO)
	animation.track_insert_key(track, 1.0, Vector3.UP)
	return animation


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("ANIMATION_SEQUENCE_SERVICE_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("ANIMATION_SEQUENCE_SERVICE_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("ANIMATION_SEQUENCE_SERVICE_REGRESSION PASS")
		quit(0)
	else:
		print("ANIMATION_SEQUENCE_SERVICE_REGRESSION FAIL ", failures)
		quit(1)
