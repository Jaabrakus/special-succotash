extends SceneTree

const AuditorScript := preload(
	"res://scripts/labs/gunsmith/gunsmith_animation_quality_auditor.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var auditor = AuditorScript.new()
	_expect(is_equal_approx(auditor.score(0.5, 0.5, false), 92.0), "quality scoring remains stable")
	_expect(auditor.grade(92.0) == "A" and auditor.grade(81.0) == "C", "quality grades remain stable")
	var catalog := {
		&"idle_bad": "res://bad.fbx",
		&"aim_good": "res://good.fbx",
		&"reload_crouched": "res://reload.fbx",
	}
	var candidates: Array[StringName] = auditor.compatible_candidates("idle_standing", catalog)
	_expect(&"aim_good" in candidates and &"reload_crouched" not in candidates, "candidate filtering preserves intent and posture")
	var audit_result: Dictionary = await auditor.audit(
		{"idle_standing": "idle_bad"},
		[&"idle_standing"],
		{"idle_standing": "Standing Idle"},
		Callable(self, "_measure")
	)
	_expect(bool(audit_result.get("ok", false)), "auditor completes a measured slot pass")
	_expect(float(auditor.last_audit.get("idle_standing", {}).get("score", 0.0)) == 40.0, "auditor owns the last measured report")
	var fix_result: Dictionary = await auditor.build_autofix(
		{"idle_standing": "idle_bad"},
		[&"idle_standing"],
		{"idle_standing": "Standing Idle"},
		catalog,
		Callable(self, "_measure")
	)
	_expect(String((fix_result.get("slots", {}) as Dictionary).get("idle_standing", "")) == "aim_good", "safe auto-fix selects the stronger compatible clip")
	_expect(String(auditor.take_previous_slots().get("idle_standing", "")) == "idle_bad", "undo state remains owned by the auditor")
	if failures.is_empty():
		print("GUNSMITH_ANIMATION_QUALITY_AUDITOR_REGRESSION PASS")
		quit(0)
	else:
		push_error("GUNSMITH_ANIMATION_QUALITY_AUDITOR_REGRESSION FAIL %s" % failures)
		quit(1)


func _measure(_slot_name: String, clip_name: StringName) -> Dictionary:
	var quality_score := 95.0 if clip_name == &"aim_good" else 40.0
	return {
		"grade": "A" if quality_score >= 92.0 else "F",
		"score": quality_score,
		"trigger_error_cm": 0.5 if quality_score >= 92.0 else 8.0,
		"support_error_cm": 0.5,
		"support_free": false,
		"weapon_travel_cm": 1.0,
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
