extends SceneTree

const Router := preload("res://scripts/player/operator_presentation_router.gd")

var failures: Array[String] = []
var consumed_plans: Array[Dictionary] = []


func _initialize() -> void:
	var slots := {
		"aim_idle": "res://aim.fbx",
		"idle_crouch": "res://crouch.fbx",
		"idle_prone": "res://prone.fbx",
		"combat_fire": "res://fire.fbx",
		"crouch_fire": "res://crouch_fire.fbx",
		"prone_fire": "res://prone_fire.fbx",
		"reload": "res://reload.fbx",
		"prone_reload": "res://prone_reload.fbx",
	}
	var rules := {
		"combat_fire": {
			"layer": "UPPER_BODY",
			"blend_in_seconds": 0.04,
			"blend_out_seconds": 0.10,
			"return_state": "CURRENT_BASE",
		},
		"crouch_fire": {
			"layer": "UPPER_BODY",
			"blend_in_seconds": 0.04,
			"blend_out_seconds": 0.10,
			"return_state": "CURRENT_BASE",
		},
	}
	var routes := {
		"FIRE_ACCEPTED": {
			"default_state": "combat_fire",
			"posture_states": {
				"STANDING": "combat_fire",
				"CROUCHED": "crouch_fire",
				"PRONE": "prone_fire",
			},
			"family_states": {
				"TWO_HAND_RIFLE": {
					"default_state": "combat_fire",
					"posture_states": {"CROUCHED": "crouch_fire"},
				},
			},
			"effects": ["ENTER_READY_AIM", "RAIL_TO_BLUE_LINE"],
		},
		"RELOAD_STARTED": {
			"default_state": "reload",
			"posture_states": {"PRONE": "prone_reload"},
		},
	}
	var router := Router.new()
	router.configure(slots, rules, routes)
	var fire := router.resolve(&"FIRE_ACCEPTED", {
		"posture": "CROUCHED",
		"weapon_family": "TWO_HAND_RIFLE",
		"current_base_state": "crouch_forward",
	})
	_expect(bool(fire.get("valid", false)), "a connected semantic event resolves")
	_expect(
		String(fire.get("state", "")) == "crouch_fire"
		and String(fire.get("layer", "")) == "UPPER_BODY",
		"posture and weapon family select one visual state and body layer"
	)
	_expect(
		String(fire.get("resolved_return_state", "")) == "crouch_forward",
		"CURRENT_BASE returns to the live locomotion state"
	)
	_expect(
		"RAIL_TO_BLUE_LINE" not in (fire.get("effects", []) as Array),
		"the router rejects retired live blue-line relocation data"
	)
	_expect(
		"ENTER_READY_AIM" in (fire.get("effects", []) as Array),
		"valid fire enters the shared ready-aim presentation state"
	)
	var applied := router.present(
		&"FIRE_ACCEPTED",
		{
			"posture": "CROUCHED",
			"weapon_family": "TWO_HAND_RIFLE",
			"current_base_state": "idle_crouch",
		},
		Callable(self, "_consume")
	)
	_expect(
		bool(applied.get("applied", false)) and consumed_plans.size() == 1,
		"the router sends one immutable presentation plan to one consumer"
	)
	var missing := router.present(
		&"JUMPED",
		{"posture": "STANDING"},
		Callable(self, "_consume")
	)
	_expect(
		not bool(missing.get("valid", true)) and consumed_plans.size() == 1,
		"an unconnected event cannot silently play a fallback clip"
	)
	_expect(
		router.describe(fire).contains("FIRE_ACCEPTED")
		and router.describe(fire).contains("crouch_fire"),
		"the low-code UI receives a readable decision trace"
	)
	_finish()


func _consume(plan: Dictionary) -> bool:
	consumed_plans.append(plan.duplicate(true))
	return true


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PRESENTATION_ROUTER_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("PRESENTATION_ROUTER_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("OPERATOR_PRESENTATION_ROUTER_REGRESSION PASS")
		quit(0)
	else:
		print("OPERATOR_PRESENTATION_ROUTER_REGRESSION FAIL ", failures)
		quit(1)
