extends SceneTree

const CASTING_REPOSITORY := preload(
	"res://scripts/labs/animation_casting_repository.gd"
)
const WEAPON_RIG_PREVIEW := preload(
	"res://scripts/labs/weapon_rig_preview_loader.gd"
)

var failures: Array[String] = []
var temp_path := "/private/tmp/animation_casting_regression.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var repository = CASTING_REPOSITORY.new()
	var entry := {
		"display": "[Rifle] Run Forward",
		"key": "rifle_run_forward",
		"type": "FBX",
		"path": "res://test/rifle_run_forward.fbx",
	}
	var board: Dictionary = repository.empty_board()
	board = repository.save_review(
		board,
		entry,
		"use",
		{"legs_root": true, "torso_spine": true},
		0.2,
		1.1
	)
	_expect(repository.save_board(temp_path, board), "casting decisions save as durable project data")
	var loaded: Dictionary = repository.load_board(temp_path)
	var record: Dictionary = repository.record_for(loaded, entry)
	_expect(
		String(record.get("decision", "")) == "use"
		and bool((record.get("regions", {}) as Dictionary).get("legs_root", false))
		and bool((record.get("regions", {}) as Dictionary).get("torso_spine", false)),
		"casting preserves the selected connected body regions"
	)
	var frame_range: Dictionary = record.get("frame_range", {})
	_expect(
		is_equal_approx(float(frame_range.get("start_seconds", 0.0)), 0.2)
		and is_equal_approx(float(frame_range.get("end_seconds", 0.0)), 1.1),
		"casting preserves the selected animation frame range"
	)
	var pivot := Node3D.new()
	var left_socket := Marker3D.new()
	var right_socket := Marker3D.new()
	pivot.add_child(left_socket)
	pivot.add_child(right_socket)
	pivot.position = Vector3(0.05, 0.0, 0.0)
	left_socket.position = Vector3(0.0, 0.0, 0.3)
	right_socket.position = Vector3.ZERO
	pivot.set_meta("canonical_weapon_pivot_transform", pivot.transform)
	left_socket.set_meta("canonical_socket_transform", left_socket.transform)
	right_socket.set_meta("canonical_socket_transform", right_socket.transform)
	var grip_config := {
		"animation_hand_maps": {
			"aim_idle": {"left_grip": {"x": 0.0, "y": 0.0, "z": 0.1}},
		},
	}
	_expect(
		WEAPON_RIG_PREVIEW.apply_animation_hand_map(
			grip_config,
			"res://clips/idle.fbx",
			pivot,
			left_socket,
			right_socket,
			&"STANDING",
			PackedStringArray(["aim_idle"])
		)
		and is_equal_approx(left_socket.position.z, 0.1),
		"Studio resolves a Gunsmith hand map through the semantic clip key"
	)
	_expect(
		not WEAPON_RIG_PREVIEW.apply_animation_hand_map(
			grip_config,
			"res://clips/unmapped.fbx",
			pivot,
			left_socket,
			right_socket
		)
		and is_equal_approx(left_socket.position.z, 0.3),
		"an unmapped clip resets to canonical weapon sockets instead of inheriting the previous grip"
	)
	pivot.free()

	var packed := load("res://animation_library_lab.tscn") as PackedScene
	var studio := packed.instantiate()
	root.add_child(studio)
	await process_frame
	await process_frame
	_expect(
		studio.find_child("CastingModeButton", true, false) != null
		and studio.find_child("CastingPage", true, false) != null,
		"Animation Studio exposes one Animation Casting workspace"
	)
	_expect(
		studio.find_child("CastingRegion_legs_root", true, false) != null
		and studio.find_child("CastingRegion_torso_spine", true, false) != null
		and studio.find_child("CastingRegion_hands_weapon", true, false) != null,
		"Casting offers safe connected body-region choices"
	)
	_expect(
		studio.find_child("CastingDecision_use", true, false) != null
		and studio.find_child("CastingDecision_repair", true, false) != null
		and studio.find_child("CastingDecision_pass", true, false) != null,
		"Casting provides Use, Repair, and Pass decisions"
	)
	_expect(
		studio.find_child("AnimationCastingGripGuides", true, false) != null
		and studio.find_child("AnimationCastingAdjustGrip", true, false) != null
		and studio.find_child("AnimationCastingCycleWeapon", true, false) != null,
		"Casting exposes grip dots, per-clip grip editing, and weapon selection"
	)
	var state_slots_before: Dictionary = studio.get("state_slots").duplicate(true)
	studio.set("animation_casting_board_path", temp_path)
	studio.call("_load_animation_casting_board")
	studio.call("_show_editor_page", "Casting")
	studio.call("_casting_region_toggled", true, "legs_root")
	var selected_entry: Dictionary = studio.call("_casting_current_entry")
	studio.call("_casting_save_decision", "use")
	var studio_board: Dictionary = studio.get("animation_casting_board")
	var studio_record: Dictionary = repository.record_for(studio_board, selected_entry)
	_expect(
		String(studio_record.get("decision", "")) == "use"
		and bool((studio_record.get("regions", {}) as Dictionary).get("legs_root", false)),
		"one Casting choice saves the selected clip and advances the review deck"
	)
	_expect(
		studio.get("state_slots") == state_slots_before,
		"Casting review cannot silently change playable animation states"
	)
	studio.call("_casting_open_grip_editor")
	_expect(
		String(studio.get("active_editor_page")) == "Pose"
		and bool(studio.get("animation_correction_enabled")),
		"Adjust This Clip's Grip opens Rig & Hands on the same animation"
	)
	studio.queue_free()
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(temp_path)
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("ANIMATION_CASTING_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("ANIMATION_CASTING_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("ANIMATION_CASTING_REGRESSION PASS")
		quit(0)
	else:
		print("ANIMATION_CASTING_REGRESSION FAIL ", failures)
		quit(1)
