extends SceneTree

const StateContract := preload(
	"res://scripts/player/operator_animation_state_contract.gd"
)
const AnimationProfile := preload(
	"res://scripts/player/operator_animation_profile.gd"
)
const WorkshopRepository := preload(
	"res://scripts/labs/animation_workshop_repository.gd"
)
const LanguageParser := preload(
	"res://scripts/labs/animation_state_language_parser.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	var slots := {
		"idle_rifle": "res://idle.fbx",
		"aim_idle": "res://aim.fbx",
		"combat_fire": "res://fire.fbx",
	}
	var rules := StateContract.normalized_rules(slots, {
		"combat_fire": {
			"layer": "UPPER_BODY",
			"blend_in_seconds": 0.03,
			"blend_out_seconds": 0.11,
			"return_state": "aim_idle",
		},
		"idle_rifle": {
			"layer": "UPPER_BODY",
			"return_state": "missing_state",
		},
	})
	_expect(rules.size() == slots.size(), "every mapped clip receives an editable state rule")
	_expect(
		String(rules["combat_fire"]["layer"]) == "UPPER_BODY",
		"fire may own only the torso and arms"
	)
	_expect(
		String(rules["idle_rifle"]["layer"]) == "FULL_BODY",
		"locomotion cannot accidentally discard its legs"
	)
	_expect(
		String(rules["idle_rifle"]["return_state"]) == "idle_rifle",
		"invalid return states are repaired safely"
	)
	_expect(
		String(rules["combat_fire"]["return_state"]) == "aim_idle",
		"an explicit valid return state remains supported"
	)
	var contextual_rules := StateContract.normalized_rules(slots, {
		"combat_fire": {"return_state": "CURRENT_BASE"},
	})
	_expect(
		String(contextual_rules["combat_fire"]["return_state"]) == "CURRENT_BASE",
		"action states can return to the live movement and stance"
	)
	_expect(
		StateContract.clip_compatibility_error(
			"crouch_fire",
			"Rifle Sprint Right",
			"res://animations/sprint right.fbx"
		).contains("cannot drive"),
		"a locomotion take cannot silently become a crouched fire overlay"
	)
	_expect(
		StateContract.clip_compatibility_error(
			"combat_fire",
			"Rifle Aiming Idle",
			"res://animations/rifle aiming idle.fbx"
		).is_empty()
		and StateContract.clip_compatibility_error(
			"crouch_fire",
			"Crouch Rapid Fire",
			"res://animations/Crouch Rapid Fire.fbx"
		).is_empty(),
		"aim-idle and posture fire takes remain valid fire presentations"
	)

	var event_routes := StateContract.normalized_event_routes(slots, {
		"FIRE_ACCEPTED": {
			"default_state": "combat_fire",
			"posture_states": {"STANDING": "combat_fire"},
			"family_states": {
				"TWO_HAND_RIFLE": {
					"default_state": "aim_idle",
					"posture_states": {"STANDING": "aim_idle"},
				},
			},
			"return_policy": "CURRENT_BASE",
			"effects": ["ENTER_READY_AIM", "RAIL_TO_BLUE_LINE"],
		},
	})
	_expect(
		StateContract.resolve_event_state(
			event_routes,
			&"FIRE_ACCEPTED",
			&"STANDING"
		) == &"combat_fire",
		"a semantic fire event resolves through authored state data"
	)
	_expect(
		StateContract.resolve_event_state(
			event_routes,
			&"FIRE_ACCEPTED",
			&"STANDING",
			&"TWO_HAND_RIFLE"
		) == &"aim_idle",
		"an equipped family can specialize a semantic event without duplicating the graph"
	)
	var fire_presentation := StateContract.resolve_event_presentation(
		slots,
		rules,
		event_routes,
		&"FIRE_ACCEPTED",
		&"STANDING"
	)
	_expect(
		String(fire_presentation.get("state", "")) == "combat_fire"
		and String(fire_presentation.get("layer", "")) == "UPPER_BODY"
		and "ENTER_READY_AIM" in (fire_presentation.get("effects", []) as Array)
		and "RAIL_TO_BLUE_LINE" not in (fire_presentation.get("effects", []) as Array),
		"fire recipes retain ready aim and reject retired live rail relocation"
	)
	var proposal := LanguageParser.new().propose(
		"When a valid rifle shot happens, play this on torso and arms, blend in 0.04, blend out 0.10, return to current movement.",
		"combat_fire"
	)
	_expect(bool(proposal.get("valid", false)), "natural language creates a review proposal")
	_expect(
		String(proposal.get("event", "")) == "FIRE_ACCEPTED"
		and String(proposal.get("layer", "")) == "UPPER_BODY",
		"proposal identifies the fire event and upper-body layer"
	)
	_expect(
		is_equal_approx(float(proposal.get("blend_in_seconds", 0.0)), 0.04)
		and is_equal_approx(float(proposal.get("blend_out_seconds", 0.0)), 0.10),
		"proposal extracts entry and exit blend timing"
	)

	var profile := AnimationProfile.new()
	profile.load_project_map()
	_expect(
		profile.state_layer(&"combat_fire") == "UPPER_BODY",
		"runtime reads the authored fire body layer"
	)
	_expect(
		is_equal_approx(profile.state_blend_in_seconds(&"combat_fire"), 0.04),
		"runtime reads the authored fire blend-in"
	)
	_expect(
		profile.transition_blend_seconds(&"combat_fire", &"aim_idle") >= 0.10,
		"runtime blends from a fired state back into aim"
	)
	var saved_fire_presentation := profile.resolve_animation_event_presentation(
		&"FIRE_ACCEPTED",
		&"STANDING"
	)
	_expect(
		String(saved_fire_presentation.get("state", "")) == "aim_idle"
		and "ENTER_READY_AIM" in (saved_fire_presentation.get("effects", []) as Array)
		and "RAIL_TO_BLUE_LINE" not in (saved_fire_presentation.get("effects", []) as Array),
		"runtime resolves saved standing fire to recovery aim without relocating the rifle"
	)
	var saved_reload_presentation := profile.resolve_animation_event_presentation(
		&"RELOAD_STARTED",
		&"PRONE",
		&"TWO_HAND_RIFLE"
	)
	_expect(
		bool(saved_reload_presentation.get("valid", false))
		and String(saved_reload_presentation.get("state", "")) == "prone_reload",
		"runtime resolves saved reload through the same posture-aware presentation router"
	)

	var temp_path := "/private/tmp/socom-animation-state-authoring.json"
	var repository := WorkshopRepository.new()
	_expect(
		repository.save_state_authoring(temp_path, slots, rules, event_routes),
		"Studio saves clips and state behavior together"
	)
	_expect(
		repository.load_state_slots(temp_path) == slots,
		"saved clip assignments reload"
	)
	_expect(
		repository.load_state_rules(temp_path) == rules,
		"saved state behavior reloads"
	)
	_expect(
		StateContract.resolve_event_state(
			StateContract.normalized_event_routes(
				slots,
				repository.load_event_routes(temp_path)
			),
			&"FIRE_ACCEPTED",
			&"STANDING"
		) == &"combat_fire",
		"saved semantic event routes reload and resolve"
	)
	DirAccess.remove_absolute(temp_path)
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("ANIMATION_STATE_AUTHORING_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("ANIMATION_STATE_AUTHORING_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("ANIMATION_STATE_AUTHORING_REGRESSION PASS")
		quit(0)
	else:
		print("ANIMATION_STATE_AUTHORING_REGRESSION FAIL ", failures)
		quit(1)
