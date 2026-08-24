extends SceneTree

const DictionaryContract := preload(
	"res://scripts/runtime/gameplay_event_dictionary.gd"
)
const AnimationContract := preload(
	"res://scripts/player/operator_animation_state_contract.gd"
)
const LanguageParser := preload(
	"res://scripts/labs/animation_state_language_parser.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	var dictionary_events := DictionaryContract.event_names()
	for event_name in AnimationContract.VALID_EVENTS:
		_expect(
			String(event_name) in dictionary_events,
			"presentation event has a plain-language dictionary entry: %s" % event_name
		)
	var fire := DictionaryContract.event_entry("FIRE_ACCEPTED")
	_expect(
		String(fire.get("truth_domain", "")) == "COMBAT"
		and String(fire.get("presentation_never", "")).contains("damage"),
		"fire entry separates combat authority from visual presentation"
	)
	_expect(
		DictionaryContract.event_from_text(
			"when the player shoots, move the arms then return"
		) == "FIRE_ACCEPTED",
		"ordinary shooting language resolves to the canonical event"
	)
	_expect(
		DictionaryContract.event_from_text(
			"when reload begins use the prone animation"
		) == "RELOAD_STARTED",
		"ordinary reload language resolves to the canonical event"
	)
	_expect(
		DictionaryContract.event_from_text(
			"when i realod keep the crouch legs"
		) == "RELOAD_STARTED",
		"the rule language tolerates a close single-word typing mistake"
	)
	var proposal := LanguageParser.new().propose(
		"when the player shoots play this on torso and arms then return",
		"combat_fire"
	)
	_expect(
		bool(proposal.get("valid", false))
		and String(proposal.get("event", "")) == "FIRE_ACCEPTED",
		"SOCOM Rules compiler consumes the shared Gameplay Dictionary"
	)
	var description := DictionaryContract.describe_event("FIRE_ACCEPTED")
	_expect(
		description.contains("Source of truth")
		and description.contains("Presentation must never"),
		"the editor can teach ownership without showing code"
	)
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("GAMEPLAY_DICTIONARY_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("GAMEPLAY_DICTIONARY_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("GAMEPLAY_EVENT_DICTIONARY_REGRESSION PASS")
		quit(0)
	else:
		print("GAMEPLAY_EVENT_DICTIONARY_REGRESSION FAIL ", failures)
		quit(1)
