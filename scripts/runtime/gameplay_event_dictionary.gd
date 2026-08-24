@tool
class_name SocomGameplayEventDictionary
extends RefCounted

## Plain-language contract shared by human authoring, natural-language tools,
## and runtime diagnostics. This file describes authority; it grants none.

const SOURCE_TRUTHS: Dictionary = {
	"INPUT": {
		"label": "Input intent",
		"owner": "Input Map",
		"meaning": "What the player asked to do. Input never proves the action happened.",
	},
	"PLAYER": {
		"label": "Player state",
		"owner": "Character gameplay controller",
		"meaning": "Movement, collision, standing, crouching, prone, and mobility state.",
	},
	"WEAPON": {
		"label": "Weapon state",
		"owner": "Weapon gameplay controller",
		"meaning": "Equipped weapon, ammunition, cadence, reload rules, and shot requests.",
	},
	"COMBAT": {
		"label": "Combat authority",
		"owner": "Server-facing combat rules",
		"meaning": "Accepted shots, hit detection, hurtboxes, damage, health, and death.",
	},
	"PRESENTATION": {
		"label": "Character presentation",
		"owner": "Operator Presentation Router",
		"meaning": "Animation, body layer, blending, IK, visual effects, and contextual return.",
	},
	"MAP_MATCH": {
		"label": "Map and match",
		"owner": "Map and match runtime",
		"meaning": "Geometry, boundaries, teams, spawns, objectives, and round state.",
	},
}

const EVENTS: Dictionary = {
	"WEAPON_EQUIPPED": {
		"label": "Weapon Equipped",
		"aliases": ["equip", "equipped", "pick up weapon", "switch weapon"],
		"meaning": "Gameplay changed the operator's active weapon.",
		"truth_domain": "WEAPON",
		"emitter": "Authorized loadout or pickup system",
		"accepted_when": "The weapon change is valid and the active loadout was updated.",
		"context": ["weapon id", "weapon family", "posture"],
		"presentation_may": "Apply the weapon family, ready pose, sockets, and visual weapon.",
		"presentation_never": "Grant ownership of a weapon or change ammunition.",
	},
	"FIRE_ACCEPTED": {
		"label": "Valid Fire",
		"aliases": ["fire", "shot", "shoot", "valid shot", "weapon fired"],
		"meaning": "The weapon authority accepted one real shot.",
		"truth_domain": "COMBAT",
		"emitter": "Weapon gameplay authority after ammo and cadence validation",
		"accepted_when": "The weapon can fire, has ammunition, and the shot sequence is valid.",
		"context": ["weapon family", "posture", "current movement", "shot sequence"],
		"presentation_may": "Play fire animation, raise the rail to the blue line, and show effects.",
		"presentation_never": "Create a bullet, spend ammo, redirect aim, or apply damage.",
	},
	"RELOAD_STARTED": {
		"label": "Reload Started",
		"aliases": ["reload", "start reload", "reload begins"],
		"meaning": "Gameplay accepted a reload and reserved its completion lifecycle.",
		"truth_domain": "WEAPON",
		"emitter": "Weapon reload coordinator",
		"accepted_when": "The weapon needs rounds, reserve ammo exists, and no reload is pending.",
		"context": ["weapon family", "posture", "reload duration", "current movement"],
		"presentation_may": "Play the posture-aware reload and emit its completion cue.",
		"presentation_never": "Refill ammo before the accepted completion cue.",
	},
	"POSTURE_CHANGED": {
		"label": "Posture Changed",
		"aliases": ["posture", "stance", "crouch", "prone", "stand"],
		"meaning": "The authoritative character posture changed.",
		"truth_domain": "PLAYER",
		"emitter": "Character gameplay controller",
		"accepted_when": "Collision and movement rules allow the new posture.",
		"context": ["previous posture", "new posture", "movement state"],
		"presentation_may": "Transition to the matching standing, crouched, or prone visuals.",
		"presentation_never": "Resize collision or approve an obstructed posture change.",
	},
	"JUMPED": {
		"label": "Jumped",
		"aliases": ["jump", "jumped", "airborne"],
		"meaning": "Gameplay applied a valid jump or airborne transition.",
		"truth_domain": "PLAYER",
		"emitter": "Character gameplay controller",
		"accepted_when": "The character can jump and gameplay applied vertical movement.",
		"context": ["movement direction", "vertical speed", "weapon family"],
		"presentation_may": "Play takeoff, airborne, and landing visuals.",
		"presentation_never": "Move the CharacterBody or invent vertical velocity.",
	},
	"GRENADE_RELEASED": {
		"label": "Grenade Released",
		"aliases": ["grenade", "throw", "toss", "release grenade"],
		"meaning": "The authored hand-release cue authorized one grenade launch.",
		"truth_domain": "COMBAT",
		"emitter": "Grenade gameplay coordinator",
		"accepted_when": "A grenade is equipped, the throw is valid, and the release cue is reached.",
		"context": ["grenade type", "throw strength", "posture", "trajectory"],
		"presentation_may": "Play the throw take, arc preview, particles, sound, and flash visuals.",
		"presentation_never": "Spawn extra grenades or change blast damage and radius.",
	},
	"HIT_RECEIVED": {
		"label": "Hit Received",
		"aliases": ["hit", "damage", "shot by", "was hit"],
		"meaning": "Combat authority confirmed damage to this operator.",
		"truth_domain": "COMBAT",
		"emitter": "Server-facing hit and damage system",
		"accepted_when": "An authoritative shot intersects a valid hurtbox.",
		"context": ["body region", "damage", "direction", "remaining health"],
		"presentation_may": "Play a bounded hit reaction, camera feedback, sound, and particles.",
		"presentation_never": "Choose the hurtbox, multiply damage, or change health.",
	},
	"DIED": {
		"label": "Died",
		"aliases": ["death", "died", "killed", "dead"],
		"meaning": "Combat authority set this operator's health to the dead state.",
		"truth_domain": "COMBAT",
		"emitter": "Server-facing health and death system",
		"accepted_when": "Authoritative health reaches the death threshold.",
		"context": ["damage direction", "body region", "weapon", "death sequence"],
		"presentation_may": "Select and play one death presentation.",
		"presentation_never": "Decide whether the player died, respawn them, or award a kill.",
	},
}


static func event_names() -> Array[String]:
	var names: Array[String] = []
	for raw_name in EVENTS.keys():
		names.append(String(raw_name))
	return names


static func event_entry(event_name: String) -> Dictionary:
	var raw: Variant = EVENTS.get(event_name.to_upper(), {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


static func event_from_text(text: String) -> String:
	var normalized := text.strip_edges().to_lower()
	for event_name in EVENTS.keys():
		var entry: Dictionary = EVENTS[event_name]
		for alias in entry.get("aliases", []):
			var alias_text := String(alias)
			if alias_text in normalized or _fuzzy_single_word_match(normalized, alias_text):
				return String(event_name)
	return ""


static func _fuzzy_single_word_match(text: String, alias: String) -> bool:
	if " " in alias or alias.length() < 4:
		return false
	var cleaned := text
	for separator in [",", ".", "!", "?", ":", ";", "(", ")"]:
		cleaned = cleaned.replace(separator, " ")
	for raw_token in cleaned.split(" ", false):
		var token := String(raw_token)
		if (
			token.length() >= 4
			and absi(token.length() - alias.length()) <= 2
			and token.left(1) == alias.left(1)
			and _edit_distance(token, alias) <= (2 if alias.length() >= 5 else 1)
		):
			return true
	return false


static func _edit_distance(left: String, right: String) -> int:
	var previous: Array[int] = []
	for column in range(right.length() + 1):
		previous.append(column)
	for row in range(1, left.length() + 1):
		var current: Array[int] = [row]
		for column in range(1, right.length() + 1):
			var substitution_cost := (
				0
				if left.unicode_at(row - 1) == right.unicode_at(column - 1)
				else 1
			)
			current.append(mini(
				mini(current[column - 1] + 1, previous[column] + 1),
				previous[column - 1] + substitution_cost
			))
		previous = current
	return previous[right.length()]


static func describe_event(event_name: String) -> String:
	var entry := event_entry(event_name)
	if entry.is_empty():
		return "%s is not defined in the Gameplay Dictionary." % event_name
	var truth_domain := String(entry.get("truth_domain", ""))
	var domain: Dictionary = SOURCE_TRUTHS.get(truth_domain, {})
	return (
		"%s — %s\n"
		+ "Meaning: %s\n"
		+ "Source of truth: %s — %s\n"
		+ "Emitted by: %s\n"
		+ "Accepted when: %s\n"
		+ "Carries: %s\n"
		+ "Presentation may: %s\n"
		+ "Presentation must never: %s"
	) % [
		event_name,
		String(entry.get("label", event_name)),
		String(entry.get("meaning", "")),
		String(domain.get("label", truth_domain)),
		String(domain.get("owner", "Unknown")),
		String(entry.get("emitter", "Unknown")),
		String(entry.get("accepted_when", "Not documented")),
		", ".join(entry.get("context", [])),
		String(entry.get("presentation_may", "Nothing")),
		String(entry.get("presentation_never", "Change gameplay authority")),
	]
