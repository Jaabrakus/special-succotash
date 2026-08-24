extends SceneTree

const LanguageParser := preload(
	"res://scripts/labs/animation_state_language_parser.gd"
)
const AnimationProfile := preload(
	"res://scripts/player/operator_animation_profile.gd"
)

const SOURCE_RULE := (
	"when a valid rifle shot happens, play this on torso and arms, "
	+ "blend in 0.04, blend out 0.10, return to current movement"
)

var failures: Array[String] = []


func _initialize() -> void:
	var proposal := LanguageParser.new().propose(SOURCE_RULE, "combat_fire")
	_expect(bool(proposal.get("valid", false)), "natural language produces a review proposal")
	_expect(
		String(proposal.get("event", "")) == "FIRE_ACCEPTED"
		and String(proposal.get("state", "")) == "combat_fire",
		"the sentence compiles to valid fire and combat fire"
	)
	_expect(
		String(proposal.get("layer", "")) == "UPPER_BODY"
		and is_equal_approx(float(proposal.get("blend_in_seconds", 0.0)), 0.04)
		and is_equal_approx(float(proposal.get("blend_out_seconds", 0.0)), 0.10),
		"the sentence compiles torso ownership and exact blend timing"
	)
	var profile := AnimationProfile.new()
	profile.load_project_map()
	var saved_rule: Dictionary = profile.state_rules.get("combat_fire", {})
	_expect(
		String(saved_rule.get("source_rule", "")) == SOURCE_RULE
		and String(saved_rule.get("authoring_mode", "")) == "SOCOM_RULES",
		"the saved state keeps the human sentence as its authoring source"
	)
	var standing := profile.resolve_animation_event_presentation(
		&"FIRE_ACCEPTED",
		&"STANDING",
		&"TWO_HAND_RIFLE"
	)
	_expect(
		bool(standing.get("valid", false))
		and String(standing.get("state", "")) == "combat_fire"
		and String(standing.get("layer", "")) == "UPPER_BODY"
		and String(standing.get("return_policy", "")) == "CURRENT_BASE",
		"the saved sentence resolves through the same runtime presentation router"
	)
	_expect(
		"RAIL_TO_BLUE_LINE" in (standing.get("effects", []) as Array),
		"the compiled rule retains the verified blue-line fire effect"
	)
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("SOCOM_RULE_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("SOCOM_RULE_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("SOCOM_RULE_END_TO_END_REGRESSION PASS")
		quit(0)
	else:
		print("SOCOM_RULE_END_TO_END_REGRESSION FAIL ", failures)
		quit(1)
