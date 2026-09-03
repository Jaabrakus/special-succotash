class_name SocomTournamentRoundRules
extends RefCounted

## Loads and normalizes the saved rules consumed by every authoritative arena.

const PROFILE_PATH := "res://config/network/tournament_round_rules.json"
const DEFAULTS := {
	"schema_version": 1,
	"round_time_limit_seconds": 40.0,
	"max_regulation_rounds": 6,
	"sudden_death_vote_seconds": 10.0,
	"timeout_health_epsilon": 0.01,
	"sudden_death_timeout_policy": "replay_until_elimination",
}


static func load_profile() -> Dictionary:
	var profile := DEFAULTS.duplicate(true)
	if not FileAccess.file_exists(PROFILE_PATH):
		return profile
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if file == null:
		return profile
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return profile
	var document := parsed as Dictionary
	profile["round_time_limit_seconds"] = maxf(
		1.0,
		float(document.get("round_time_limit_seconds", profile["round_time_limit_seconds"]))
	)
	profile["max_regulation_rounds"] = maxi(
		1,
		int(document.get("max_regulation_rounds", profile["max_regulation_rounds"]))
	)
	profile["sudden_death_vote_seconds"] = maxf(
		1.0,
		float(document.get("sudden_death_vote_seconds", profile["sudden_death_vote_seconds"]))
	)
	profile["timeout_health_epsilon"] = maxf(
		0.0,
		float(document.get("timeout_health_epsilon", profile["timeout_health_epsilon"]))
	)
	profile["sudden_death_timeout_policy"] = String(
		document.get("sudden_death_timeout_policy", profile["sudden_death_timeout_policy"])
	)
	return profile
